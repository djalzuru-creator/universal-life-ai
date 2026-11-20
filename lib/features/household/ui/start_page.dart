import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/household_repository.dart';
import '../data/providers.dart';
import 'common.dart';

/// Primer paso tras crear la cuenta: crear un hogar (serás su administrador)
/// o unirte a uno con el código que te dio el administrador.
class StartPage extends ConsumerStatefulWidget {
  const StartPage({super.key});

  @override
  ConsumerState<StartPage> createState() => _StartPageState();
}

class _StartPageState extends ConsumerState<StartPage> {
  final _householdName = TextEditingController();
  final _ownerName = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _householdName.dispose();
    _ownerName.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final hid = await action();
      ref.invalidate(myMembershipsProvider);
      if (mounted) context.go('/h/$hid');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(householdRepositoryProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Empezar'),
        actions: [
          IconButton(
            tooltip: 'Salir',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(supabaseProvider).auth.signOut(),
          ),
        ],
      ),
      body: PageBody(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Crear mi hogar', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text(
                    'Serás el administrador y podrás invitar a tu familia.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _householdName,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del hogar',
                      hintText: 'Casa Alzuru',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ownerName,
                    decoration: const InputDecoration(
                      labelText: 'Tu nombre en el hogar',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_householdName.text.trim().isEmpty ||
                                _ownerName.text.trim().isEmpty) {
                              showSnack(context, 'Rellena los dos nombres.');
                              return;
                            }
                            _run(
                              () => repo.createHousehold(
                                name: _householdName.text.trim(),
                                ownerName: _ownerName.text.trim(),
                              ),
                            );
                          },
                    child: const Text('Crear hogar'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Unirme con un código',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pide el código de invitación al administrador de tu hogar.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Código de 8 caracteres',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_code.text.trim().length != 8) {
                              showSnack(
                                context,
                                'El código tiene 8 caracteres.',
                              );
                              return;
                            }
                            _run(
                              () => repo.acceptInvitation(_code.text.trim()),
                            );
                          },
                    child: const Text('Unirme'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
