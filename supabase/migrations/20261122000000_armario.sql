-- Universal Life AI — Armario digital (ropa), conjuntos y ciudad del hogar para el tiempo.
-- Requiere las migraciones de hogares/permisos.

-- 1. Nuevo módulo de permisos. Se confirma antes de usarlo (PostgreSQL lo exige).
alter type public.app_module add value if not exists 'wardrobe';
commit;

-- 2. Permisos por defecto del armario para los miembros que ya existen.
--    Ver y crear: todos menos invitados. Editar y eliminar: todos menos invitados (solo lo suyo, ver RLS).
insert into public.member_permissions (member_id, module, can_view, can_create, can_edit, can_delete, can_approve)
select m.id, 'wardrobe', m.role <> 'guest', m.role <> 'guest', m.role <> 'guest', m.role <> 'guest', m.role = 'owner'
from public.members m
on conflict (member_id, module) do nothing;

-- Los miembros nuevos reciben el mismo permiso de armario.
create or replace function public.apply_default_permissions(mid uuid, r public.member_role)
returns void language plpgsql security definer set search_path = public as $$
declare
  m public.app_module;
begin
  foreach m in array enum_range(null::public.app_module) loop
    insert into member_permissions (member_id, module, can_view, can_create, can_edit, can_delete, can_approve)
    values (
      mid, m,
      case when m = 'wardrobe' then r <> 'guest' else
        r in ('owner', 'adult', 'teen') or (r = 'child' and m in ('dashboard', 'shopping', 'recipes'))
        or (r = 'guest' and m in ('dashboard', 'shopping')) end,
      case when m = 'wardrobe' then r <> 'guest' else
        r in ('owner', 'adult') or (r = 'teen' and m in ('pantry', 'shopping', 'recipes'))
        or (r = 'child' and m = 'shopping') end,
      case when m = 'wardrobe' then r <> 'guest' else
        r in ('owner', 'adult') or (r = 'teen' and m in ('pantry', 'shopping')) end,
      case when m = 'wardrobe' then r <> 'guest' else
        r in ('owner', 'adult') and m <> 'budget' or r = 'owner' end,
      r = 'owner'
    )
    on conflict (member_id, module) do nothing;
  end loop;
end;
$$;
revoke execute on function public.apply_default_permissions(uuid, public.member_role) from public, anon, authenticated;

-- 3. Ciudad del hogar (para el outfit según el tiempo). La edita el administrador.
alter table public.households
  add column if not exists city_name text check (char_length(city_name) <= 80),
  add column if not exists latitude double precision check (latitude between -90 and 90),
  add column if not exists longitude double precision check (longitude between -180 and 180);

-- 4. Prendas y conjuntos
create type public.garment_category as enum ('top', 'bottom', 'dress', 'outerwear', 'shoes', 'accessory');

create or replace function public.my_member_id(hid uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select id from members where household_id = hid and user_id = auth.uid() and status = 'active';
$$;

create table public.garments (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  member_id uuid not null references public.members (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  category public.garment_category not null,
  color text not null default 'otro' check (char_length(color) <= 30),
  seasons text[] not null default '{spring,summer,autumn,winter}'
    check (seasons <@ array['spring', 'summer', 'autumn', 'winter']),
  styles text[] not null default '{}' check (cardinality(styles) <= 10),
  warmth smallint not null default 2 check (warmth between 1 and 3),
  photo_path text check (char_length(photo_path) <= 200),
  is_shared boolean not null default false,
  created_at timestamptz not null default now()
);
create index garments_member_idx on public.garments (member_id);

create table public.outfits (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  member_id uuid not null references public.members (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  garment_ids uuid[] not null check (cardinality(garment_ids) between 1 and 10),
  occasion text check (char_length(occasion) <= 30),
  is_favorite boolean not null default false,
  created_at timestamptz not null default now()
);
create index outfits_member_idx on public.outfits (member_id);

-- El miembro dueño de la prenda debe ser del mismo hogar.
create or replace function public.wardrobe_check_member()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from members where id = new.member_id and household_id = new.household_id) then
    raise exception 'member_not_in_household';
  end if;
  if tg_op = 'UPDATE' and (new.household_id <> old.household_id or new.member_id <> old.member_id) then
    raise exception 'owner_cannot_change';
  end if;
  return new;
end;
$$;
create trigger garments_check_member before insert or update on public.garments
  for each row execute function public.wardrobe_check_member();
create trigger outfits_check_member before insert or update on public.outfits
  for each row execute function public.wardrobe_check_member();

-- Puede ver: el dueño, el administrador del hogar, o cualquiera con permiso si la prenda es compartida.
-- Puede crear/editar/borrar: el dueño (con permiso) o el administrador.
create or replace function public.can_use_wardrobe(hid uuid, owner_member uuid, action text, shared boolean)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_household_owner(hid)
    or (public.has_permission(hid, 'wardrobe', action)
        and (owner_member = public.my_member_id(hid) or (action = 'view' and shared)));
$$;

alter table public.garments enable row level security;
alter table public.outfits enable row level security;

create policy garments_select on public.garments for select
  using (public.can_use_wardrobe(household_id, member_id, 'view', is_shared));
create policy garments_insert on public.garments for insert
  with check (public.can_use_wardrobe(household_id, member_id, 'create', false));
create policy garments_update on public.garments for update
  using (public.can_use_wardrobe(household_id, member_id, 'edit', false))
  with check (public.can_use_wardrobe(household_id, member_id, 'edit', false));
create policy garments_delete on public.garments for delete
  using (public.can_use_wardrobe(household_id, member_id, 'delete', false));

create policy outfits_select on public.outfits for select
  using (public.can_use_wardrobe(household_id, member_id, 'view', false));
create policy outfits_insert on public.outfits for insert
  with check (public.can_use_wardrobe(household_id, member_id, 'create', false));
create policy outfits_update on public.outfits for update
  using (public.can_use_wardrobe(household_id, member_id, 'edit', false))
  with check (public.can_use_wardrobe(household_id, member_id, 'edit', false));
create policy outfits_delete on public.outfits for delete
  using (public.can_use_wardrobe(household_id, member_id, 'delete', false));

-- 5. Fotos: almacenamiento privado. Ruta: <household_id>/<member_id>/<archivo>.jpg
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('wardrobe', 'wardrobe', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create or replace function public.wardrobe_path_ok(path text, action text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  parts text[] := string_to_array(path, '/');
  hid uuid;
  mid uuid;
begin
  if cardinality(parts) <> 3 then
    return false;
  end if;
  begin
    hid := parts[1]::uuid;
    mid := parts[2]::uuid;
  exception when others then
    return false;
  end;
  if not exists (select 1 from members where id = mid and household_id = hid) then
    return false;
  end if;
  if action = 'view' then
    -- Ver la foto si puede ver alguna prenda que la use.
    return public.can_use_wardrobe(hid, mid, 'view', false)
      or exists (select 1 from garments g where g.photo_path = path and g.is_shared
                 and public.has_permission(hid, 'wardrobe', 'view'));
  end if;
  return public.can_use_wardrobe(hid, mid, action, false);
end;
$$;

create policy wardrobe_photos_select on storage.objects for select to authenticated
  using (bucket_id = 'wardrobe' and public.wardrobe_path_ok(name, 'view'));
create policy wardrobe_photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'wardrobe' and public.wardrobe_path_ok(name, 'create'));
create policy wardrobe_photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'wardrobe' and public.wardrobe_path_ok(name, 'delete'));
