import 'package:flutter_test/flutter_test.dart';
import '../../lib/admin/staff/staff_access.dart';
import '../../lib/admin/staff/staff_records.dart';
import '../../lib/admin/staff/staff_role_rules.dart';

void main() {
  StaffProfile employee(String uid, Set<StaffRole> roles) => StaffProfile(
    uid: uid, fullName: 'Test Employee', email: 'test@example.com',
    status: 'active', eligibleRoles: roles);

  test('Marketing is exclusive to all other staff roles', () {
    final roles = <StaffRole>{StaffRole.marketingStaff, StaffRole.photographer};
    expect(StaffRoleRules.validate(roles: roles, colleagues: []), isNotNull);
    StaffRoleRules.toggle(roles, StaffRole.marketingStaff, true);
    expect(roles, {StaffRole.marketingStaff});
    StaffRoleRules.toggle(roles, StaffRole.admissionStaff, true);
    expect(roles, {StaffRole.admissionStaff});
  });

  test('only one Operations Manager may be assigned', () {
    final colleagues = [employee('existing-manager', {StaffRole.operationsManager})];
    expect(StaffRoleRules.validate(
      roles: {StaffRole.operationsManager}, colleagues: colleagues,
      editingUid: 'other'), contains('Only one Operations Manager'));
    expect(StaffRoleRules.validate(
      roles: {StaffRole.operationsManager}, colleagues: colleagues,
      editingUid: 'existing-manager'), isNull);
  });

  test('empty role selection is rejected', () {
    expect(StaffRoleRules.validate(roles: {}, colleagues: []), isNotNull);
  });
}
