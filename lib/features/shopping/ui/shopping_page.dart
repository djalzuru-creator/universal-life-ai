import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../household/data/household_repository.dart';
import '../../household/data/models.dart';
import '../../household/data/providers.dart';
import '../../household/ui/common.dart';
import '../../pantry/data/pantry_models.dart';
import '../../pantry/data/pantry_repository.dart';
import '../../pantry/ui/scanner_page.dart';
import '../data/shopping_repository.dart';

typedef _ModuleKey = ({String householdId, AppModule module});

/// Acciones permitidas al usuario actual en un módulo.
final moduleAccessProvider =
    FutureProvider.family<Set<PermissionAction>, _ModuleKey>((ref, k) async {
      final me = await ref.watch(myMemberProvider(k.householdId).future);
      if (me == null) return {};
      if (me.isOwner) return PermissionAction.values.toSet();
      final perms = await ref.watch(permissionsProvider(me.id).future);
      return perms
          .where((p) => p.module == k.module)
          .expand((p) => p.allowed)
          .toSet();
    });

class ShoppingPage extends ConsumerStatefulWidget {
  const ShoppingPage({super.key, required this.householdId});
  final String householdId;

  @override
  ConsumerState<ShoppingPage> createState() => _ShoppingPageState();
}

class _ShoppingPageState extends ConsumerState<ShoppingPage> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  Future<void> _quickAdd() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await _add(ShoppingItem(householdId: widget.householdId, name: text));
  }

  Future<void> _add(ShoppingItem item) => _run(() async {
    final price = await ref.read(shoppingRepositoryProvider).add(item);
    if (price != null && mounted) {
      showSnack(
        context,
        '${item.name}: ${price.toStringAsFixed(2).replaceAll('.', ',')} € (último precio que pagasteis)',
      );
    }
  });

  Future<void> _scan() async {
    final code = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScannerPage()));
    if (code == null || !mounted) return;
    showSnack(context, 'Buscando el producto…');
    final info = await ref.read(openFoodFactsProvider).lookup(code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (info == null) {
      showSnack(context, 'No lo encuentro. Escríbelo a mano.');
      return;
    }
    await _add(
      ShoppingItem(
        householdId: widget.householdId,
        name: info.name.isEmpty ? code : info.name,
        brand: info.brand,
        barcode: code,
      ),
    );
  }

  Future<void> _toPantry(List<ShoppingItem> checked) async {
    final location = await showDialog<PantryLocation>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('¿Dónde lo guardas?'),
        children: [
          for (final l in PantryLocation.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, l),
              child: Text(l.label),
            ),
        ],
      ),
    );
    if (location == null) return;
    await _run(() async {
      final n = await ref
          .read(shoppingRepositoryProvider)
          .moveCheckedToPantry(checked, location);
      if (mounted) {
        showSnack(
          context,
          n == 1
              ? '1 producto guardado en la despensa.'
              : '$n productos guardados en la despensa.',
        );
      }
    });
  }

  Future<void> _edit(ShoppingItem item) async {
    final qty = TextEditingController(
      text: item.quantity == item.quantity.roundToDouble()
          ? item.quantity.toStringAsFixed(0)
          : '${item.quantity}',
    );
    final price = TextEditingController(text: item.price?.toString() ?? '');
    final note = TextEditingController(text: item.note ?? '');
    var unit = item.unit;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(item.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qty,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Cantidad'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: unit,
                    items: [
                      for (final u in pantryUnits)
                        DropdownMenuItem(value: u, child: Text(u)),
                    ],
                    onChanged: (u) => setState(() => unit = u ?? unit),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'Nota (marca, tamaño…)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Precio pagado',
                  suffixText: '€',
                ),
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
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    double? parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
    if (ok == true) {
      final q = parse(qty.text);
      await _run(
        () => ref
            .read(shoppingRepositoryProvider)
            .update(
              ShoppingItem(
                id: item.id,
                householdId: item.householdId,
                name: item.name,
                quantity: q != null && q > 0 ? q : item.quantity,
                unit: unit,
                note: note.text.trim().isEmpty ? null : note.text.trim(),
                barcode: item.barcode,
                brand: item.brand,
                isChecked: item.isChecked,
                price: parse(price.text),
              ),
            ),
      );
    }
    qty.dispose();
    price.dispose();
    note.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hid = widget.householdId;
    final items = ref.watch(shoppingItemsProvider(hid));
    final access =
        ref
            .watch(
              moduleAccessProvider((
                householdId: hid,
                module: AppModule.shopping,
              )),
            )
            .value ??
        const {};
    final pantryAccess =
        ref
            .watch(
              moduleAccessProvider((
                householdId: hid,
                module: AppModule.pantry,
              )),
            )
            .value ??
        const {};
    final canAdd = access.contains(PermissionAction.create);
    final canCheck = access.contains(PermissionAction.edit);
    final canDelete = access.contains(PermissionAction.delete);
    final pantry = pantryAccess.contains(PermissionAction.view)
        ? ref.watch(pantryItemsProvider(hid)).value
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Lista de la compra')),
      body: items.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          e,
          onRetry: () => ref.invalidate(shoppingItemsProvider(hid)),
        ),
        data: (all) {
          final pending = all.where((i) => !i.isChecked).toList();
          final checked = all.where((i) => i.isChecked).toList();
          final onList = {for (final i in all) i.name.toLowerCase()};
          final runOut = [
            for (final p in pantry ?? const <PantryItem>[])
              if (p.quantity <= 0 && !onList.contains(p.name.toLowerCase())) p,
          ];
          final theme = Theme.of(context);

          return PageBody(
            children: [
              if (canAdd)
                TextField(
                  controller: _input,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'Añadir a la lista (leche, pan…)',
                    prefixIcon: const Icon(Icons.add_shopping_cart),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Escanear código de barras',
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: _scan,
                        ),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: _quickAdd,
                        ),
                      ],
                    ),
                  ),
                  onSubmitted: (_) => _quickAdd(),
                ),
              if (canAdd && runOut.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Se han acabado en la despensa',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final p in runOut)
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: Text(p.name),
                        onPressed: () => _add(ShoppingItem.fromPantry(p)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (all.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'La lista está vacía.',
                    textAlign: TextAlign.center,
                  ),
                ),
              if (pending.any((i) => i.price != null))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(() {
                    final known = pending.where((i) => i.price != null);
                    final total = known.fold<double>(0, (a, i) => a + i.price!);
                    final t = total.toStringAsFixed(2).replaceAll('.', ',');
                    return known.length == pending.length
                        ? 'Total estimado: $t €'
                        : 'Total estimado: $t € (${known.length} de ${pending.length} con precio)';
                  }(), style: theme.textTheme.titleSmall),
                ),
              if (pending.isNotEmpty)
                Card(
                  child: Column(
                    children: [
                      for (final i in pending)
                        _ItemTile(
                          item: i,
                          onChecked: canCheck
                              ? (v) => _run(
                                  () => ref
                                      .read(shoppingRepositoryProvider)
                                      .setChecked(i.id!, v),
                                )
                              : null,
                          onTap: canCheck ? () => _edit(i) : null,
                          onDelete: canDelete
                              ? () => _run(
                                  () => ref
                                      .read(shoppingRepositoryProvider)
                                      .delete(i.id!),
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
              if (checked.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'En el carrito (${checked.length})',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (canDelete)
                      TextButton(
                        onPressed: () => _run(
                          () => ref
                              .read(shoppingRepositoryProvider)
                              .clearChecked(checked),
                        ),
                        child: const Text('Vaciar'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (final i in checked)
                        _ItemTile(
                          item: i,
                          onChecked: canCheck
                              ? (v) => _run(
                                  () => ref
                                      .read(shoppingRepositoryProvider)
                                      .setChecked(i.id!, v),
                                )
                              : null,
                          onTap: canCheck ? () => _edit(i) : null,
                        ),
                    ],
                  ),
                ),
                if (canDelete &&
                    pantryAccess.contains(PermissionAction.create)) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _toPantry(checked),
                    icon: const Icon(Icons.kitchen_outlined),
                    label: const Text('Guardar lo comprado en la despensa'),
                  ),
                ],
              ],
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    this.onChecked,
    this.onTap,
    this.onDelete,
  });
  final ShoppingItem item;
  final ValueChanged<bool>? onChecked;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (item.quantityLabel.isNotEmpty) item.quantityLabel,
      if (item.note != null) item.note!,
      if (item.price != null) '${item.price!.toStringAsFixed(2)} €',
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: Checkbox(
        value: item.isChecked,
        onChanged: onChecked == null ? null : (v) => onChecked!(v ?? false),
      ),
      title: Text(
        item.name,
        style: item.isChecked
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: Theme.of(context).colorScheme.outline,
              )
            : null,
      ),
      subtitle: details.isEmpty ? null : Text(details),
      trailing: onDelete == null
          ? null
          : IconButton(
              tooltip: 'Quitar',
              icon: const Icon(Icons.close),
              onPressed: onDelete,
            ),
    );
  }
}
