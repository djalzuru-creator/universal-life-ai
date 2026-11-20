-- Pruebas de seguridad de la despensa. Se ejecuta después de permisos_test.sql en run.sh.
\set ON_ERROR_STOP on
\o /dev/null
reset role;
grant select, insert, update, delete on all tables in schema public to authenticated;

insert into auth.users values
  ('00000000-0000-0000-0000-0000000000d1'), -- propietaria
  ('00000000-0000-0000-0000-0000000000d2'), -- niño
  ('00000000-0000-0000-0000-0000000000d3'); -- otra familia

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u, false);
$$;
create function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if not ok then raise exception 'FALLO: %', label; end if;
  raise notice 'ok: %', label;
end $$;

set role authenticated;

select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
select public.create_household('Casa D', 'Ana') as hid \gset
select set_config('test.hid', :'hid', false);
insert into invitations (household_id, display_name, role, created_by)
  values (:'hid', 'Peque', 'child', '00000000-0000-0000-0000-0000000000d1') returning code \gset
insert into pantry_items (household_id, name, barcode, quantity, unit, location, expires_on)
  values (:'hid', 'Leche', '8410000000001', 2, 'l', 'fridge', current_date + 2);
select pg_temp.check((select count(*) from pantry_items) = 1, 'propietaria añade a la despensa');

-- Otra familia no ve ni toca la despensa
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d3');
select public.create_household('Casa E', 'Eva') as other \gset
select pg_temp.check((select count(*) from pantry_items) = 0, 'otra familia no ve la despensa');
do $$ begin
  insert into pantry_items (household_id, name) values (current_setting('test.hid')::uuid, 'Intruso');
  raise exception 'FALLO: otra familia insertó';
exception when others then
  if sqlerrm like 'FALLO%' then raise; end if;
  raise notice 'ok: otra familia no puede añadir';
end $$;

-- Un niño (por defecto no ve la despensa) no la ve
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d2');
select public.accept_invitation(:'code');
select pg_temp.check((select count(*) from pantry_items) = 0, 'niño sin permiso no ve la despensa');

-- La propietaria le da permiso de ver, pero no de borrar
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
update member_permissions set can_view = true
  where module = 'pantry' and member_id = (select id from members where role = 'child');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d2');
select pg_temp.check((select count(*) from pantry_items) = 1, 'niño con permiso ve la despensa');
delete from pantry_items;
update pantry_items set quantity = 0;
select pg_temp.check((select quantity from pantry_items) = 2, 'niño no puede editar ni borrar');

-- No se puede mover un producto a otro hogar
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
select set_config('test.other', :'other', false);
do $$ begin
  update pantry_items set household_id = current_setting('test.other')::uuid;
  raise exception 'FALLO: producto movido';
exception when others then
  if sqlerrm like 'FALLO%' then raise; end if;
  raise notice 'ok: producto no cambia de hogar';
end $$;

-- Código de barras inválido rechazado
do $$ begin
  insert into pantry_items (household_id, name, barcode) values (current_setting('test.hid')::uuid, 'X', 'abc');
  raise exception 'FALLO: código inválido aceptado';
exception when others then
  if sqlerrm like 'FALLO%' then raise; end if;
  raise notice 'ok: código de barras validado';
end $$;
\o
\echo DESPENSA: TODAS LAS PRUEBAS PASARON
