import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../household/data/providers.dart';
import '../../pantry/data/pantry_models.dart';

class ShoppingItem {
  const ShoppingItem({
    this.id,
    required this.householdId,
    required this.name,
    this.quantity = 1,
    this.unit = 'ud',
    this.note,
    this.barcode,
    this.brand,
    this.isChecked = false,
    this.price,
  });

  final String? id;
  final String householdId;
  final String name;
  final double quantity;
  final String unit;
  final String? note;
  final String? barcode;
  final String? brand;
  final bool isChecked;
  final double? price;

  String get quantityLabel {
    final q = quantity == quantity.roundToDouble()
        ? quantity.toStringAsFixed(0)
        : '$quantity';
    return unit == 'ud' && quantity == 1 ? '' : '$q $unit';
  }

  factory ShoppingItem.fromJson(Map<String, dynamic> j) => ShoppingItem(
    id: j['id'] as String,
    householdId: j['household_id'] as String,
    name: j['name'] as String,
    quantity: (j['quantity'] as num).toDouble(),
    unit: j['unit'] as String,
    note: j['note'] as String?,
    barcode: j['barcode'] as String?,
    brand: j['brand'] as String?,
    isChecked: j['is_checked'] as bool,
    price: (j['price'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'household_id': householdId,
    'name': name,
    'quantity': quantity,
    'unit': unit,
    'note': note,
    'barcode': barcode,
    'brand': brand,
    'is_checked': isChecked,
    'price': price,
  };

  /// Un producto de la despensa que se ha acabado, como artículo de la lista.
  factory ShoppingItem.fromPantry(PantryItem p) => ShoppingItem(
    householdId: p.householdId,
    name: p.name,
    brand: p.brand,
    barcode: p.barcode,
    unit: p.unit,
    quantity: p.unit == 'ud' ? 1 : (p.quantity > 0 ? p.quantity : 1),
  );

  /// Lo comprado, listo para guardarlo en la despensa.
  PantryItem toPantry(PantryLocation location) => PantryItem(
    householdId: householdId,
    name: name,
    brand: brand,
    barcode: barcode,
    quantity: quantity,
    unit: unit,
    location: location,
    price: price,
  );
}

class ShoppingRepository {
  ShoppingRepository(this._db);
  final SupabaseClient _db;

  Stream<List<ShoppingItem>> watch(String householdId) => _db
      .from('shopping_items')
      .stream(primaryKey: ['id'])
      .eq('household_id', householdId)
      .order('created_at')
      .map((rows) => rows.map(ShoppingItem.fromJson).toList());

  /// Añade a la lista. Si no trae precio, pone el último que se pagó.
  Future<double?> add(ShoppingItem item) async {
    final price =
        item.price ??
        await lastPrice(item.householdId, item.name, barcode: item.barcode);
    await _db.from('shopping_items').insert(item.toJson()..['price'] = price);
    return price;
  }

  /// Último precio pagado por un producto (por código de barras o por nombre),
  /// buscando en la despensa y en la lista. Null si nunca se apuntó.
  Future<double?> lastPrice(
    String householdId,
    String name, {
    String? barcode,
  }) async {
    final safe = name.trim().replaceAll(RegExp(r'[%_\\,()"]'), '');
    if (safe.isEmpty && barcode == null) return null;
    final match = [
      if (barcode != null) 'barcode.eq.$barcode',
      if (safe.isNotEmpty) 'name.ilike."$safe"',
    ].join(',');
    Future<({double price, DateTime at})?> find(String table, String at) async {
      try {
        final rows = await _db
            .from(table)
            .select('price, $at')
            .eq('household_id', householdId)
            .not('price', 'is', null)
            .or(match)
            .order(at, ascending: false)
            .limit(1);
        if (rows.isEmpty) return null;
        final r = rows.first;
        return (
          price: (r['price'] as num).toDouble(),
          at: DateTime.parse(r[at] as String),
        );
      } catch (_) {
        return null; // sin permiso o sin red: no pasa nada
      }
    }

    final hits = [
      ?await find('pantry_items', 'created_at'),
      ?await find('shopping_items', 'created_at'),
    ]..sort((a, b) => b.at.compareTo(a.at));
    return hits.isEmpty ? null : hits.first.price;
  }

  Future<void> setChecked(String id, bool checked) =>
      _db.from('shopping_items').update({'is_checked': checked}).eq('id', id);

  Future<void> update(ShoppingItem item) => _db
      .from('shopping_items')
      .update(item.toJson()..remove('household_id'))
      .eq('id', item.id!);

  Future<void> delete(String id) =>
      _db.from('shopping_items').delete().eq('id', id);

  /// Guarda lo comprado en la despensa y lo quita de la lista.
  Future<int> moveCheckedToPantry(
    List<ShoppingItem> checked,
    PantryLocation location,
  ) async {
    if (checked.isEmpty) return 0;
    await _db.from('pantry_items').insert([
      for (final i in checked) i.toPantry(location).toJson(),
    ]);
    await _db.from('shopping_items').delete().inFilter('id', [
      for (final i in checked) i.id!,
    ]);
    return checked.length;
  }

  Future<void> clearChecked(List<ShoppingItem> checked) => _db
      .from('shopping_items')
      .delete()
      .inFilter('id', [for (final i in checked) i.id!]);
}

final shoppingRepositoryProvider = Provider(
  (ref) => ShoppingRepository(ref.watch(supabaseProvider)),
);

final shoppingItemsProvider = StreamProvider.family<List<ShoppingItem>, String>(
  (ref, householdId) =>
      ref.watch(shoppingRepositoryProvider).watch(householdId),
);
