\set ON_ERROR_STOP on
\o /dev/null
reset role;
grant select, insert, update, delete on all tables in schema public to authenticated;
insert into auth.users values ('00000000-0000-0000-0000-0000000000e1'), ('00000000-0000-0000-0000-0000000000e2'), ('00000000-0000-0000-0000-0000000000e3');
create function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false); $$;
create function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin if not ok then raise exception 'FALLO: %', label; end if; raise notice 'ok: %', label; end $$;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select public.create_household('Casa P', 'Ana') as hid \gset
insert into invitations (household_id, display_name, role, created_by) values (:'hid', 'Teo', 'teen', '00000000-0000-0000-0000-0000000000e1') returning code \gset
insert into expenses (household_id, amount, category) values (:'hid', 45.5, 'supermercado');
insert into budget_limits (household_id, monthly_limit) values (:'hid', 600);
select pg_temp.check((select count(*) from expenses) = 1 and (select count(*) from budget_limits) = 1, 'administradora apunta gasto y límite');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
select public.accept_invitation(:'code');
select pg_temp.check((select count(*) from expenses) = 1, 'adolescente ve el presupuesto');
do $$ begin
  insert into expenses (household_id, amount, category) select household_id, 10, 'ocio' from expenses limit 1;
  raise exception 'FALLO: adolescente apuntó gasto';
exception when others then if sqlerrm like 'FALLO%' then raise; end if; raise notice 'ok: adolescente no apunta gastos'; end $$;
update budget_limits set monthly_limit = 99999;
select pg_temp.check((select monthly_limit from budget_limits) = 600, 'adolescente no cambia límites');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e3');
select public.create_household('Otra', 'X');
select pg_temp.check((select count(*) from expenses) = 0, 'otra familia no ve gastos');
\o
\echo PRESUPUESTO: TODAS LAS PRUEBAS PASARON
