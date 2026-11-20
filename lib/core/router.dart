import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/login_page.dart';
import '../features/household/data/providers.dart';
import '../features/household/ui/admin_page.dart';
import '../features/household/ui/dashboard_page.dart';
import '../features/household/ui/home_page.dart';
import '../features/household/ui/member_permissions_page.dart';
import '../features/household/ui/start_page.dart';

/// Avisa al router cuando cambia la sesión para recalcular redirecciones.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(GoTrueClient auth) {
    _sub = auth.onAuthStateChange.listen((_) => notifyListeners());
  }
  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(supabaseProvider).auth;
  final listenable = _AuthListenable(auth);
  ref.onDispose(listenable.dispose);

  return GoRouter(
    refreshListenable: listenable,
    redirect: (context, state) {
      final loggedIn = auth.currentSession != null;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn) return atLogin ? null : '/login';
      if (atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/', builder: (_, _) => const HomePage()),
      GoRoute(path: '/start', builder: (_, _) => const StartPage()),
      GoRoute(
        path: '/h/:hid',
        builder: (_, s) => DashboardPage(householdId: s.pathParameters['hid']!),
        routes: [
          GoRoute(
            path: 'admin',
            builder: (_, s) => AdminPage(householdId: s.pathParameters['hid']!),
            routes: [
              GoRoute(
                path: 'member/:mid',
                builder: (_, s) => MemberPermissionsPage(
                  householdId: s.pathParameters['hid']!,
                  memberId: s.pathParameters['mid']!,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
