import 'package:flutter_test/flutter_test.dart';
import 'package:collaborative_asg/admin/staff/staff_access.dart';
import 'package:collaborative_asg/admin/staff/staff_spark_policy.dart';

void main() {
  test('normalize real employee email', () {
    expect(StaffSparkPolicy.normalizeEmail('  Staff@Example.COM  '),
        'staff@example.com');
  });
  test('accept regular staff, not a super admin assignment', () {
    StaffSparkPolicy.validate(
      fullName: 'Park Photographer',
      email: 'photographer@example.com',
      eligibleRoles: {StaffRole.photographer},
    );
    expect(() => StaffSparkPolicy.validate(
      fullName: 'Park Photographer',
      email: 'photographer@example.com',
      eligibleRoles: {StaffRole.superAdmin},
    ), throwsArgumentError);
  });
  test('reject blank name, invalid email, empty roles', () {
    for (final input in [
      (' ', 'staff@example.com', {StaffRole.photographer}),
      ('Staff Test', 'not-an-email', {StaffRole.photographer}),
      ('Staff Test', 'staff@example.com', <StaffRole>{}),
    ]) {
      expect(() => StaffSparkPolicy.validate(
        fullName: input.$1, email: input.$2, eligibleRoles: input.$3,
      ), throwsArgumentError);
    }
  });
  test('new staff ID matches deployed STF-eight-digit rules', () {
    expect(StaffSparkPolicy.staffIdFromNumber(12345678), 'STF-12345678');
    expect(() => StaffSparkPolicy.staffIdFromNumber(123), throwsArgumentError);
  });
}
