import 'package:flutter_test/flutter_test.dart';
import 'package:universal_life_ai/features/budget/budget.dart';
import 'package:universal_life_ai/features/pantry/data/pantry_models.dart';
import 'package:universal_life_ai/features/recipes/recipes.dart';

PantryItem p(String n, {double q = 1, DateTime? exp}) =>
    PantryItem(householdId: 'h', name: n, quantity: q, expiresOn: exp);

void main() {
  test('normalize quita tildes', () {
    expect(normalize(' Atún Plátano '), 'atun platano');
  });

  test('tortilla completa con huevos y patatas', () {
    final m = matchRecipes([p('Huevos camperos'), p('Patatas')]);
    final t = m.firstWhere((x) => x.recipe.name == 'Tortilla de patatas');
    expect(t.missingRequired, isEmpty);
    expect(m.first.missingRequired, isEmpty);
  });

  test('ignora productos agotados', () {
    final m = matchRecipes([p('Huevos', q: 0), p('Patatas')]);
    final t = m.firstWhere((x) => x.recipe.name == 'Tortilla de patatas');
    expect(t.missingRequired.map((i) => i.name), ['Huevos']);
  });

  test('prioriza lo que caduca', () {
    final today = DateTime(2026, 11, 20);
    final m = matchRecipes([
      p('Pan'),
      p('Tomate', exp: today),
      p('Yogur'),
      p('Plátano'),
    ], today: today);
    expect(m.first.recipe.name, 'Tostadas con tomate');
  });

  test('euros formatea', () {
    expect(euros(12.5), contains('12,50'));
  });
}
