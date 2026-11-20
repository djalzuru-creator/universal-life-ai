-- Pruebas de seguridad de la lista de la compra.
\set ON_ERROR_STOP on
\o /dev/null
reset role;
grant select, insert, update, delete on all tables in schema public to authenticated;

insert into auth.users values
  ('00000000-0000-0000-0000-0000000000c1'), -- padre
  ('00000000-0000-0000-0000-0000000000c2'), -- niña
  ('00000000-0000-0000-0000-0000000000c3'); -- otra familia

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u, false);
$$;
create function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if not ok then raise exception 'FALLO: %', label; end if;
  raise notice 'ok: %', label;
end $$;

set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select public.create_household('Casa C', 'Papá') as hid \gset
insert into invitations (household_id, display_name, role, created_by)
  values (:'hid', 'Sara', 'child', '00000000-0000-0000-0000-0000000000c1') returning code \gset
insert into shopping_items (household_id, name, quantity, unit) values (:'hid', 'Pan', 1, 'ud');
update shopping_items set is_checked = true;
select pg_temp.check((select checked_at is not null from shopping_items), 'al marcar se guarda la hora');
update shopping_items set is_checked = false;
select pg_temp.check((select checked_at is null from shopping_items), 'al desmarcar se borra la hora');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000c2');
select public.accept_invitation(:'code');
select pg_temp.check((select count(*) from shopping_items) = 1, 'niña ve la lista');
insert into shopping_items (household_id, name) values (:'hid', 'Galletas');
select pg_temp.check((select count(*) from shopping_items) = 2, 'niña añade a la lista');
update shopping_items set is_checked = true;
delete from shopping_items;
select pg_temp.check((select count(*) from shopping_items where is_checked) = 0, 'niña no marca comprado (sin permiso de editar)');
select pg_temp.check((select count(*) from shopping_items) = 2, 'niña no borra');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000c3');
select public.create_household('Casa X', 'X');
select pg_temp.check((select count(*) from shopping_items) = 0, 'otra familia no ve la lista');
\o
\echo COMPRA: TODAS LAS PRUEBAS PASARON
