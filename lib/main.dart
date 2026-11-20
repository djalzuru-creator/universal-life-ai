import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/router.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Env.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
  );
  runApp(const ProviderScope(child: UniversalLifeApp()));
}

class UniversalLifeApp extends ConsumerWidget {
  const UniversalLifeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Universal Life AI',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Falta la configuración de Supabase.\n\n'
              'Copia config/dev.example.json a config/dev.json, rellena tus claves '
              'y ejecuta:\nflutter run --dart-define-from-file=config/dev.json',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
