-- Pruebas de seguridad del armario.
\set ON_ERROR_STOP on
\o /dev/null
reset role;
grant select, insert, update, delete on all tables in schema public to authenticated;

insert into auth.users values
  ('00000000-0000-0000-0000-0000000000a1'), -- madre (administradora)
  ('00000000-0000-0000-0000-0000000000a2'), -- hija adolescente
  ('00000000-0000-0000-0000-0000000000a3'), -- hijo adulto
  ('00000000-0000-0000-0000-0000000000a4'); -- otra familia

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u, false);
$$;
create function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if not ok then raise exception 'FALLO: %', label; end if;
  raise notice 'ok: %', label;
end $$;
create function pg_temp.expect_error(stmt text, label text) returns void language plpgsql as $$
begin
  execute stmt;
  raise exception 'FALLO: %', label;
exception when others then
  if sqlerrm like 'FALLO%' then raise; end if;
  raise notice 'ok: %', label;
end $$;

set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select public.create_household('Casa A', 'Mamá') as hid \gset
insert into invitations (household_id, display_name, role, created_by)
  values (:'hid', 'Lucía', 'teen', '00000000-0000-0000-0000-0000000000a1') returning code as c_teen \gset
insert into invitations (household_id, display_name, role, created_by)
  values (:'hid', 'Pablo', 'adult', '00000000-0000-0000-0000-0000000000a1') returning code as c_adult \gset
select pg_temp.check((select count(*) from member_permissions where module = 'wardrobe') = 1, 'nuevo hogar trae permiso de armario');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
select public.accept_invitation(:'c_teen');
select public.my_member_id(:'hid') as teen \gset
insert into garments (household_id, member_id, name, category, color) values (:'hid', :'teen', 'Vaquero', 'bottom', 'azul');
insert into garments (household_id, member_id, name, category, is_shared) values (:'hid', :'teen', 'Bufanda', 'accessory', true);
select pg_temp.check((select count(*) from garments) = 2, 'adolescente crea su ropa');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000a3');
select public.accept_invitation(:'c_adult');
select pg_temp.check((select count(*) from garments) = 1, 'hermano solo ve la prenda compartida');
select set_config('test.hid', :'hid', false), set_config('test.teen', :'teen', false);
select pg_temp.expect_error(
  format('insert into garments (household_id, member_id, name, category) values (%L, %L, %L, %L)',
         current_setting('test.hid'), current_setting('test.teen'), 'Falsa', 'top'),
  'hermano no añade ropa al armario de otra');
update garments set name = 'Robada';
select pg_temp.check((select count(*) from garments where name = 'Robada') = 0, 'hermano no edita ropa ajena');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select pg_temp.check((select count(*) from garments) = 2, 'administradora ve todo el armario familiar');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000a4');
select public.create_household('Casa B', 'Otro');
select pg_temp.check((select count(*) from garments) = 0, 'otra familia no ve nada');

-- Fotos
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
select set_config('test.path', :'hid' || '/' || :'teen' || '/foto.jpg', false);
insert into storage.objects (bucket_id, name) values ('wardrobe', current_setting('test.path'));
select pg_temp.check((select count(*) from storage.objects) = 1, 'adolescente sube su foto');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a3');
select pg_temp.check((select count(*) from storage.objects) = 0, 'hermano no ve fotos privadas ajenas');
select pg_temp.expect_error(
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'wardrobe',
         current_setting('test.hid') || '/' || current_setting('test.teen') || '/x.jpg'),
  'hermano no sube fotos al armario de otra');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a4');
select pg_temp.check((select count(*) from storage.objects) = 0, 'otra familia no ve fotos');

-- Conjuntos
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
insert into outfits (household_id, member_id, name, garment_ids)
  select :'hid', :'teen', 'Clase', array_agg(id) from garments;
select pg_temp.check((select count(*) from outfits) = 1, 'adolescente guarda un conjunto');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a3');
select pg_temp.check((select count(*) from outfits) = 0, 'hermano no ve conjuntos ajenos');

-- Quitar el permiso de armario deja sin acceso
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
update member_permissions set can_view = false where module = 'wardrobe' and member_id = :'teen';
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
select pg_temp.check((select count(*) from garments) = 0, 'sin permiso no ve su armario');
\o
\echo ARMARIO: TODAS LAS PRUEBAS PASARON
