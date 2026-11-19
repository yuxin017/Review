import 'staff_access.dart';
import 'staff_records.dart';

/// Staff role business validation. Used by both create and edit flows.
/// Firestore still remains the final authority for restricted writes.
class StaffRoleRules {
  StaffRoleRules._();

  static String? validate({
    required Set<StaffRole> roles,
    required Iterable<StaffProfile> colleagues,
    String? editingUid,
  }) {
    if (roles.isEmpty) return 'Select at least one staff role.';
    if (roles.contains(StaffRole.superAdmin)) {
      return 'Super Admin cannot be assigned here.';
    }
    if (roles.contains(StaffRole.marketingStaff) && roles.length > 1) {
      return 'Marketing Staff cannot be combined with another staff role.';
    }
    if (roles.contains(StaffRole.operationsManager) && colleagues.any((p) =>
      p.uid != editingUid && p.eligibleRoles.contains(StaffRole.operationsManager))) {
      return 'Only one Operations Manager can be assigned. Remove that role from the existing manager first.';
    }
    return null;
  }

  static void toggle(Set<StaffRole> roles, StaffRole role, bool checked) {
    if (!checked) { roles.remove(role); return; }
    if (role == StaffRole.marketingStaff) {
      roles..clear()..add(role);
    } else {
      roles.remove(StaffRole.marketingStaff);
      roles.add(role);
    }
  }
}
