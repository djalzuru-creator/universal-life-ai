import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/providers.dart';
import 'common.dart';

/// Selector de hogar: si perteneces a uno, entra directo; si a varios, eliges.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberships = ref.watch(myMembershipsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis hogares'),
        actions: [
          IconButton(
            tooltip: 'Salir',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(supabaseProvider).auth.signOut(),
          ),
        ],
      ),
      body: memberships.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            ErrorView(e, onRetry: () => ref.invalidate(myMembershipsProvider)),
        data: (list) {
          if (list.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) context.go('/start');
            });
            return const LoadingView();
          }
          if (list.length == 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) context.go('/h/${list.single.householdId}');
            });
            return const LoadingView();
          }
          return PageBody(
            children: [
              for (final m in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.home_outlined),
                      title: _HouseholdName(m.householdId),
                      subtitle: Text('${m.displayName} · ${m.role.label}'),
                      onTap: () => context.go('/h/${m.householdId}'),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.go('/start'),
                icon: const Icon(Icons.add),
                label: const Text('Crear o unirme a otro hogar'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HouseholdName extends ConsumerWidget {
  const _HouseholdName(this.id);
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(
    ref.watch(householdProvider(id)).whenOrNull(data: (h) => h.name) ?? '…',
  );
}
