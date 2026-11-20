import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'household_repository.dart';
import 'models.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final householdRepositoryProvider = Provider(
  (ref) => HouseholdRepository(ref.watch(supabaseProvider)),
);

/// Emite cada cambio de sesión (entrar, salir, refrescar token).
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

final myMembershipsProvider = FutureProvider<List<Member>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(householdRepositoryProvider).myMemberships();
});

final householdProvider = FutureProvider.family<Household, String>(
  (ref, id) => ref.watch(householdRepositoryProvider).household(id),
);

final membersProvider = FutureProvider.family<List<Member>, String>(
  (ref, householdId) =>
      ref.watch(householdRepositoryProvider).members(householdId),
);

final permissionsProvider =
    FutureProvider.family<List<ModulePermission>, String>(
      (ref, memberId) =>
          ref.watch(householdRepositoryProvider).permissions(memberId),
    );

final invitationsProvider = FutureProvider.family<List<Invitation>, String>(
  (ref, householdId) =>
      ref.watch(householdRepositoryProvider).invitations(householdId),
);

final auditLogProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
      (ref, householdId) =>
          ref.watch(householdRepositoryProvider).auditLog(householdId),
    );

/// Mi membresía dentro de un hogar concreto (null si no pertenezco).
final myMemberProvider = FutureProvider.family<Member?, String>((
  ref,
  householdId,
) async {
  final list = await ref.watch(myMembershipsProvider.future);
  for (final m in list) {
    if (m.householdId == householdId) return m;
  }
  return null;
});
