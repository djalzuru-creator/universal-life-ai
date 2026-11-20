import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/household_repository.dart';
import '../data/models.dart';
import '../data/providers.dart';
import 'common.dart';
import 'dashboard_page.dart' show moduleIcons;

/// Editor de perfil y matriz de permisos de un miembro (solo administrador).
class MemberPermissionsPage extends ConsumerWidget {
  const MemberPermissionsPage({
    super.key,
    required this.householdId,
    required this.memberId,
  });

  final String householdId;
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider(householdId));
    final perms = ref.watch(permissionsProvider(memberId));
    final repo = ref.read(householdRepositoryProvider);

    Future<void> act(Future<void> Function() f) async {
      try {
        await f();
        ref.invalidate(membersProvider(householdId));
        ref.invalidate(permissionsProvider(memberId));
        ref.invalidate(auditLogProvider(householdId));
      } catch (e) {
        if (context.mounted) showSnack(context, friendlyError(e));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil y permisos')),
      body: members.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e),
        data: (list) {
          final member = list.where((m) => m.id == memberId).firstOrNull;
          if (member == null) {
            return const Center(child: Text('Este miembro ya no existe.'));
          }
          return PageBody(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        member.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<MemberRole>(
                        initialValue: member.role,
                        decoration: const InputDecoration(labelText: 'Perfil'),
                        items: [
                          for (final r in MemberRole.values.where(
                            (r) => r != MemberRole.owner,
                          ))
                            DropdownMenuItem(value: r, child: Text(r.label)),
                        ],
                        onChanged: (r) {
                          if (r != null && r != member.role) {
                            act(() => repo.updateMember(member.id, role: r));
                          }
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Perfil activo'),
                        subtitle: const Text(
                          'Si lo desactivas, no podrá entrar al hogar.',
                        ),
                        value: member.isActive,
                        onChanged: (v) => act(
                          () => repo.updateMember(
                            member.id,
                            status: v
                                ? MemberStatus.active
                                : MemberStatus.suspended,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Qué puede hacer en cada módulo',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              perms.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(e),
                data: (plist) {
                  final byModule = {for (final p in plist) p.module: p};
                  return Column(
                    children: [
                      for (final m in AppModule.values)
                        if (byModule[m] case final p?)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(moduleIcons[m]),
                                      const SizedBox(width: 8),
                                      Text(
                                        m.label,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      for (final a in PermissionAction.values)
                                        FilterChip(
                                          label: Text(a.label),
                                          selected: p.can(a),
                                          onSelected: (v) => act(
                                            () => repo.setPermission(
                                              member.id,
                                              m,
                                              a,
                                              v,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.person_remove_outlined),
                label: const Text('Eliminar del hogar'),
                onPressed: () async {
                  final sure = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('¿Eliminar a ${member.displayName}?'),
                      content: const Text(
                        'Perderá el acceso al hogar. Podrás invitarle de nuevo.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Eliminar'),
                        ),
                      ],
                    ),
                  );
                  if (sure != true) return;
                  try {
                    await repo.removeMember(member.id);
                    ref.invalidate(membersProvider(householdId));
                    if (context.mounted) context.go('/h/$householdId/admin');
                  } catch (e) {
                    if (context.mounted) showSnack(context, friendlyError(e));
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
