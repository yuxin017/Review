import 'package:collaborative_asg/admin/staff/staff_access.dart';
import 'package:collaborative_asg/admin/staff/staff_records.dart';
import 'package:collaborative_asg/admin/staff/staff_schedule_arrangement.dart';
import 'package:flutter_test/flutter_test.dart';

StaffProfile staff(String uid, Set<StaffRole> roles) => StaffProfile(
  uid: uid,
  fullName: uid,
  email: '',
  status: 'active',
  eligibleRoles: roles,
);

void main() {
  final monday = DateTime(2026, 11, 16);
  const operator = StaffRole.attractionOperator;
  const admission = StaffRole.admissionStaff;
  StaffQualification qualification(
    String uid,
    StaffRole role, {
    DateTime? expiry,
  }) => StaffQualification(
    id: '$uid-${role.code}',
    staffUid: uid,
    role: role,
    title: role.label,
    status: 'approved',
    completedAt: DateTime.utc(2025),
    expiresAt: expiry,
    attractionId: role == operator ? 'coaster' : null,
  );

  test('coverage moves a flexible worker to admission when needed', () {
    final result = arrangeStaffWeek(
      monday: monday,
      roles: {operator, admission},
      directory: [
        staff('A', {operator, admission}),
        staff('B', {operator}),
      ],
      availability: {
        'A': {'2026-11-16'},
        'B': {'2026-11-16'},
      },
      leaves: [],
      qualifications: [
        qualification('A', operator),
        qualification('A', admission),
        qualification('B', operator),
      ],
    );
    expect(result.assignments.map((shift) => shift.staffUid), ['B', 'A']);
    expect(result.assignments.first.attractionId, 'coaster');
    expect(result.gaps, hasLength(12));
  });

  test('approved leave and mid-shift training expiry prevent assignments', () {
    final result = arrangeStaffWeek(
      monday: monday,
      roles: {admission},
      directory: [
        staff('A', {admission}),
        staff('B', {admission}),
      ],
      availability: {
        'A': {'2026-11-16'},
        'B': {'2026-11-16'},
      },
      leaves: [
        {
          'staffUid': 'A',
          'status': 'approved',
          'startOn': '2026-11-16',
          'endOn': '2026-11-16',
        },
      ],
      qualifications: [
        qualification('A', admission),
        qualification('B', admission, expiry: DateTime.utc(2026, 11, 16, 4)),
      ],
    );
    expect(result.assignments, isEmpty);
    expect(result.gaps, hasLength(7));
  });

  test('a worker receives at most five shifts per week', () {
    final result = arrangeStaffWeek(
      monday: monday,
      roles: {admission},
      directory: [
        staff('A', {admission}),
      ],
      availability: {
        'A': {for (var day = 16; day <= 22; day++) '2026-11-$day'},
      },
      leaves: [],
      qualifications: [qualification('A', admission)],
    );
    expect(result.assignments, hasLength(5));
    expect(result.gaps, hasLength(2));
  });

  test('regular-duty staff stay out of rotating shift coverage', () {
    const manager = StaffRole.operationsManager;
    const marketing = StaffRole.marketingStaff;
    final result = arrangeStaffWeek(
      monday: monday,
      roles: {operator, manager, marketing},
      directory: [
        staff('A', {manager, operator}),
        staff('B', {marketing}),
      ],
      availability: {
        'A': {'2026-11-16'},
        'B': {'2026-11-16'},
      },
      leaves: [],
      qualifications: [qualification('A', operator)],
    );
    expect(result.assignments, isEmpty);
    expect(result.gaps, hasLength(7));
  });
}
