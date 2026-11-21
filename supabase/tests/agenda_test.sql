-- Pruebas de seguridad de la agenda.
\set ON_ERROR_STOP on
\o /dev/null
reset role;
grant select, insert, update, delete on all tables in schema public to authenticated;

insert into auth.users values
  ('00000000-0000-0000-0000-0000000000a7'), -- madre
  ('00000000-0000-0000-0000-0000000000a8'), -- niño
  ('00000000-0000-0000-0000-0000000000a9'); -- otra familia

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u, false);
$$;
create function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if not ok then raise exception 'FALLO: %', label; end if;
  raise notice 'ok: %', label;
end $$;

set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a7');
select public.create_household('Casa A', 'Mamá') as hid \gset
select set_config('test.hid', :'hid', false);
insert into invitations (household_id, display_name, role, created_by)
  values (:'hid', 'Leo', 'child', '00000000-0000-0000-0000-0000000000a7') returning code \gset
insert into events (household_id, title, starts_at) values (:'hid', 'Dentista', now() + interval '1 day');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000a8');
select public.accept_invitation(:'code');
select pg_temp.check((select count(*) from events) = 1, 'niño ve la agenda');
select pg_temp.check(not public.has_permission(:'hid', 'pantry', 'view'), 'niño no ve la despensa');
insert into events (household_id, title, starts_at) values (:'hid', 'Fútbol', now() + interval '2 day');
select pg_temp.check((select count(*) from events) = 2, 'niño apunta un evento');
update events set title = 'Cambiado';
select pg_temp.check((select count(*) from events where title = 'Cambiado') = 1, 'niño solo cambia lo suyo');
delete from events;
select pg_temp.check((select count(*) from events) = 1, 'niño solo borra lo suyo');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000a7');
delete from events;
select pg_temp.check((select count(*) from events) = 0, 'madre borra cualquiera');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000a9');
select public.create_household('Casa X', 'X');
select pg_temp.check((select count(*) from events) = 0, 'otra familia no ve la agenda');
\o
\echo AGENDA: TODAS LAS PRUEBAS PASARON
