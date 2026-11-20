import 'staff_access.dart';
import 'staff_records.dart';

/// Only controls which AdminShell tabs are visible to each employee.
/// Actual reads/writes MUST still be authorised by Firebase rules or APIs.
enum StaffMenuAccess { hidden, viewOnly, manage }

class StaffPortalNavigation {
  const StaffPortalNavigation._(this.superAdmin, this.roles);

  const StaffPortalNavigation.superAdmin() : this._(true, const <StaffRole>{});

  factory StaffPortalNavigation.employee(StaffProfile profile) =>
      StaffPortalNavigation._(
        false,
        profile.status == 'active' ? profile.eligibleRoles : const {},
      );

  factory StaffPortalNavigation.onDuty(StaffRole? role) =>
      StaffPortalNavigation._(false, role == null ? const {} : {role});

  final bool superAdmin;
  final Set<StaffRole> roles;

  // Menu IDs must match AdminShell.open() and its existing sidebar.
  // viewOnly means non-destructive view access, not database write access.
  static const Map<StaffRole, Map<String, StaffMenuAccess>> _menus = {
    StaffRole.operationsManager: {
      'reports': StaffMenuAccess.viewOnly,
      'crowd': StaffMenuAccess.viewOnly,
      'landmarks': StaffMenuAccess.manage,
      'facilities': StaffMenuAccess.manage,
      'reservations': StaffMenuAccess.viewOnly,
    },
    StaffRole.attractionOperator: {'ride-entry': StaffMenuAccess.manage},
    StaffRole.admissionStaff: {'validation': StaffMenuAccess.manage},
    StaffRole.photographer: {'photos': StaffMenuAccess.manage},
    StaffRole.customerSupport: {'support': StaffMenuAccess.manage},
    StaffRole.marketingStaff: {
      'promotions': StaffMenuAccess.manage,
      'reports': StaffMenuAccess.viewOnly,
    },
  };

  String get landingPage => [
    'validation', 'ride-entry', 'photos', 'promotions',
    'support', 'reports', 'reservations',
  ].where(allows).firstOrNull ?? 'staff-my-work';

  static const List<String> menuOrder = [
    'staff-my-work', 'dashboard', 'visitors', 'staff', 'commerce', 'tickets', 'packages', 'photos',
    'promotions', 'reports', 'crowd', 'landmarks', 'anomalies',
    'facilities', 'reservations', 'validation',
    'ride-entry', 'activity', 'support',
  ];

  StaffMenuAccess accessFor(String menuId) {
    if (!menuOrder.contains(menuId)) return StaffMenuAccess.hidden;
    if (menuId == 'staff-my-work') return superAdmin ? StaffMenuAccess.hidden : StaffMenuAccess.manage;
    if (superAdmin) return StaffMenuAccess.manage;
    if (menuId == 'dashboard') return StaffMenuAccess.manage;
    var result = StaffMenuAccess.hidden;
    for (final role in roles) {
      final roleAccess = _menus[role]?[menuId] ?? StaffMenuAccess.hidden;
      if (roleAccess.index > result.index) result = roleAccess;
    }
    return result;
  }

  bool allows(String menuId) => accessFor(menuId) != StaffMenuAccess.hidden;

  bool readOnly(String menuId) =>
      accessFor(menuId) == StaffMenuAccess.viewOnly;

  bool get isRestricted => !superAdmin;

  String get roleLabel {
    if (superAdmin) return 'Super Admin';
    final names = roles.map((e) => e.label).toList()..sort();
    return names.isEmpty ? 'Staff' : names.join(', ');
  }

  List<String> get availableMenus => [
    for (final item in menuOrder)
      if (allows(item)) item,
  ];
}
