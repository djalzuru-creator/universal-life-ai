import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand_widgets.dart';
import '../../../core/theme.dart';
import '../../pantry/data/pantry_models.dart';
import '../../pantry/data/pantry_repository.dart';
import '../../shopping/data/shopping_repository.dart';

import '../data/models.dart';
import '../data/providers.dart';
import 'common.dart';

/// Módulos que ya tienen pantalla; el resto aparece como "Próximamente".
const availableModules = {
  AppModule.pantry,
  AppModule.shopping,
  AppModule.wardrobe,
  AppModule.budget,
  AppModule.recipes,
};

const moduleIcons = {
  AppModule.dashboard: Icons.dashboard_outlined,
  AppModule.pantry: Icons.kitchen_outlined,
  AppModule.shopping: Icons.shopping_cart_outlined,
  AppModule.budget: Icons.account_balance_wallet_outlined,
  AppModule.recipes: Icons.restaurant_menu_outlined,
  AppModule.wardrobe: Icons.checkroom,
};

const moduleBlurb = {
  AppModule.pantry: 'Stock y caducidades',
  AppModule.shopping: 'Lista compartida',
  AppModule.wardrobe: 'Looks según el tiempo',
  AppModule.budget: 'Gastos del mes',
  AppModule.recipes: 'Qué cocinar hoy',
};

const _days = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];
const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

String spanishDate(DateTime d) =>
    '${_days[d.weekday - 1]}, ${d.day} de ${_months[d.month - 1]} de ${d.year}';

String greeting(DateTime d) => d.hour < 13
    ? 'Buenos días'
    : d.hour < 20
    ? 'Buenas tardes'
    : 'Buenas noches';

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
        toolbarHeight: 68,
        title: BrandTitle(
          subtitle: household.whenOrNull(data: (h) => h.name) ?? 'Mi hogar',
        ),
        actions: [
          if (me.value?.isOwner ?? false)
            IconButton(
              tooltip: 'Administrar',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => context.go('/h/$householdId/admin'),
            ),
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
          final visible = [
            for (final p in perms.value ?? const <ModulePermission>[])
              if (p.module != AppModule.dashboard &&
                  p.can(PermissionAction.view))
                p.module,
          ]..sort((a, b) => a.index.compareTo(b.index));
          String? live(AppModule m) => switch (m) {
            AppModule.pantry => _pantryLine(
              ref.watch(pantryItemsProvider(householdId)).value,
            ),
            AppModule.shopping => _shoppingLine(
              ref.watch(shoppingItemsProvider(householdId)).value,
            ),
            _ => null,
          };
          void open(AppModule m) => availableModules.contains(m)
              ? context.go('/h/$householdId/${m.name}')
              : showSnack(context, '${m.label}: llega en el siguiente paso.');

          return PageBody(
            children: [
              _Hero(name: member.displayName, role: member.role.label),
              const SizedBox(height: 16),
              if (perms.isLoading) const LoadingView(),
              if (perms.hasError) ErrorView(perms.error!),
              if (perms.hasValue && visible.isEmpty)
                const Text(
                  'Aún no tienes módulos activados. Pídeselo al administrador.',
                ),
              LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth > 560 ? 3 : 2;
                  final w = (c.maxWidth - 12 * (cols - 1)) / cols;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final (i, m) in visible.indexed)
                        SizedBox(
                          width: w,
                          height: 150,
                          child: _ModuleCard(
                            n: i + 1,
                            module: m,
                            line: live(m),
                            onTap: () => open(m),
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (visible.isNotEmpty) ...[
                const SizedBox(height: 16),
                _Assistant(visible: visible.toSet(), open: open),
              ],
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  static String? _pantryLine(List<PantryItem>? items) {
    if (items == null) return null;
    final now = DateTime.now();
    final urgent = items.where((i) {
      final s = i.expiry(now);
      return s == ExpiryStatus.soon || s == ExpiryStatus.expired;
    }).length;
    return urgent > 0 ? '$urgent caducan pronto' : '${items.length} productos';
  }

  static String? _shoppingLine(List<ShoppingItem>? items) {
    if (items == null) return null;
    final n = items.where((i) => !i.isChecked).length;
    return n == 0 ? 'Lista al día' : '$n por comprar';
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.name, required this.role});
  final String name;
  final String role;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime>(
      stream: Stream.periodic(
        const Duration(seconds: 30),
        (_) => DateTime.now(),
      ),
      initialData: DateTime.now(),
      builder: (context, snap) {
        final now = snap.data!;
        final hh = now.hour.toString().padLeft(2, '0');
        final mm = now.minute.toString().padLeft(2, '0');
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Brand.line),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF130928), Color(0xFF2A0F55), Color(0xFF0D0720)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -10,
                bottom: -30,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: Brand.glow(Brand.magenta, .45),
                    color: Brand.magenta.withValues(alpha: .12),
                  ),
                ),
              ),
              const Positioned(
                right: 12,
                bottom: 0,
                child: Mascot(height: 130),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 150, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${greeting(now)}, $name 👋',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Brand.fg,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Esto es lo que Aguilucho ha preparado hoy para la familia. · $role',
                      style: const TextStyle(color: Brand.muted, fontSize: 14),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Brand.bg.withValues(alpha: .6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Brand.line),
                      ),
                      child: Text(
                        '📅 ${spanishDate(now)}   🕒 $hh:$mm',
                        style: const TextStyle(
                          color: Brand.muted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.n,
    required this.module,
    required this.onTap,
    this.line,
  });
  final int n;
  final AppModule module;
  final String? line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ready = availableModules.contains(module);
    return NeonCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NeonNumber(n),
              const Spacer(),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Brand.violet2.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: Brand.line2),
                ),
                child: Icon(moduleIcons[module], color: Brand.violet),
              ),
            ],
          ),
          const Spacer(),
          Text(
            module.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Brand.fg,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            ready ? (line ?? moduleBlurb[module] ?? 'Abrir') : 'Próximamente',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Brand.muted),
          ),
        ],
      ),
    );
  }
}

/// Atajos de Aguilucho a cada módulo.
class _Assistant extends StatelessWidget {
  const _Assistant({required this.visible, required this.open});
  final Set<AppModule> visible;
  final void Function(AppModule) open;

  static const _asks = [
    (AppModule.recipes, '👩‍🍳 ¿Qué cocino hoy?'),
    (AppModule.shopping, '🛒 ¿Qué falta en la compra?'),
    (AppModule.pantry, '🥫 ¿Qué caduca pronto?'),
    (AppModule.budget, '💶 ¿Cómo van las cuentas?'),
    (AppModule.wardrobe, '👗 ¿Qué me pongo hoy?'),
  ];

  @override
  Widget build(BuildContext context) {
    return NeonCard(
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Brand.violet),
                  gradient: const RadialGradient(
                    colors: [Color(0xFF3B1475), Color(0xFF140A28)],
                  ),
                ),
                alignment: Alignment.center,
                child: const Mascot(height: 38),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aguilucho',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE9D5FF),
                    ),
                  ),
                  Text(
                    'Asistente de la familia',
                    style: TextStyle(fontSize: 12, color: Brand.dim),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Brand.violet2.withValues(alpha: .18),
              border: Border.all(color: Brand.line2),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
                topLeft: Radius.circular(4),
              ),
            ),
            child: const Text(
              '¡Hola! Te ayudo con la casa. ¿Por dónde empezamos?',
              style: TextStyle(color: Brand.fg),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (m, q) in _asks)
                if (visible.contains(m))
                  ActionChip(label: Text(q), onPressed: () => open(m)),
            ],
          ),
        ],
      ),
    );
  }
}
