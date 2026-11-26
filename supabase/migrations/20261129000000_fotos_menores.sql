-- Universal Life AI — Los menores también usan el álbum de fotos.
-- Adolescentes y niños: ven el álbum familiar y suben fotos. Solo pueden
-- cambiar o borrar las fotos que suben ellos (no las de los padres).

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
      v := m in ('dashboard', 'wardrobe', 'agenda', 'photos');
      c := m in ('wardrobe', 'agenda', 'photos');
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

-- Abre el álbum a los adolescentes y niños que ya existen.
insert into public.member_permissions (member_id, module, can_view, can_create, can_edit, can_delete, can_approve)
select m.id, 'photos', true, true, false, false, false
from public.members m where m.role in ('teen', 'child')
on conflict (member_id, module) do update
  set can_view = true, can_create = true, can_edit = false, can_delete = false, can_approve = false;
