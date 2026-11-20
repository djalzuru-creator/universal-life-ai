import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_life_ai/features/auth/login_page.dart';

void main() {
  testWidgets('El formulario valida correo y contraseña', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginPage())),
    );
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(find.text('Escribe un correo válido'), findsOneWidget);
    expect(find.text('Mínimo 8 caracteres'), findsOneWidget);

    await tester.tap(find.text('Crear una cuenta nueva'));
    await tester.pump();
    expect(find.text('Crear cuenta'), findsOneWidget);
  });
}
