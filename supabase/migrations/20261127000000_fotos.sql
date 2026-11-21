-- Universal Life AI — Álbum familiar de fotos (privado).
-- Adultos y propietario: ver, subir, editar y borrar. Menores e invitados: nada
-- (regla de la familia); el administrador puede abrírselo desde Administrar.

-- 1. Nuevo módulo de permisos. Se confirma antes de usarlo (PostgreSQL lo exige).
alter type public.app_module add value if not exists 'photos';
commit;

-- 2. Permisos por defecto.
create or replace function public.apply_default_permissions(mid uuid, r public.member_role)
returns void language plpgsql security definer set search_path = public as $$
declare
  m public.app_module;
  minor boolean := r in ('teen', 'child');
  adult boolean := r in ('owner', 'adult');
  v boolean; c boolean; w boolean;
begin
  foreach m in array enum_range(null::public.app_module) loop
    if minor then
      v := m in ('dashboard', 'wardrobe', 'agenda');
      c := m in ('wardrobe', 'agenda');
      w := m = 'wardrobe';
      insert into member_permissions (member_id, module, can_view, can_create, can_edit, can_delete, can_approve)
      values (mid, m, v, c, w, w, false)
      on conflict (member_id, module) do nothing;
    elsif m = 'agenda' then
      insert into member_permissions (member_id, module, can_view, can_create, can_edit, can_delete, can_approve)
      values (mid, m, r <> 'guest', r <> 'guest', adult, adult, r = 'owner')
      on conflict (member_id, module) do nothing;
    elsif m = 'photos' then
      insert into member_permissions (member_id, module, can_view, can_create, can_edit, can_delete, can_approve)
      values (mid, m, adult, adult, adult, adult, r = 'owner')
      on conflict (member_id, module) do nothing;
    else
      insert into member_permissions (member_id, module, can_view, can_create, can_edit, can_delete, can_approve)
      values (
        mid, m,
        case when m = 'wardrobe' then r <> 'guest' else
          adult or (r = 'guest' and m in ('dashboard', 'shopping')) end,
        case when m = 'wardrobe' then r <> 'guest' else adult end,
        case when m = 'wardrobe' then r <> 'guest' else adult end,
        case when m = 'wardrobe' then r <> 'guest' else
          adult and m <> 'budget' or r = 'owner' end,
        r = 'owner'
      )
      on conflict (member_id, module) do nothing;
    end if;
  end loop;
end;
$$;
revoke execute on function public.apply_default_permissions(uuid, public.member_role) from public, anon, authenticated;

insert into public.member_permissions (member_id, module, can_view, can_create, can_edit, can_delete, can_approve)
select m.id, 'photos', a, a, a, a, m.role = 'owner'
from public.members m, lateral (select m.role in ('owner', 'adult') as a) x
on conflict (member_id, module) do nothing;

-- 3. Álbumes y fotos
create table public.albums (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index albums_household_idx on public.albums (household_id);

create table public.photos (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  album_id uuid references public.albums (id) on delete set null,
  path text not null unique check (char_length(path) <= 200),
  caption text check (char_length(caption) <= 200),
  taken_on date not null default current_date,
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index photos_household_idx on public.photos (household_id, taken_on desc);

-- La foto debe estar en la carpeta de su hogar y su álbum ser del mismo hogar.
create or replace function public.photos_check()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if split_part(new.path, '/', 1) <> new.household_id::text then
    raise exception 'path_not_in_household';
  end if;
  if new.album_id is not null and not exists (
    select 1 from albums where id = new.album_id and household_id = new.household_id) then
    raise exception 'album_not_in_household';
  end if;
  if tg_op = 'UPDATE' and (new.household_id <> old.household_id or new.path <> old.path
      or new.created_by is distinct from old.created_by) then
    raise exception 'cannot_change';
  end if;
  return new;
end;
$$;
create trigger photos_check before insert or update on public.photos
  for each row execute function public.photos_check();

-- Puede cambiar o borrar: quien tenga ese permiso, o quien lo subió si puede subir.
create or replace function public.can_touch_photo(hid uuid, owner uuid, action text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.has_permission(hid, 'photos', action)
    or (owner = auth.uid() and public.has_permission(hid, 'photos', 'create'));
$$;

alter table public.albums enable row level security;
alter table public.photos enable row level security;

create policy albums_select on public.albums for select using (public.has_permission(household_id, 'photos', 'view'));
create policy albums_insert on public.albums for insert
  with check (public.has_permission(household_id, 'photos', 'create') and created_by = auth.uid());
create policy albums_update on public.albums for update
  using (public.can_touch_photo(household_id, created_by, 'edit'))
  with check (public.can_touch_photo(household_id, created_by, 'edit'));
create policy albums_delete on public.albums for delete using (public.can_touch_photo(household_id, created_by, 'delete'));

create policy photos_select on public.photos for select using (public.has_permission(household_id, 'photos', 'view'));
create policy photos_insert on public.photos for insert
  with check (public.has_permission(household_id, 'photos', 'create') and created_by = auth.uid());
create policy photos_update on public.photos for update
  using (public.can_touch_photo(household_id, created_by, 'edit'))
  with check (public.can_touch_photo(household_id, created_by, 'edit'));
create policy photos_delete on public.photos for delete using (public.can_touch_photo(household_id, created_by, 'delete'));

-- 4. Archivos: almacenamiento privado. Ruta: <household_id>/<archivo>.jpg
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('family-photos', 'family-photos', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create or replace function public.photo_path_hid(path text)
returns uuid language plpgsql immutable as $$
begin
  if cardinality(string_to_array(path, '/')) <> 2 then return null; end if;
  return split_part(path, '/', 1)::uuid;
exception when others then
  return null;
end;
$$;

create policy family_photos_select on storage.objects for select to authenticated
  using (bucket_id = 'family-photos' and public.has_permission(public.photo_path_hid(name), 'photos', 'view'));
create policy family_photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'family-photos' and public.has_permission(public.photo_path_hid(name), 'photos', 'create'));
create policy family_photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'family-photos' and public.can_touch_photo(public.photo_path_hid(name), owner, 'delete'));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.photos;
    alter publication supabase_realtime add table public.albums;
  end if;
end $$;
