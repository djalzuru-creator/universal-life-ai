import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_life_ai/features/wardrobe/data/wardrobe_models.dart';
import 'package:universal_life_ai/features/wardrobe/ui/fitting_room.dart';

Garment g(String n, GarmentCategory c) =>
    Garment(id: n, householdId: 'h', memberId: 'm', name: n, category: c);

void main() {
  testWidgets('el conjunto se ve en vertical: arriba, abajo y zapatos', (
    t,
  ) async {
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: OutfitStack([
                g('Zapatillas', GarmentCategory.shoes),
                g('Vaquero', GarmentCategory.bottom),
                g('Camiseta', GarmentCategory.top),
                g('Chaqueta', GarmentCategory.outerwear),
              ]),
            ),
          ),
        ),
      ),
    );
    final top = t.getTopLeft(find.byIcon(GarmentCategory.top.icon)).dy;
    final bottom = t.getTopLeft(find.byIcon(GarmentCategory.bottom.icon)).dy;
    final shoes = t.getTopLeft(find.byIcon(GarmentCategory.shoes.icon)).dy;
    expect(top < bottom && bottom < shoes, isTrue);
    expect(t.takeException(), isNull);
  });
}
