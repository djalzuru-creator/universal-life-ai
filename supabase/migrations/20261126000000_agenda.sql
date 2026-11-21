-- Universal Life AI — Agenda familiar.
-- Todos menos invitados la ven y apuntan eventos. Cada uno edita o borra lo suyo;
-- adultos y propietario pueden editar o borrar cualquiera.

-- 1. Nuevo módulo de permisos. Se confirma antes de usarlo (PostgreSQL lo exige).
alter type public.app_module add value if not exists 'agenda';
commit;

-- 2. Permisos por defecto (incluye la regla de menores: solo panel, armario y agenda).
create or replace function public.apply_default_permissions(mid uuid, r public.member_role)
returns void language plpgsql security definer set search_path = public as $$
declare
  m public.app_module;
  minor boolean := r in ('teen', 'child');
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
      values (mid, m, r <> 'guest', r <> 'guest', r in ('owner', 'adult'), r in ('owner', 'adult'), r = 'owner')
      on conflict (member_id, module) do nothing;
    else
      insert into member_permissions (member_id, module, can_view, can_create, can_edit, can_delete, can_approve)
      values (
        mid, m,
        case when m = 'wardrobe' then r <> 'guest' else
          r in ('owner', 'adult') or (r = 'guest' and m in ('dashboard', 'shopping')) end,
        case when m = 'wardrobe' then r <> 'guest' else r in ('owner', 'adult') end,
        case when m = 'wardrobe' then r <> 'guest' else r in ('owner', 'adult') end,
        case when m = 'wardrobe' then r <> 'guest' else
          r in ('owner', 'adult') and m <> 'budget' or r = 'owner' end,
        r = 'owner'
      )
      on conflict (member_id, module) do nothing;
    end if;
  end loop;
end;
$$;
revoke execute on function public.apply_default_permissions(uuid, public.member_role) from public, anon, authenticated;

-- Permiso de agenda para los miembros que ya existen.
insert into public.member_permissions (member_id, module, can_view, can_create, can_edit, can_delete, can_approve)
select m.id, 'agenda', m.role <> 'guest', m.role <> 'guest', m.role in ('owner', 'adult'),
       m.role in ('owner', 'adult'), m.role = 'owner'
from public.members m
on conflict (member_id, module) do nothing;

-- 3. Eventos
create table public.events (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  starts_at timestamptz not null,
  all_day boolean not null default false,
  member_id uuid references public.members (id) on delete set null,
  note text check (char_length(note) <= 300),
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index events_household_idx on public.events (household_id, starts_at);

create or replace function public.events_check()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.member_id is not null and not exists (
    select 1 from members where id = new.member_id and household_id = new.household_id) then
    raise exception 'member_not_in_household';
  end if;
  if tg_op = 'UPDATE' and (new.household_id <> old.household_id or new.created_by is distinct from old.created_by) then
    raise exception 'owner_cannot_change';
  end if;
  return new;
end;
$$;
create trigger events_check before insert or update on public.events
  for each row execute function public.events_check();

alter table public.events enable row level security;

create policy events_select on public.events for select
  using (public.has_permission(household_id, 'agenda', 'view'));
create policy events_insert on public.events for insert
  with check (public.has_permission(household_id, 'agenda', 'create') and created_by = auth.uid());
create policy events_update on public.events for update
  using (public.has_permission(household_id, 'agenda', 'edit')
         or (created_by = auth.uid() and public.has_permission(household_id, 'agenda', 'create')))
  with check (public.has_permission(household_id, 'agenda', 'edit')
         or (created_by = auth.uid() and public.has_permission(household_id, 'agenda', 'create')));
create policy events_delete on public.events for delete
  using (public.has_permission(household_id, 'agenda', 'delete')
         or (created_by = auth.uid() and public.has_permission(household_id, 'agenda', 'create')));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.events;
  end if;
end $$;
