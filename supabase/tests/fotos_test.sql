-- Pruebas de seguridad del álbum de fotos.
\set ON_ERROR_STOP on
\o /dev/null
reset role;
grant select, insert, update, delete on all tables in schema public to authenticated;

insert into auth.users values
  ('00000000-0000-0000-0000-0000000000f1'), -- madre
  ('00000000-0000-0000-0000-0000000000f2'), -- padre
  ('00000000-0000-0000-0000-0000000000f3'), -- hija
  ('00000000-0000-0000-0000-0000000000f4'); -- otra familia

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u, false);
$$;
create function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if not ok then raise exception 'FALLO: %', label; end if;
  raise notice 'ok: %', label;
end $$;

set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
select public.create_household('Casa F', 'Mamá') as hid \gset
select set_config('test.hid', :'hid', false);
insert into invitations (household_id, display_name, role, created_by)
  values (:'hid', 'Papá', 'adult', '00000000-0000-0000-0000-0000000000f1') returning code as c_adult \gset
insert into invitations (household_id, display_name, role, created_by)
  values (:'hid', 'Lucía', 'teen', '00000000-0000-0000-0000-0000000000f1') returning code as c_teen \gset
insert into albums (household_id, name) values (:'hid', 'Verano') returning id as album \gset
insert into storage.objects (bucket_id, name) values ('family-photos', :'hid' || '/a.jpg');
insert into photos (household_id, album_id, path) values (:'hid', :'album', :'hid' || '/a.jpg');
select pg_temp.check((select count(*) from photos) = 1, 'madre sube una foto');

-- La ruta debe ser de su hogar
do $$ begin
  insert into photos (household_id, path) values (current_setting('test.hid')::uuid, gen_random_uuid() || '/x.jpg');
  raise exception 'FALLO: ruta de otro hogar';
exception when others then if sqlerrm like 'FALLO%' then raise; end if; raise notice 'ok: ruta de otro hogar rechazada'; end $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
select public.accept_invitation(:'c_adult');
select pg_temp.check((select count(*) from photos) = 1 and (select count(*) from storage.objects) = 1, 'padre ve el álbum');
insert into storage.objects (bucket_id, name) values ('family-photos', :'hid' || '/b.jpg');
insert into photos (household_id, path, caption) values (:'hid', :'hid' || '/b.jpg', 'Playa');
select pg_temp.check((select count(*) from photos) = 2, 'padre sube');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f3');
select public.accept_invitation(:'c_teen');
select pg_temp.check((select count(*) from photos) = 2 and (select count(*) from storage.objects) = 2, 'adolescente ve el álbum');
insert into storage.objects (bucket_id, name) values ('family-photos', :'hid' || '/c.jpg');
insert into photos (household_id, path, caption) values (:'hid', :'hid' || '/c.jpg', 'Mía');
select pg_temp.check((select count(*) from photos) = 3, 'adolescente sube');
update photos set caption = 'Mía 2' where caption = 'Mía';
select pg_temp.check(exists (select 1 from photos where caption = 'Mía 2'), 'adolescente cambia la suya');
delete from photos where caption = 'Playa';
select pg_temp.check((select count(*) from photos) = 3, 'adolescente no borra la del padre');
delete from storage.objects where name = :'hid' || '/b.jpg';
select pg_temp.check((select count(*) from storage.objects) = 3, 'adolescente no borra archivo del padre');
delete from photos where caption = 'Mía 2';
delete from storage.objects where name = :'hid' || '/c.jpg';
select pg_temp.check((select count(*) from photos) = 2 and (select count(*) from storage.objects) = 2, 'adolescente borra la suya');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f4');
select public.create_household('Casa X', 'X');
select pg_temp.check((select count(*) from photos) = 0 and (select count(*) from storage.objects) = 0, 'otra familia no ve nada');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
delete from photos where caption = 'Playa';
select pg_temp.check((select count(*) from photos) = 1, 'madre borra cualquiera');
\o
\echo FOTOS: TODAS LAS PRUEBAS PASARON
