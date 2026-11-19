import 'package:flutter_test/flutter_test.dart';
import 'package:collaborative_asg/admin/staff/staff_portal_policy.dart';

void main() {
  StaffPortalStage check({
    bool signedIn = true,
    bool hasStaffProfile = true,
    bool emailVerified = true,
    String? profileStatus = 'active',
  }) => StaffPortalPolicy.evaluate(
        signedIn: signedIn,
        hasStaffProfile: hasStaffProfile,
        emailVerified: emailVerified,
        profileStatus: profileStatus,
      );

  test('signed out account sees login', () {
    expect(check(signedIn: false), StaffPortalStage.signIn);
  });
  test('visitor without admin-approved Staff Profile is rejected', () {
    expect(check(hasStaffProfile: false), StaffPortalStage.notStaff);
  });
  test('employee needs to verify real email inbox', () {
    expect(check(emailVerified: false), StaffPortalStage.verifyEmail);
  });
  test('new employee is inactive until supervisor approves', () {
    expect(check(profileStatus: 'inactive'), StaffPortalStage.pendingApproval);
  });
  test('suspended employee cannot enter read-only dashboard', () {
    expect(check(profileStatus: 'suspended'), StaffPortalStage.suspended);
  });
  test('verified, active employee sees read-only dashboard', () {
    expect(check(), StaffPortalStage.ready);
  });
  test('unknown status cannot grant employee access', () {
    expect(check(profileStatus: null), StaffPortalStage.notStaff);
    expect(check(profileStatus: 'pending'), StaffPortalStage.notStaff);
  });
}
