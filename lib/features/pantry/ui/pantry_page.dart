import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../household/data/household_repository.dart';
import '../../household/data/models.dart';
import '../../household/data/providers.dart';
import '../../household/ui/common.dart';
import '../data/pantry_models.dart';
import '../../shopping/data/shopping_repository.dart';
import '../data/pantry_repository.dart';
import 'pantry_item_form.dart';
import '../data/scan_lookup.dart';
import 'scanner_page.dart';

/// Permisos del usuario actual sobre la despensa de un hogar.
final pantryAccessProvider =
    FutureProvider.family<Set<PermissionAction>, String>((
      ref,
      householdId,
    ) async {
      final me = await ref.watch(myMemberProvider(householdId).future);
      if (me == null) return {};
      if (me.isOwner) return PermissionAction.values.toSet();
      final perms = await ref.watch(permissionsProvider(me.id).future);
      return perms
          .where((p) => p.module == AppModule.pantry)
          .expand((p) => p.allowed)
          .toSet();
    });

class PantryPage extends ConsumerStatefulWidget {
  const PantryPage({super.key, required this.householdId});

  final String householdId;

  @override
  ConsumerState<PantryPage> createState() => _PantryPageState();
}

class _PantryPageState extends ConsumerState<PantryPage> {
  PantryLocation? _filter;
  String _query = '';

  Future<void> _addManual([PantryItem? prefilled]) async {
    final saved = await showPantryItemForm(
      context,
      initial:
          prefilled ?? PantryItem(householdId: widget.householdId, name: ''),
    );
    if (saved == true && mounted) showSnack(context, 'Producto guardado.');
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScannerPage()));
    if (code == null || !mounted) return;
    showSnack(context, 'Buscando el producto…');
    final scanned = await ref.read(scanLookupProvider)(code);
    final info = scanned.info;
    if (!mounted) return;
    // Escanear otra vez algo que ya está en la despensa suma uno más.
    final existing =
        (ref.read(pantryItemsProvider(widget.householdId)).value ??
                const <PantryItem>[])
            .where((p) => p.barcode == code)
            .firstOrNull;
    final step = existing == null
        ? null
        : existing.unit == 'ud'
        ? 1.0
        : (info?.unit == existing.unit ? info?.quantity : null);
    if (existing != null && step != null) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final total = existing.quantity + step;
      try {
        await ref
            .read(pantryRepositoryProvider)
            .setQuantity(existing.id!, total);
        if (mounted) {
          showSnack(
            context,
            '${existing.name}: ahora tienes ${existing.copyWith(quantity: total).quantityLabel}.',
          );
        }
      } catch (e) {
        if (mounted) showSnack(context, friendlyError(e));
      }
      return;
    }
    final price = await ref
        .read(shoppingRepositoryProvider)
        .lastPrice(widget.householdId, scanned.name, barcode: code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (info == null) {
      showSnack(
        context,
        'No lo encuentro en Open Food Facts. Escribe el nombre a mano.',
      );
    }
    await _addManual(
      PantryItem(
        householdId: widget.householdId,
        name: scanned.name,
        brand: info?.brand,
        summary: scanned.summary,
        barcode: code,
        quantity: info?.quantity ?? 1,
        unit: info?.unit ?? 'ud',
        imageUrl: info?.imageUrl,
        price: price,
      ),
    );
  }

  void _chooseAdd() => showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text('Escanear código de barras'),
            onTap: () {
              Navigator.pop(ctx);
              _scan();
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Escribir a mano'),
            onTap: () {
              Navigator.pop(ctx);
              _addManual();
            },
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(pantryItemsProvider(widget.householdId));
    final access =
        ref.watch(pantryAccessProvider(widget.householdId)).value ?? const {};
    final canCreate = access.contains(PermissionAction.create);
    final canEdit = access.contains(PermissionAction.edit);
    final canDelete = access.contains(PermissionAction.delete);
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Despensa')),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _chooseAdd,
              icon: const Icon(Icons.add),
              label: const Text('Añadir'),
            )
          : null,
      body: items.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          e,
          onRetry: () =>
              ref.invalidate(pantryItemsProvider(widget.householdId)),
        ),
        data: (all) {
          final q = _query.trim().toLowerCase();
          final list =
              all
                  .where((i) => _filter == null || i.location == _filter)
                  .where(
                    (i) =>
                        q.isEmpty ||
                        i.name.toLowerCase().contains(q) ||
                        (i.brand ?? '').toLowerCase().contains(q),
                  )
                  .toList()
                ..sort((a, b) {
                  final da = a.daysLeft(today) ?? 1 << 30;
                  final db = b.daysLeft(today) ?? 1 << 30;
                  return da != db
                      ? da.compareTo(db)
                      : a.name.toLowerCase().compareTo(b.name.toLowerCase());
                });
          final urgent = all.where((i) {
            final s = i.expiry(today);
            return s == ExpiryStatus.soon || s == ExpiryStatus.expired;
          }).length;

          return PageBody(
            children: [
              if (urgent > 0)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: Text(
                      urgent == 1
                          ? '1 producto caduca pronto o ya caducó'
                          : '$urgent productos caducan pronto o ya caducaron',
                    ),
                    subtitle: const Text('Aparecen primero en la lista.'),
                  ),
                ),
              if (urgent > 0) const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar en la despensa',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: Text('Todo (${all.length})'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  for (final l in PantryLocation.values)
                    ChoiceChip(
                      label: Text(
                        '${l.label} (${all.where((i) => i.location == l).length})',
                      ),
                      selected: _filter == l,
                      onSelected: (_) => setState(() => _filter = l),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (all.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'La despensa está vacía. Pulsa "Añadir" para meter el primer producto.',
                    textAlign: TextAlign.center,
                  ),
                )
              else if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No hay productos que coincidan.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final item in list)
                        _PantryTile(
                          item: item,
                          today: today,
                          canEdit: canEdit,
                          onTap: canEdit
                              ? () => showPantryItemForm(
                                  context,
                                  initial: item,
                                  canDelete: canDelete,
                                )
                              : null,
                          onUseOne: canEdit && item.quantity >= 1
                              ? () async {
                                  try {
                                    await ref
                                        .read(pantryRepositoryProvider)
                                        .setQuantity(
                                          item.id!,
                                          item.quantity - 1,
                                        );
                                    if (item.quantity - 1 <= 0 &&
                                        context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Se ha acabado: ${item.name}',
                                          ),
                                          action: SnackBarAction(
                                            label: 'Añadir a la compra',
                                            onPressed: () => ref
                                                .read(
                                                  shoppingRepositoryProvider,
                                                )
                                                .add(
                                                  ShoppingItem.fromPantry(item),
                                                ),
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      showSnack(context, '$e');
                                    }
                                  }
                                }
                              : null,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }
}

