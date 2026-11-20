-- Universal Life AI — Lista de la compra compartida.
-- Requiere las migraciones de hogares/permisos y despensa.

create table public.shopping_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  quantity numeric(10, 2) not null default 1 check (quantity > 0),
  unit text not null default 'ud' check (unit in ('ud', 'g', 'kg', 'ml', 'l')),
  note text check (char_length(note) <= 200),
  barcode text check (barcode ~ '^[0-9]{8,14}$'),
  brand text check (char_length(brand) <= 80),
  is_checked boolean not null default false,
  checked_at timestamptz,
  price numeric(10, 2) check (price >= 0),
  added_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index shopping_items_household_idx on public.shopping_items (household_id, is_checked, created_at);

create or replace function public.shopping_before_write()
returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and new.household_id <> old.household_id then
    raise exception 'household_cannot_change';
  end if;
  if new.is_checked and (tg_op = 'INSERT' or not old.is_checked) then
    new.checked_at := now();
  elsif not new.is_checked then
    new.checked_at := null;
  end if;
  return new;
end;
$$;
create trigger shopping_items_before_write before insert or update on public.shopping_items
  for each row execute function public.shopping_before_write();

alter table public.shopping_items enable row level security;

create policy shopping_select on public.shopping_items for select
  using (public.has_permission(household_id, 'shopping', 'view'));
create policy shopping_insert on public.shopping_items for insert
  with check (public.has_permission(household_id, 'shopping', 'create') and added_by = auth.uid());
-- Marcar como comprado cuenta como editar.
create policy shopping_update on public.shopping_items for update
  using (public.has_permission(household_id, 'shopping', 'edit'))
  with check (public.has_permission(household_id, 'shopping', 'edit'));
create policy shopping_delete on public.shopping_items for delete
  using (public.has_permission(household_id, 'shopping', 'delete'));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.shopping_items;
  end if;
end $$;
