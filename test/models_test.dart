import 'package:flutter_test/flutter_test.dart';
import 'package:universal_life_ai/features/household/data/household_repository.dart';
import 'package:universal_life_ai/features/household/data/models.dart';

void main() {
  test('Member se lee desde la fila de Supabase', () {
    final m = Member.fromJson({
      'id': 'm1',
      'household_id': 'h1',
      'user_id': 'u1',
      'display_name': 'Dj',
      'role': 'owner',
      'status': 'active',
    });
    expect(m.isOwner, isTrue);
    expect(m.isActive, isTrue);
    expect(m.role.label, 'Administrador');
  });

  test('ModulePermission solo incluye las acciones marcadas', () {
    final p = ModulePermission.fromJson({
      'member_id': 'm2',
      'module': 'budget',
      'can_view': true,
      'can_create': false,
      'can_edit': false,
      'can_delete': false,
      'can_approve': false,
    });
    expect(p.module, AppModule.budget);
    expect(p.can(PermissionAction.view), isTrue);
    expect(p.can(PermissionAction.edit), isFalse);
  });

  test('Los enums coinciden con los tipos de la base de datos', () {
    expect(MemberRole.values.map((r) => r.name), [
      'owner',
      'adult',
      'teen',
      'child',
      'guest',
    ]);
    expect(AppModule.values.map((m) => m.name), [
      'dashboard',
      'pantry',
      'shopping',
      'budget',
      'recipes',
      'wardrobe',
    ]);
    expect(PermissionAction.values.map((a) => a.column), [
      'can_view',
      'can_create',
      'can_edit',
      'can_delete',
      'can_approve',
    ]);
  });

  test('Invitación caducada no está pendiente', () {
    final inv = Invitation.fromJson({
      'id': 'i1',
      'display_name': 'Hijo',
      'role': 'teen',
      'code': 'ABCD1234',
      'expires_at': DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String(),
      'accepted_at': null,
    });
    expect(inv.isPending, isFalse);
  });

  test('Los errores de la base de datos se traducen', () {
    expect(
      friendlyError(Exception('invalid_or_expired_code')),
      'El código no es válido o ha caducado.',
    );
  });
}
