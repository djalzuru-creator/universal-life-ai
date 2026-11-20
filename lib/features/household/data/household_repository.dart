import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Acceso a Supabase. Toda la seguridad real está en las políticas RLS:
/// aquí no se decide quién puede qué, solo se piden los datos.
class HouseholdRepository {
  HouseholdRepository(this._db);

  final SupabaseClient _db;

  String? get _uid => _db.auth.currentUser?.id;

  /// Membresías activas del usuario actual (una por hogar).
  Future<List<Member>> myMemberships() async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _db
        .from('members')
        .select()
        .eq('user_id', uid)
        .eq('status', 'active');
    return rows.map(Member.fromJson).toList();
  }

  Future<Household> household(String id) async {
    final row = await _db.from('households').select().eq('id', id).single();
    return Household.fromJson(row);
  }

  Future<List<Member>> members(String householdId) async {
    final rows = await _db
        .from('members')
        .select()
        .eq('household_id', householdId)
        .order('created_at');
    return rows.map(Member.fromJson).toList();
  }

  Future<List<ModulePermission>> permissions(String memberId) async {
    final rows = await _db
        .from('member_permissions')
        .select()
        .eq('member_id', memberId);
    return rows.map(ModulePermission.fromJson).toList();
  }

  Future<String> createHousehold({
    required String name,
    required String ownerName,
  }) async {
    final id = await _db.rpc(
      'create_household',
      params: {'household_name': name, 'owner_name': ownerName},
    );
    return id as String;
  }

  Future<String> acceptInvitation(String code) async {
    final id = await _db.rpc(
      'accept_invitation',
      params: {'invite_code': code},
    );
    return id as String;
  }

  Future<Invitation> createInvitation({
    required String householdId,
    required String displayName,
    required MemberRole role,
  }) async {
    final row = await _db
        .from('invitations')
        .insert({
          'household_id': householdId,
          'display_name': displayName,
          'role': role.name,
          'created_by': _uid,
        })
        .select()
        .single();
    return Invitation.fromJson(row);
  }

  Future<List<Invitation>> invitations(String householdId) async {
    final rows = await _db
        .from('invitations')
        .select()
        .eq('household_id', householdId)
        .order('expires_at', ascending: false);
    return rows.map(Invitation.fromJson).toList();
  }

  /// Últimos cambios administrativos (solo visible para el administrador).
  Future<List<Map<String, dynamic>>> auditLog(
    String householdId, {
    int limit = 20,
  }) => _db
      .from('audit_log')
      .select()
      .eq('household_id', householdId)
      .order('created_at', ascending: false)
      .limit(limit);

  Future<void> deleteInvitation(String id) =>
      _db.from('invitations').delete().eq('id', id);

  Future<void> updateMember(
    String memberId, {
    MemberRole? role,
    MemberStatus? status,
  }) => _db
      .from('members')
      .update({
        if (role != null) 'role': role.name,
        if (status != null) 'status': status.name,
      })
      .eq('id', memberId);

  Future<void> removeMember(String memberId) =>
      _db.from('members').delete().eq('id', memberId);

  Future<void> setPermission(
    String memberId,
    AppModule module,
    PermissionAction action,
    bool value,
  ) => _db
      .from('member_permissions')
      .update({action.column: value})
      .eq('member_id', memberId)
      .eq('module', module.name);
}

/// Convierte los errores de la base de datos en mensajes para la familia.
String friendlyError(Object e) {
  final msg = e is PostgrestException
      ? e.message
      : e is AuthException
      ? e.message
      : '$e';
  const known = {
    'invalid_or_expired_code': 'El código no es válido o ha caducado.',
    'already_member': 'Ya formas parte de este hogar.',
    'owner_cannot_be_removed': 'El administrador no se puede eliminar.',
    'owner_cannot_be_changed':
        'El administrador no se puede suspender ni cambiar de rol.',
    'only_one_owner': 'Solo puede haber un administrador por hogar.',
    'Invalid login credentials': 'Correo o contraseña incorrectos.',
  };
  for (final entry in known.entries) {
    if (msg.contains(entry.key)) return entry.value;
  }
  return 'Algo ha fallado: $msg';
}
