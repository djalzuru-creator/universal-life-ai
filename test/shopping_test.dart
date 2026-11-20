import 'package:flutter_test/flutter_test.dart';
import 'package:universal_life_ai/features/pantry/data/pantry_models.dart';
import 'package:universal_life_ai/features/shopping/data/shopping_repository.dart';

void main() {
  test('De la despensa a la lista', () {
    final p = PantryItem(
      householdId: 'h',
      name: 'Leche',
      brand: 'A',
      unit: 'l',
      quantity: 0,
      barcode: '8410000000001',
    );
    final s = ShoppingItem.fromPantry(p);
    expect(s.name, 'Leche');
    expect(s.quantity, 1);
    expect(s.unit, 'l');
    expect(s.barcode, '8410000000001');
  });

  test('De la lista a la despensa con precio', () {
    const s = ShoppingItem(
      householdId: 'h',
      name: 'Pan',
      price: 1.2,
      isChecked: true,
    );
    final p = s.toPantry(PantryLocation.pantry);
    expect(p.name, 'Pan');
    expect(p.price, 1.2);
    expect(p.location, PantryLocation.pantry);
  });

  test('Cantidad legible oculta "1 ud"', () {
    expect(const ShoppingItem(householdId: 'h', name: 'Pan').quantityLabel, '');
    expect(
      const ShoppingItem(
        householdId: 'h',
        name: 'Arroz',
        quantity: 2,
        unit: 'kg',
      ).quantityLabel,
      '2 kg',
    );
  });
}
