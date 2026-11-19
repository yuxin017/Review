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

  final bool superAdmin;
  final Set<StaffRole> roles;

  // Menu IDs must match AdminShell.open() and its existing sidebar.
  // viewOnly means non-destructive view access, not database write access.
  static const Map<StaffRole, Map<String, StaffMenuAccess>> _menus = {
    StaffRole.operationsManager: {
      'dashboard': StaffMenuAccess.manage,
      'visitors': StaffMenuAccess.viewOnly,
      'reports': StaffMenuAccess.viewOnly,
      'crowd': StaffMenuAccess.manage,
      'landmarks': StaffMenuAccess.manage,
      'anomalies': StaffMenuAccess.manage,
      'facilities': StaffMenuAccess.manage,
      'reservations': StaffMenuAccess.manage,
      'ride-entry': StaffMenuAccess.manage,
      'activity': StaffMenuAccess.manage,
      'support': StaffMenuAccess.viewOnly,
    },
    StaffRole.attractionOperator: {
      'dashboard': StaffMenuAccess.manage,
      'crowd': StaffMenuAccess.viewOnly,
      'facilities': StaffMenuAccess.viewOnly,
      'reservations': StaffMenuAccess.manage,
      'ride-entry': StaffMenuAccess.manage,
      'activity': StaffMenuAccess.manage,
    },
    StaffRole.admissionStaff: {
      'dashboard': StaffMenuAccess.manage,
      'visitors': StaffMenuAccess.viewOnly,
      'tickets': StaffMenuAccess.viewOnly,
      'packages': StaffMenuAccess.viewOnly,
      'validation': StaffMenuAccess.manage,
    },
    StaffRole.photographer: {
      'dashboard': StaffMenuAccess.manage,
      'photos': StaffMenuAccess.manage,
    },
    StaffRole.photoCounterStaff: {
      'dashboard': StaffMenuAccess.manage,
      'tickets': StaffMenuAccess.viewOnly,
      'photos': StaffMenuAccess.manage,
      'photo-kiosk': StaffMenuAccess.manage,
    },
    StaffRole.customerSupport: {
      'dashboard': StaffMenuAccess.manage,
      'visitors': StaffMenuAccess.viewOnly,
      'tickets': StaffMenuAccess.viewOnly,
      'packages': StaffMenuAccess.viewOnly,
      'promotions': StaffMenuAccess.viewOnly,
      'reservations': StaffMenuAccess.viewOnly,
      'support': StaffMenuAccess.manage,
    },
    StaffRole.marketingStaff: {
      'dashboard': StaffMenuAccess.manage,
      'packages': StaffMenuAccess.viewOnly,
      'promotions': StaffMenuAccess.manage,
      'reports': StaffMenuAccess.viewOnly,
    },
  };

  static const List<String> menuOrder = [
    'staff-my-work', 'dashboard', 'visitors', 'staff', 'commerce', 'tickets', 'packages', 'photos',
    'promotions', 'reports', 'crowd', 'landmarks', 'anomalies',
    'photo-kiosk', 'facilities', 'reservations', 'validation',
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
