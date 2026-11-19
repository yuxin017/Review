import 'package:flutter_test/flutter_test.dart';
import 'package:collaborative_asg/admin/staff/staff_access.dart';
import 'package:collaborative_asg/admin/staff/staff_records.dart';
import 'package:collaborative_asg/admin/staff/staff_portal_navigation.dart';

StaffProfile profile(Set<StaffRole> roles, {String status = 'active'}) => StaffProfile(
  uid: 'test-staff-uid',
  fullName: 'Demo Employee',
  email: 'employee@example.com',
  status: status,
  eligibleRoles: roles,
);

void main() {
  test('Super Admin retains all 18 sidebar entries', () {
    const navigation = StaffPortalNavigation.superAdmin();
    expect(navigation.availableMenus, StaffPortalNavigation.menuOrder);
    expect(navigation.accessFor('staff'), StaffMenuAccess.manage);
    expect(navigation.accessFor('fake'), StaffMenuAccess.hidden);
  });

  test('operationsManager sees the correct scoped tabs', () {
    final navigation = StaffPortalNavigation.employee(profile({StaffRole.operationsManager}));
    const expected = <String, StaffMenuAccess>{'dashboard': StaffMenuAccess.manage, 'visitors': StaffMenuAccess.viewOnly, 'reports': StaffMenuAccess.viewOnly, 'crowd': StaffMenuAccess.manage, 'landmarks': StaffMenuAccess.manage, 'anomalies': StaffMenuAccess.manage, 'facilities': StaffMenuAccess.manage, 'reservations': StaffMenuAccess.manage, 'ride-entry': StaffMenuAccess.manage, 'activity': StaffMenuAccess.manage, 'support': StaffMenuAccess.viewOnly};
    expect(navigation.availableMenus.toSet(), expected.keys.toSet());
    for (final entry in expected.entries) {
      expect(navigation.accessFor(entry.key), entry.value, reason: entry.key);
    }
    expect(navigation.allows('staff'), isFalse);
  });

  test('attractionOperator sees the correct scoped tabs', () {
    final navigation = StaffPortalNavigation.employee(profile({StaffRole.attractionOperator}));
    const expected = <String, StaffMenuAccess>{'dashboard': StaffMenuAccess.manage, 'crowd': StaffMenuAccess.viewOnly, 'facilities': StaffMenuAccess.viewOnly, 'reservations': StaffMenuAccess.manage, 'ride-entry': StaffMenuAccess.manage, 'activity': StaffMenuAccess.manage};
    expect(navigation.availableMenus.toSet(), expected.keys.toSet());
    for (final entry in expected.entries) {
      expect(navigation.accessFor(entry.key), entry.value, reason: entry.key);
    }
    expect(navigation.allows('staff'), isFalse);
  });

  test('admissionStaff sees the correct scoped tabs', () {
    final navigation = StaffPortalNavigation.employee(profile({StaffRole.admissionStaff}));
    const expected = <String, StaffMenuAccess>{'dashboard': StaffMenuAccess.manage, 'visitors': StaffMenuAccess.viewOnly, 'tickets': StaffMenuAccess.viewOnly, 'packages': StaffMenuAccess.viewOnly, 'validation': StaffMenuAccess.manage};
    expect(navigation.availableMenus.toSet(), expected.keys.toSet());
    for (final entry in expected.entries) {
      expect(navigation.accessFor(entry.key), entry.value, reason: entry.key);
    }
    expect(navigation.allows('staff'), isFalse);
  });

  test('photographer sees the correct scoped tabs', () {
    final navigation = StaffPortalNavigation.employee(profile({StaffRole.photographer}));
    const expected = <String, StaffMenuAccess>{'dashboard': StaffMenuAccess.manage, 'photos': StaffMenuAccess.manage};
    expect(navigation.availableMenus.toSet(), expected.keys.toSet());
    for (final entry in expected.entries) {
      expect(navigation.accessFor(entry.key), entry.value, reason: entry.key);
    }
    expect(navigation.allows('staff'), isFalse);
  });

  test('photoCounterStaff sees the correct scoped tabs', () {
    final navigation = StaffPortalNavigation.employee(profile({StaffRole.photoCounterStaff}));
    const expected = <String, StaffMenuAccess>{'dashboard': StaffMenuAccess.manage, 'tickets': StaffMenuAccess.viewOnly, 'photos': StaffMenuAccess.manage, 'photo-kiosk': StaffMenuAccess.manage};
    expect(navigation.availableMenus.toSet(), expected.keys.toSet());
    for (final entry in expected.entries) {
      expect(navigation.accessFor(entry.key), entry.value, reason: entry.key);
    }
    expect(navigation.allows('staff'), isFalse);
  });

  test('customerSupport sees the correct scoped tabs', () {
    final navigation = StaffPortalNavigation.employee(profile({StaffRole.customerSupport}));
    const expected = <String, StaffMenuAccess>{'dashboard': StaffMenuAccess.manage, 'visitors': StaffMenuAccess.viewOnly, 'tickets': StaffMenuAccess.viewOnly, 'packages': StaffMenuAccess.viewOnly, 'promotions': StaffMenuAccess.viewOnly, 'reservations': StaffMenuAccess.viewOnly, 'support': StaffMenuAccess.manage};
    expect(navigation.availableMenus.toSet(), expected.keys.toSet());
    for (final entry in expected.entries) {
      expect(navigation.accessFor(entry.key), entry.value, reason: entry.key);
    }
    expect(navigation.allows('staff'), isFalse);
  });

  test('marketingStaff sees the correct scoped tabs', () {
    final navigation = StaffPortalNavigation.employee(profile({StaffRole.marketingStaff}));
    const expected = <String, StaffMenuAccess>{'dashboard': StaffMenuAccess.manage, 'packages': StaffMenuAccess.viewOnly, 'promotions': StaffMenuAccess.manage, 'reports': StaffMenuAccess.viewOnly};
    expect(navigation.availableMenus.toSet(), expected.keys.toSet());
    for (final entry in expected.entries) {
      expect(navigation.accessFor(entry.key), entry.value, reason: entry.key);
    }
    expect(navigation.allows('staff'), isFalse);
  });

  test('Multiple roles combine tabs using the most permissive role', () {
    final nav = StaffPortalNavigation.employee(profile({
      StaffRole.photographer,
      StaffRole.customerSupport,
    }));
    expect(nav.allows('photos'), isTrue);
    expect(nav.readOnly('tickets'), isTrue);
    expect(nav.allows('staff'), isFalse);
  });

  test('Inactive staff have only the dashboard entry', () {
    final nav = StaffPortalNavigation.employee(profile(
      {StaffRole.operationsManager}, status: 'suspended',
    ));
    expect(nav.availableMenus, ['dashboard']);
  });
}
