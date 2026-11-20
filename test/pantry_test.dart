import 'package:flutter_test/flutter_test.dart';
import 'package:universal_life_ai/features/pantry/data/open_food_facts.dart';
import 'package:universal_life_ai/features/pantry/data/pantry_models.dart';

void main() {
  final today = DateTime(2026, 11, 20, 18);

  PantryItem item({DateTime? expires, double qty = 1}) => PantryItem(
    householdId: 'h',
    name: 'Leche',
    expiresOn: expires,
    quantity: qty,
  );

  test('Estado de caducidad', () {
    expect(item().expiry(today), ExpiryStatus.none);
    expect(
      item(expires: DateTime(2026, 11, 19)).expiry(today),
      ExpiryStatus.expired,
    );
    expect(
      item(expires: DateTime(2026, 11, 20)).expiry(today),
      ExpiryStatus.soon,
    );
    expect(
      item(expires: DateTime(2026, 11, 23)).expiry(today),
      ExpiryStatus.soon,
    );
    expect(
      item(expires: DateTime(2026, 11, 24)).expiry(today),
      ExpiryStatus.ok,
    );
  });

  test('Cantidad legible', () {
    expect(item(qty: 2).quantityLabel, '2 ud');
    expect(item(qty: 1.5).quantityLabel, '1.5 ud');
  });

  test('JSON de ida y vuelta', () {
    final json = PantryItem(
      householdId: 'h',
      name: 'Yogur',
      quantity: 4,
      location: PantryLocation.fridge,
      expiresOn: DateTime(2026, 12, 1),
    ).toJson();
    expect(json['expires_on'], '2026-12-01');
    expect(json['location'], 'fridge');
    final back = PantryItem.fromJson({...json, 'id': 'x'});
    expect(back.location, PantryLocation.fridge);
    expect(back.expiresOn, DateTime(2026, 12, 1));
  });

  test('Open Food Facts: producto encontrado', () {
    final info = OpenFoodFacts.parse({
      'status': 1,
      'product': {
        'product_name': 'Whole milk',
        'product_name_es': 'Leche entera',
        'brands': 'Marca A, Marca B',
        'product_quantity': '1000',
        'product_quantity_unit': 'ml',
        'image_front_small_url': 'https://images.openfoodfacts.org/x.jpg',
      },
    });
    expect(info!.name, 'Leche entera');
    expect(info.brand, 'Marca A');
    expect(info.quantity, 1000);
    expect(info.unit, 'ml');
  });

  test('Open Food Facts: no encontrado', () {
    expect(OpenFoodFacts.parse({'status': 0}), isNull);
    expect(OpenFoodFacts.isValidBarcode('84100'), isFalse);
    expect(OpenFoodFacts.isValidBarcode('8410000000001'), isTrue);
  });
}
