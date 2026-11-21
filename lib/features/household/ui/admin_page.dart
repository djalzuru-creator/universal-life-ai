import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backup/backup.dart';

import 'package:go_router/go_router.dart';

import '../data/household_repository.dart';
import '../data/models.dart';
import '../data/providers.dart';
import 'common.dart';

/// Panel del administrador: miembros, invitaciones y registro de cambios.
class AdminPage extends ConsumerWidget {
  const AdminPage({super.key, required this.householdId});

  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider(householdId));
    final invitations = ref.watch(invitationsProvider(householdId));
    final audit = ref.watch(auditLogProvider(householdId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Administrar hogar')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _invite(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Invitar'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(membersProvider(householdId));
          ref.invalidate(invitationsProvider(householdId));
          ref.invalidate(auditLogProvider(householdId));
        },
        child: PageBody(
          children: [
            BackupCard(householdId: householdId),
            const SizedBox(height: 16),
            Text('Miembros', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            members.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(e),
              data: (list) => Card(
                child: Column(
                  children: [
                    for (final m in list)
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            m.displayName.characters.first.toUpperCase(),
                          ),
                        ),
                        title: Text(m.displayName),
                        subtitle: Text(
                          m.isActive
                              ? m.role.label
                              : '${m.role.label} · suspendido',
                        ),
                        trailing: m.isOwner
                            ? null
                            : const Icon(Icons.chevron_right),
                        onTap: m.isOwner
                            ? null
                            : () => context.go(
                                '/h/$householdId/admin/member/${m.id}',
                              ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Invitaciones pendientes', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            invitations.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(e),
              data: (list) {
                final pending = list.where((i) => i.isPending).toList();
                if (pending.isEmpty) {
                  return const Text('No hay invitaciones pendientes.');
                }
                return Card(
                  child: Column(
                    children: [
                      for (final i in pending)
                        ListTile(
                          title: Text('${i.displayName} · ${i.role.label}'),
                          subtitle: SelectableText('Código: ${i.code}'),
                          trailing: IconButton(
                            tooltip: 'Anular',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              try {
                                await ref
                                    .read(householdRepositoryProvider)
                                    .deleteInvitation(i.id);
                                ref.invalidate(
                                  invitationsProvider(householdId),
                                );
                              } catch (e) {
                                if (context.mounted) {
                                  showSnack(context, friendlyError(e));
                                }
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Text('Últimos cambios', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            audit.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(e),
              data: (rows) => rows.isEmpty
                  ? const Text('Sin cambios todavía.')
                  : Card(
                      child: Column(
                        children: [
                          for (final r in rows)
                            ListTile(
                              dense: true,
                              title: Text(_auditLabel(r['action'] as String)),
                              subtitle: Text(
                                _formatDate(
                                  DateTime.parse(r['created_at'] as String),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    var role = MemberRole.adult;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Invitar a un familiar'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MemberRole>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Perfil'),
                items: [
                  for (final r in MemberRole.values.where(
                    (r) => r != MemberRole.owner,
                  ))
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (r) => setState(() => role = r ?? role),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Crear código'),
            ),
          ],
        ),
      ),
    );
    final displayName = name.text.trim();
    name.dispose();
    if (ok != true || displayName.isEmpty || !context.mounted) return;

    try {
      final inv = await ref
          .read(householdRepositoryProvider)
          .createInvitation(
            householdId: householdId,
            displayName: displayName,
            role: role,
          );
      ref.invalidate(invitationsProvider(householdId));
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Código para $displayName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                inv.code,
                style: Theme.of(ctx).textTheme.headlineMedium
                    ?.copyWith(letterSpacing: 4),
              ),
              const SizedBox(height: 12),
              const Text(
                'Que cree su cuenta en la app y lo escriba en "Unirme con un código". '
                'Caduca en 7 días y solo sirve una vez.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: inv.code)),
              child: const Text('Copiar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hecho'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) showSnack(context, friendlyError(e));
    }
  }
}

String _auditLabel(String action) => switch (action) {
  'household.created' => 'Hogar creado',
  'member.joined' => 'Nuevo miembro',
  'member.updated' => 'Miembro modificado',
  'member.removed' => 'Miembro eliminado',
  'permission.updated' => 'Permisos cambiados',
  _ => action,
};

String _formatDate(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}
