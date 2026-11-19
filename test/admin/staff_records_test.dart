import 'package:flutter_test/flutter_test.dart';
import 'package:collaborative_asg/admin/staff/staff_access.dart';
import 'package:collaborative_asg/admin/staff/staff_records.dart';

void main() {
  final now = DateTime.utc(2026, 11, 17, 12);

  StaffProfile staff({
    String status = 'active',
    Set<StaffRole> roles = const {StaffRole.attractionOperator},
  }) => StaffProfile(
        uid: 'staff-a',
        fullName: 'Park Operator',
        email: 'staff@example.com',
        status: status,
        eligibleRoles: roles,
      );

  StaffQualification training({
    String staffUid = 'staff-a',
    StaffRole role = StaffRole.attractionOperator,
    String status = 'approved',
    String? attractionId = 'ferris-wheel',
    DateTime? expiresAt,
  }) => StaffQualification(
        id: 'qualification-a',
        staffUid: staffUid,
        role: role,
        title: 'Ride Safety Training',
        status: status,
        completedAt: DateTime.utc(2026, 1, 1),
        expiresAt: expiresAt,
        attractionId: attractionId,
      );

  test('active trained operator can operate the specific attraction', () {
    expect(
        StaffTrainingPolicy.isEligible(
          staff: staff(),
          qualifications: [training()],
          role: StaffRole.attractionOperator,
          attractionId: 'ferris-wheel',
          at: now,
        ),
        isTrue);
  });

  test('training for Ferris Wheel does not qualify a Carousel operator', () {
    expect(
        StaffTrainingPolicy.isEligible(
          staff: staff(),
          qualifications: [training()],
          role: StaffRole.attractionOperator,
          attractionId: 'carousel',
          at: now,
        ),
        isFalse);
  });

  test('revoked or expired training is rejected', () {
    for (final record in [
      training(status: 'revoked'),
      training(expiresAt: DateTime.utc(2026, 11, 16)),
    ]) {
      expect(
          StaffTrainingPolicy.isEligible(
            staff: staff(),
            qualifications: [record],
            role: StaffRole.attractionOperator,
            attractionId: 'ferris-wheel',
            at: now,
          ),
          isFalse);
    }
  });

  test('inactive employee cannot work despite training', () {
    expect(
        StaffTrainingPolicy.isEligible(
          staff: staff(status: 'suspended'),
          qualifications: [training()],
          role: StaffRole.attractionOperator,
          attractionId: 'ferris-wheel',
          at: now,
        ),
        isFalse);
  });

  test('training of another employee cannot be reused', () {
    expect(
        StaffTrainingPolicy.isEligible(
          staff: staff(),
          qualifications: [training(staffUid: 'staff-b')],
          role: StaffRole.attractionOperator,
          attractionId: 'ferris-wheel',
          at: now,
        ),
        isFalse);
  });

  test('admission staff also requires training', () {
    final employee = staff(roles: {StaffRole.admissionStaff});
    expect(
        StaffTrainingPolicy.isEligible(
          staff: employee,
          qualifications: const [],
          role: StaffRole.admissionStaff,
          at: now,
        ),
        isFalse);
    expect(
        StaffTrainingPolicy.isEligible(
          staff: employee,
          qualifications: [training(role: StaffRole.admissionStaff)],
          role: StaffRole.admissionStaff,
          at: now,
        ),
        isTrue);
  });

  test('a staff profile can never grant Super Admin claim', () {
    final profile = StaffProfile.fromMap('staff-a', {
      'fullName': 'Test',
      'email': 'staff@example.com',
      'status': 'active',
      'eligibleRoles': ['photographer', 'super_admin', 'unknown_role'],
    });
    expect(profile.eligibleRoles, {StaffRole.photographer});
  });
}
