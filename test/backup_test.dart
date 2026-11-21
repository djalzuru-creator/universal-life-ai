import 'package:flutter_test/flutter_test.dart';
import 'package:universal_life_ai/features/backup/backup.dart';

void main() {
  test('nombres de archivo seguros y sin repetir', () {
    expect(safeName('Camisa: azul/rayas?'), 'Camisa azulrayas');
    expect(safeName('   '), 'sin nombre');
    final used = <String>{};
    expect(
      uniqueName(used, 'Armario/Dj/Camisa', 'jpg'),
      'Armario/Dj/Camisa.jpg',
    );
    expect(
      uniqueName(used, 'Armario/Dj/Camisa', 'jpg'),
      'Armario/Dj/Camisa (2).jpg',
    );
  });
}
