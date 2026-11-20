/// Modelos del hogar. Los nombres de enum coinciden con los tipos de PostgreSQL.
enum MemberRole {
  owner('Administrador'),
  adult('Adulto'),
  teen('Adolescente'),
  child('Niño'),
  guest('Invitado');

  const MemberRole(this.label);
  final String label;

  static MemberRole parse(String v) => MemberRole.values.byName(v);
}

enum MemberStatus { active, suspended }

enum AppModule {
  dashboard('Panel'),
  pantry('Despensa'),
  shopping('Lista de la compra'),
  budget('Presupuesto'),
  recipes('Recetas'),
  wardrobe('Armario');

  const AppModule(this.label);
  final String label;
}

enum PermissionAction {
  view('Ver'),
  create('Crear'),
  edit('Editar'),
  delete('Eliminar'),
  approve('Aprobar');

  const PermissionAction(this.label);
  final String label;

  String get column => 'can_$name';
}

class Household {
  const Household({
    required this.id,
    required this.name,
    required this.ownerId,
    this.cityName,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String name;
  final String ownerId;
  final String? cityName;
  final double? latitude;
  final double? longitude;

  factory Household.fromJson(Map<String, dynamic> j) => Household(
    id: j['id'] as String,
    name: j['name'] as String,
    ownerId: j['owner_id'] as String,
    cityName: j['city_name'] as String?,
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
  );
}

class Member {
  const Member({
    required this.id,
    required this.householdId,
    required this.userId,
    required this.displayName,
    required this.role,
    required this.status,
  });

  final String id;
  final String householdId;
  final String? userId;
  final String displayName;
  final MemberRole role;
  final MemberStatus status;

  bool get isOwner => role == MemberRole.owner;
  bool get isActive => status == MemberStatus.active;

  factory Member.fromJson(Map<String, dynamic> j) => Member(
    id: j['id'] as String,
    householdId: j['household_id'] as String,
    userId: j['user_id'] as String?,
    displayName: j['display_name'] as String,
    role: MemberRole.parse(j['role'] as String),
    status: MemberStatus.values.byName(j['status'] as String),
  );
}

class ModulePermission {
  const ModulePermission({
    required this.memberId,
    required this.module,
    required this.allowed,
  });

  final String memberId;
  final AppModule module;
  final Set<PermissionAction> allowed;

  bool can(PermissionAction a) => allowed.contains(a);

  factory ModulePermission.fromJson(Map<String, dynamic> j) => ModulePermission(
    memberId: j['member_id'] as String,
    module: AppModule.values.byName(j['module'] as String),
    allowed: {
      for (final a in PermissionAction.values)
        if (j[a.column] == true) a,
    },
  );
}

class Invitation {
  const Invitation({
    required this.id,
    required this.displayName,
    required this.role,
    required this.code,
    required this.expiresAt,
    required this.acceptedAt,
  });

  final String id;
  final String displayName;
  final MemberRole role;
  final String code;
  final DateTime expiresAt;
  final DateTime? acceptedAt;

  bool get isPending => acceptedAt == null && expiresAt.isAfter(DateTime.now());

  factory Invitation.fromJson(Map<String, dynamic> j) => Invitation(
    id: j['id'] as String,
    displayName: j['display_name'] as String,
    role: MemberRole.parse(j['role'] as String),
    code: j['code'] as String,
    expiresAt: DateTime.parse(j['expires_at'] as String),
    acceptedAt: j['accepted_at'] == null
        ? null
        : DateTime.parse(j['accepted_at'] as String),
  );
}
