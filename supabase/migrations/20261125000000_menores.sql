-- Universal Life AI — Adolescentes y niños solo ven su Armario (y el panel).
-- Adultos y propietario lo ven todo. El administrador puede abrir más módulos a mano.

create or replace function public.apply_default_permissions(mid uuid, r public.member_role)
returns void language plpgsql security definer set search_path = public as $$
declare
  m public.app_module;
  minor boolean := r in ('teen', 'child');
  v boolean; w boolean;
begin
  foreach m in array enum_range(null::public.app_module) loop
    if minor then
      v := m in ('dashboard', 'wardrobe');
      w := m = 'wardrobe';
      insert into member_permissions (member_id, module, can_view, can_create, can_edit, can_delete, can_approve)
      values (mid, m, v, w, w, w, false)
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

-- Aplica la regla a los adolescentes y niños que ya existen.
update public.member_permissions p
set can_view = p.module in ('dashboard', 'wardrobe'),
    can_create = p.module = 'wardrobe',
    can_edit = p.module = 'wardrobe',
    can_delete = p.module = 'wardrobe',
    can_approve = false
from public.members m
where m.id = p.member_id and m.role in ('teen', 'child');
