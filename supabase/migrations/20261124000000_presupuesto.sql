-- Universal Life AI — Presupuesto del hogar.

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  member_id uuid references public.members (id) on delete set null,
  amount numeric(10, 2) not null check (amount > 0 and amount < 1000000),
  category text not null check (category in ('supermercado', 'hogar', 'facturas', 'transporte', 'ocio', 'ropa', 'salud', 'educacion', 'otros')),
  description text check (char_length(description) <= 120),
  spent_on date not null default current_date,
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index expenses_household_idx on public.expenses (household_id, spent_on desc);

-- Límite mensual: del hogar (member_id nulo) o por miembro.
create table public.budget_limits (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  member_id uuid references public.members (id) on delete cascade,
  monthly_limit numeric(10, 2) not null check (monthly_limit > 0)
);
create unique index budget_limits_unique on public.budget_limits (household_id, coalesce(member_id, '00000000-0000-0000-0000-000000000000'::uuid));

create or replace function public.budget_check_member()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.member_id is not null and not exists (
    select 1 from members where id = new.member_id and household_id = new.household_id) then
    raise exception 'member_not_in_household';
  end if;
  if tg_op = 'UPDATE' and new.household_id <> old.household_id then
    raise exception 'household_cannot_change';
  end if;
  return new;
end;
$$;
create trigger expenses_check before insert or update on public.expenses
  for each row execute function public.budget_check_member();
create trigger budget_limits_check before insert or update on public.budget_limits
  for each row execute function public.budget_check_member();

alter table public.expenses enable row level security;
alter table public.budget_limits enable row level security;

create policy expenses_select on public.expenses for select using (public.has_permission(household_id, 'budget', 'view'));
create policy expenses_insert on public.expenses for insert
  with check (public.has_permission(household_id, 'budget', 'create') and created_by = auth.uid());
create policy expenses_update on public.expenses for update
  using (public.has_permission(household_id, 'budget', 'edit')) with check (public.has_permission(household_id, 'budget', 'edit'));
create policy expenses_delete on public.expenses for delete using (public.has_permission(household_id, 'budget', 'delete'));

-- Los límites solo los pone el administrador; los ve quien ve el presupuesto.
create policy limits_select on public.budget_limits for select using (public.has_permission(household_id, 'budget', 'view'));
create policy limits_write on public.budget_limits for all
  using (public.is_household_owner(household_id)) with check (public.is_household_owner(household_id));
