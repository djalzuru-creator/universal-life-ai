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

  Future<void> add(ShoppingItem item) =>
      _db.from('shopping_items').insert(item.toJson());

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
