-- Universal Life AI — Fase 1: hogares, miembros, roles y permisos.
-- Todo el acceso pasa por Row Level Security (RLS). La app nunca usa la service key.

-- ---------------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------------
create type public.member_role as enum ('owner', 'adult', 'teen', 'child', 'guest');
create type public.member_status as enum ('active', 'suspended');
create type public.app_module as enum ('dashboard', 'pantry', 'shopping', 'budget', 'recipes');

-- ---------------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------------
create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  owner_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.members (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  user_id uuid references auth.users (id) on delete set null,
  display_name text not null check (char_length(display_name) between 1 and 60),
  role public.member_role not null,
  status public.member_status not null default 'active',
  created_at timestamptz not null default now(),
  unique (household_id, user_id)
);
create index members_user_idx on public.members (user_id);

create table public.member_permissions (
  member_id uuid not null references public.members (id) on delete cascade,
  module public.app_module not null,
  can_view boolean not null default false,
  can_create boolean not null default false,
  can_edit boolean not null default false,
  can_delete boolean not null default false,
  can_approve boolean not null default false,
  primary key (member_id, module)
);

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 60),
  role public.member_role not null check (role <> 'owner'),
  code text not null unique default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
  created_by uuid not null references auth.users (id) on delete cascade,
  expires_at timestamptz not null default now() + interval '7 days',
  accepted_by uuid references auth.users (id) on delete set null,
  accepted_at timestamptz
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  household_id uuid not null references public.households (id) on delete cascade,
  actor_id uuid,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index audit_log_household_idx on public.audit_log (household_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Funciones auxiliares (security definer para no recursar en RLS)
-- ---------------------------------------------------------------------------
create or replace function public.is_household_member(hid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from members
    where household_id = hid and user_id = auth.uid() and status = 'active'
  );
$$;

create or replace function public.is_household_owner(hid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from members
    where household_id = hid and user_id = auth.uid() and role = 'owner' and status = 'active'
  );
$$;

-- action: 'view' | 'create' | 'edit' | 'delete' | 'approve'
create or replace function public.has_permission(hid uuid, mod public.app_module, action text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from members m
    join member_permissions p on p.member_id = m.id and p.module = mod
    where m.household_id = hid and m.user_id = auth.uid() and m.status = 'active'
      and case action
        when 'view' then p.can_view
        when 'create' then p.can_create
        when 'edit' then p.can_edit
        when 'delete' then p.can_delete
        when 'approve' then p.can_approve
        else false
      end
  ) or public.is_household_owner(hid);
$$;

-- Permisos por defecto según el rol. El administrador puede cambiarlos después.
create or replace function public.apply_default_permissions(mid uuid, r public.member_role)
returns void language plpgsql security definer set search_path = public as $$
declare
  m public.app_module;
begin
  foreach m in array enum_range(null::public.app_module) loop
    insert into member_permissions (member_id, module, can_view, can_create, can_edit, can_delete, can_approve)
    values (
      mid, m,
      -- ver
      r in ('owner', 'adult', 'teen') or (r = 'child' and m in ('dashboard', 'shopping', 'recipes'))
        or (r = 'guest' and m in ('dashboard', 'shopping')),
      -- crear
      r in ('owner', 'adult') or (r = 'teen' and m in ('pantry', 'shopping', 'recipes'))
        or (r = 'child' and m = 'shopping'),
      -- editar
      r in ('owner', 'adult') or (r = 'teen' and m in ('pantry', 'shopping')),
      -- eliminar
      r in ('owner', 'adult') and m <> 'budget' or r = 'owner',
      -- aprobar
      r = 'owner'
    )
    on conflict (member_id, module) do nothing;
  end loop;
end;
$$;
revoke execute on function public.apply_default_permissions(uuid, public.member_role) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Operaciones (RPC) que la app llama
-- ---------------------------------------------------------------------------
create or replace function public.create_household(household_name text, owner_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  hid uuid;
  mid uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  insert into households (name, owner_id) values (trim(household_name), auth.uid()) returning id into hid;
  insert into members (household_id, user_id, display_name, role)
    values (hid, auth.uid(), trim(owner_name), 'owner') returning id into mid;
  perform apply_default_permissions(mid, 'owner');
  insert into audit_log (household_id, actor_id, action, details)
    values (hid, auth.uid(), 'household.created', jsonb_build_object('name', household_name));
  return hid;
end;
$$;

create or replace function public.accept_invitation(invite_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  inv invitations%rowtype;
  mid uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  select * into inv from invitations
    where code = upper(trim(invite_code)) and accepted_at is null and expires_at > now()
    for update;
  if not found then
    raise exception 'invalid_or_expired_code';
  end if;
  if exists (select 1 from members where household_id = inv.household_id and user_id = auth.uid()) then
    raise exception 'already_member';
  end if;
  insert into members (household_id, user_id, display_name, role)
    values (inv.household_id, auth.uid(), inv.display_name, inv.role) returning id into mid;
  perform apply_default_permissions(mid, inv.role);
  update invitations set accepted_by = auth.uid(), accepted_at = now() where id = inv.id;
  insert into audit_log (household_id, actor_id, action, details)
    values (inv.household_id, auth.uid(), 'member.joined',
            jsonb_build_object('member_id', mid, 'role', inv.role));
  return inv.household_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Auditoría automática de cambios administrativos
-- ---------------------------------------------------------------------------
create or replace function public.audit_member_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and (old.role, old.status, old.display_name) is distinct from (new.role, new.status, new.display_name) then
    insert into audit_log (household_id, actor_id, action, details)
      values (new.household_id, auth.uid(), 'member.updated',
              jsonb_build_object('member_id', new.id,
                                 'old', jsonb_build_object('role', old.role, 'status', old.status, 'display_name', old.display_name),
                                 'new', jsonb_build_object('role', new.role, 'status', new.status, 'display_name', new.display_name)));
  elsif tg_op = 'DELETE' and exists (select 1 from households where id = old.household_id) then
    insert into audit_log (household_id, actor_id, action, details)
      values (old.household_id, auth.uid(), 'member.removed',
              jsonb_build_object('member_id', old.id, 'display_name', old.display_name));
  end if;
  return coalesce(new, old);
end;
$$;
create trigger members_audit after update or delete on public.members
  for each row execute function public.audit_member_change();

create or replace function public.audit_permission_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  hid uuid;
begin
  select household_id into hid from members where id = new.member_id;
  insert into audit_log (household_id, actor_id, action, details)
    values (hid, auth.uid(), 'permission.updated',
            jsonb_build_object('member_id', new.member_id, 'module', new.module,
                               'view', new.can_view, 'create', new.can_create, 'edit', new.can_edit,
                               'delete', new.can_delete, 'approve', new.can_approve));
  return new;
end;
$$;
create trigger member_permissions_audit after update on public.member_permissions
  for each row execute function public.audit_permission_change();

-- El propietario no puede degradarse, suspenderse ni borrarse a sí mismo (el hogar se quedaría sin admin).
create or replace function public.protect_owner()
returns trigger language plpgsql as $$
begin
  -- Borrado en cascada del hogar completo: permitido.
  if tg_op = 'DELETE' and not exists (select 1 from public.households where id = old.household_id) then
    return old;
  end if;
  if old.role = 'owner' then
    if tg_op = 'DELETE' then
      raise exception 'owner_cannot_be_removed';
    elsif new.role <> 'owner' or new.status <> 'active' then
      raise exception 'owner_cannot_be_changed';
    end if;
  elsif tg_op = 'UPDATE' and new.role = 'owner' then
    raise exception 'only_one_owner';
  end if;
  return coalesce(new, old);
end;
$$;
create trigger members_protect_owner before update or delete on public.members
  for each row execute function public.protect_owner();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.households enable row level security;
alter table public.members enable row level security;
alter table public.member_permissions enable row level security;
alter table public.invitations enable row level security;
alter table public.audit_log enable row level security;

-- Hogares: los miembros lo ven; solo el propietario lo renombra. Se crean con create_household().
create policy households_select on public.households for select using (public.is_household_member(id));
create policy households_update on public.households for update
  using (public.is_household_owner(id)) with check (public.is_household_owner(id));

-- Miembros: los miembros ven a su familia; solo el propietario edita o elimina.
create policy members_select on public.members for select using (public.is_household_member(household_id));
create policy members_update on public.members for update
  using (public.is_household_owner(household_id)) with check (public.is_household_owner(household_id));
create policy members_delete on public.members for delete using (public.is_household_owner(household_id));

-- Permisos: cada uno ve los suyos; el propietario ve y edita todos.
create policy permissions_select on public.member_permissions for select using (
  exists (select 1 from public.members m where m.id = member_id
          and (m.user_id = auth.uid() or public.is_household_owner(m.household_id)))
);
create policy permissions_update on public.member_permissions for update
  using (exists (select 1 from public.members m where m.id = member_id and public.is_household_owner(m.household_id)))
  with check (exists (select 1 from public.members m where m.id = member_id and public.is_household_owner(m.household_id)));

-- Invitaciones: solo el propietario las crea, ve y borra. Se aceptan con accept_invitation().
create policy invitations_select on public.invitations for select using (public.is_household_owner(household_id));
create policy invitations_insert on public.invitations for insert
  with check (public.is_household_owner(household_id) and created_by = auth.uid());
create policy invitations_delete on public.invitations for delete using (public.is_household_owner(household_id));

-- Auditoría: solo lectura para el propietario.
create policy audit_select on public.audit_log for select using (public.is_household_owner(household_id));

-- ---------------------------------------------------------------------------
-- Permisos de ejecución
-- ---------------------------------------------------------------------------
revoke execute on function public.create_household(text, text) from public, anon;
revoke execute on function public.accept_invitation(text) from public, anon;
grant execute on function public.create_household(text, text) to authenticated;
grant execute on function public.accept_invitation(text) to authenticated;
