import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../household/data/providers.dart';
import 'open_food_facts.dart';
import 'pantry_models.dart';

class PantryRepository {
  PantryRepository(this._db);

  final SupabaseClient _db;

  /// Lista en tiempo real: cualquier cambio de un familiar llega al momento.
  Stream<List<PantryItem>> watch(String householdId) => _db
      .from('pantry_items')
      .stream(primaryKey: ['id'])
      .eq('household_id', householdId)
      .map((rows) => rows.map(PantryItem.fromJson).toList());

  Future<void> add(PantryItem item) =>
      _db.from('pantry_items').insert(item.toJson());

  Future<void> update(PantryItem item) => _db
      .from('pantry_items')
      .update(item.toJson()..remove('household_id'))
      .eq('id', item.id!);

  Future<void> setQuantity(String id, double quantity) =>
      _db.from('pantry_items').update({'quantity': quantity}).eq('id', id);

  Future<void> delete(String id) =>
      _db.from('pantry_items').delete().eq('id', id);
}

final pantryRepositoryProvider = Provider(
  (ref) => PantryRepository(ref.watch(supabaseProvider)),
);

final openFoodFactsProvider = Provider((ref) => OpenFoodFacts());

final pantryItemsProvider = StreamProvider.family<List<PantryItem>, String>(
  (ref, householdId) => ref.watch(pantryRepositoryProvider).watch(householdId),
);