class _PantryTile extends StatelessWidget {
  const _PantryTile({
    required this.item,
    required this.today,
    required this.canEdit,
    this.onTap,
    this.onUseOne,
  });

  final PantryItem item;
  final DateTime today;
  final bool canEdit;
  final VoidCallback? onTap;
  final VoidCallback? onUseOne;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = item.daysLeft(today);
    final status = item.expiry(today);
    final (String? label, Color? color) = switch (status) {
      ExpiryStatus.expired => ('Caducado', scheme.error),
      ExpiryStatus.soon => (
        days == 0
            ? 'Caduca hoy'
            : days == 1
            ? 'Caduca mañana'
            : 'Caduca en $days días',
        Colors.orange.shade800,
      ),
      ExpiryStatus.ok => (
        '${item.expiresOn!.day}/${item.expiresOn!.month}',
        null,
      ),
      ExpiryStatus.none => (null, null),
    };
    final details = [
      if (item.brand != null) item.brand!,
      item.quantityLabel,
      item.location.label,
    ].join(' · ');

    return ListTile(
      onTap: onTap,
      leading: item.imageUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                item.imageUrl!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.inventory_2_outlined),
              ),
            )
          : const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
      title: Text(
        item.name,
        style: item.quantity == 0
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(
        label == null ? details : '$details\n$label',
        style: color == null ? null : TextStyle(color: color),
      ),
      isThreeLine: label != null,
      trailing: onUseOne == null
          ? null
          : IconButton(
              tooltip: 'Gastar uno',
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: onUseOne,
            ),
    );
  }
}
