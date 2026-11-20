-- Pruebas de seguridad del sistema de hogar y permisos. Ejecutar con: supabase/tests/run.sh
\set ON_ERROR_STOP on
\o /dev/null
grant select, insert, update, delete on all tables in schema public to authenticated;

insert into auth.users values
  ('00000000-0000-0000-0000-00000000000a'), -- propietario
  ('00000000-0000-0000-0000-00000000000b'), -- adolescente invitado
  ('00000000-0000-0000-0000-00000000000c'); -- desconocido

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u, false);
$$;
create function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if not ok then raise exception 'FALLO: %', label; end if;
  raise notice 'ok: %', label;
end $$;

set role authenticated;

-- 1. El propietario crea su hogar
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select public.create_household('Casa Alzuru', 'Dj') as hid \gset
select pg_temp.check((select count(*) from members where household_id = :'hid') = 1, 'propietario es miembro');
select pg_temp.check((select count(*) from member_permissions) = (select count(*) from unnest(enum_range(null::app_module))), 'propietario tiene todos los módulos');
select pg_temp.check((select bool_and(can_approve) from member_permissions), 'propietario puede aprobar todo');

-- 2. Invita a un adolescente
insert into invitations (household_id, display_name, role, created_by)
  values (:'hid', 'Hijo', 'teen', '00000000-0000-0000-0000-00000000000a') returning code \gset
select set_config('test.code', :'code', false);

-- 3. Un desconocido no ve nada
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select pg_temp.check((select count(*) from households) = 0, 'desconocido no ve hogares');
select pg_temp.check((select count(*) from members) = 0, 'desconocido no ve miembros');
select pg_temp.check((select count(*) from invitations) = 0, 'desconocido no ve invitaciones');

-- 4. El adolescente acepta la invitación
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select public.accept_invitation(lower(:'code'));
select pg_temp.check((select count(*) from members) = 2, 'adolescente ve a su familia');
select pg_temp.check((select count(distinct member_id) from member_permissions) = 1, 'adolescente solo ve sus permisos');
select pg_temp.check(not public.has_permission(:'hid', 'budget', 'edit'), 'adolescente no edita presupuesto');
select pg_temp.check(public.has_permission(:'hid', 'shopping', 'create'), 'adolescente añade a la compra');
select pg_temp.check((select count(*) from invitations) = 0, 'adolescente no ve invitaciones');
select pg_temp.check((select count(*) from audit_log) = 0, 'adolescente no ve auditoría');

-- 5. El adolescente no puede darse permisos ni cambiar su rol
update member_permissions set can_edit = true where module = 'budget';
update members set role = 'adult' where user_id = '00000000-0000-0000-0000-00000000000b';
select pg_temp.check(not public.has_permission(:'hid', 'budget', 'edit'), 'adolescente no se sube permisos');
select pg_temp.check((select role from members where user_id = '00000000-0000-0000-0000-00000000000b') = 'teen', 'adolescente no cambia su rol');

-- 6. El código no se puede reutilizar
do $$ begin
  perform public.accept_invitation(current_setting('test.code'));
  raise exception 'FALLO: código reutilizado';
exception when others then
  if sqlerrm like 'FALLO%' then raise; end if;
  raise notice 'ok: código de un solo uso';
end $$;

-- 7. El propietario cambia permisos, suspende y queda registrado
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
update member_permissions set can_view = false
  where module = 'budget' and member_id = (select id from members where role = 'teen');
update members set status = 'suspended' where role = 'teen';
select pg_temp.check((select count(*) from audit_log where action in ('permission.updated', 'member.updated')) = 2, 'cambios auditados');

select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select pg_temp.check((select count(*) from households) = 0, 'suspendido pierde acceso');

-- 8. El propietario no puede quedarse sin admin
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  update members set status = 'suspended' where role = 'owner';
  raise exception 'FALLO: propietario suspendido';
exception when others then
  if sqlerrm like 'FALLO%' then raise; end if;
  raise notice 'ok: propietario protegido';
end $$;

-- 9. Un usuario anónimo no puede crear hogares
reset role;
set role anon;
do $$ begin
  perform public.create_household('x', 'y');
  raise exception 'FALLO: anónimo creó hogar';
exception when others then
  if sqlerrm like 'FALLO%' then raise; end if;
  raise notice 'ok: anónimo bloqueado';
end $$;

-- 10. Borrar la cuenta del propietario borra el hogar en cascada
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-00000000000a';
select pg_temp.check((select count(*) from households) = 0, 'borrado en cascada');
\o
\echo TODAS LAS PRUEBAS PASARON
