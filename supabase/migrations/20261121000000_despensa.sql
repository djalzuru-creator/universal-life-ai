-- Universal Life AI — Despensa del hogar.
-- Requiere la migración de hogares y permisos (has_permission, módulo 'pantry').

create type public.pantry_location as enum ('fridge', 'freezer', 'pantry', 'other');

create table public.pantry_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  brand text check (char_length(brand) <= 80),
  barcode text check (barcode ~ '^[0-9]{8,14}$'),
  quantity numeric(10, 2) not null default 1 check (quantity >= 0),
  unit text not null default 'ud' check (unit in ('ud', 'g', 'kg', 'ml', 'l')),
  location public.pantry_location not null default 'pantry',
  expires_on date,
  price numeric(10, 2) check (price >= 0),
  image_url text check (image_url ~ '^https://'),
  added_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index pantry_items_household_idx on public.pantry_items (household_id, expires_on);

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger pantry_items_touch before update on public.pantry_items
  for each row execute function public.touch_updated_at();

-- Nadie puede mover un producto a otro hogar.
create or replace function public.pantry_keep_household()
returns trigger language plpgsql as $$
begin
  if new.household_id <> old.household_id then
    raise exception 'household_cannot_change';
  end if;
  return new;
end;
$$;
create trigger pantry_items_keep_household before update on public.pantry_items
  for each row execute function public.pantry_keep_household();

alter table public.pantry_items enable row level security;

create policy pantry_select on public.pantry_items for select
  using (public.has_permission(household_id, 'pantry', 'view'));
create policy pantry_insert on public.pantry_items for insert
  with check (public.has_permission(household_id, 'pantry', 'create') and added_by = auth.uid());
create policy pantry_update on public.pantry_items for update
  using (public.has_permission(household_id, 'pantry', 'edit'))
  with check (public.has_permission(household_id, 'pantry', 'edit'));
create policy pantry_delete on public.pantry_items for delete
  using (public.has_permission(household_id, 'pantry', 'delete'));

-- Cambios en tiempo real para que toda la familia vea la despensa al momento.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.pantry_items;
  end if;
end $$;
