import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models.dart';
import '../data/providers.dart';
import 'common.dart';

/// Módulos que ya tienen pantalla; el resto aparece como "Próximamente".
const availableModules = {
  AppModule.pantry,
  AppModule.shopping,
  AppModule.wardrobe,
};

const moduleIcons = {
  AppModule.dashboard: Icons.dashboard_outlined,
  AppModule.pantry: Icons.kitchen_outlined,
  AppModule.shopping: Icons.shopping_cart_outlined,
  AppModule.budget: Icons.account_balance_wallet_outlined,
  AppModule.recipes: Icons.restaurant_menu_outlined,
  AppModule.wardrobe: Icons.checkroom,
};

/// Panel principal del hogar. Muestra solo los módulos que el miembro puede ver.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key, required this.householdId});

  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider(householdId));
    final me = ref.watch(myMemberProvider(householdId));

    return Scaffold(
      appBar: AppBar(
        title: Text(household.whenOrNull(data: (h) => h.name) ?? 'Mi hogar'),
        actions: [
          IconButton(
            tooltip: 'Cambiar de hogar',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => context.go('/'),
          ),
          IconButton(
            tooltip: 'Salir',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(supabaseProvider).auth.signOut(),
          ),
        ],
      ),
      body: me.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e),
        data: (member) {
          if (member == null) {
            return const Center(
              child: Text(
                'No perteneces a este hogar o tu perfil está suspendido.',
              ),
            );
          }
          final perms = ref.watch(permissionsProvider(member.id));
          return PageBody(
            children: [
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      member.displayName.characters.first.toUpperCase(),
                    ),
                  ),
                  title: Text('Hola, ${member.displayName}'),
                  subtitle: Text(member.role.label),
                  trailing: member.isOwner
                      ? FilledButton.tonalIcon(
                          onPressed: () => context.go('/h/$householdId/admin'),
                          icon: const Icon(Icons.admin_panel_settings_outlined),
                          label: const Text('Administrar'),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              perms.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(e),
                data: (list) {
                  final visible =
                      list
                          .where(
                            (p) =>
                                p.module != AppModule.dashboard &&
                                p.can(PermissionAction.view),
                          )
                          .map((p) => p.module)
                          .toList()
                        ..sort((a, b) => a.index.compareTo(b.index));
                  if (visible.isEmpty) {
                    return const Text(
                      'Aún no tienes módulos activados. Pídeselo al administrador.',
                    );
                  }
                  return GridView.extent(
                    maxCrossAxisExtent: 220,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.3,
                    children: [
                      for (final m in visible)
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => availableModules.contains(m)
                                ? context.go('/h/$householdId/${m.name}')
                                : showSnack(
                                    context,
                                    '${m.label}: llega en el siguiente paso.',
                                  ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Icon(moduleIcons[m], size: 32),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m.label,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      Text(
                                        availableModules.contains(m)
                                            ? 'Abrir'
                                            : 'Próximamente',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
