import 'package:flutter_test/flutter_test.dart';
import 'package:universal_life_ai/features/ai/aguilucho_ai.dart';

void main() {
  test('lee una receta de la IA aunque falten campos', () {
    final r = AiRecipe.fromJson({
      'name': 'Tortilla',
      'ingredients': ['4 huevos', 2],
      'steps': ['Batir'],
    });
    expect(r.name, 'Tortilla');
    expect(r.minutes, 30);
    expect(r.ingredients, ['4 huevos', '2']);
    expect(r.missing, isEmpty);
  });

  test('los errores de la IA salen en español', () {
    expect(aiErrorMessage('sin_clave'), contains('clave de Gemini'));
    expect(aiErrorMessage('clave_mala'), contains('no vale'));
    expect(aiErrorMessage('otra cosa'), contains('Prueba otra vez'));
  });
}
