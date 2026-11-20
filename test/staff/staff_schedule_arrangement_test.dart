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

  test('an entrance worker covers all seven days when eligible', () {
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
    expect(result.assignments, hasLength(7));
    expect(result.gaps, isEmpty);
  });

  test('three attractions and the entrance have dedicated coverage every day', () {
    const rides = {'coaster': 'Coaster', 'wheel': 'Ferris Wheel', 'cars': 'Bumper Cars'};
    final employees = [
      staff('gate', {admission}),
      for (final ride in rides.keys) staff(ride, {operator}),
    ];
    final result = arrangeStaffWeek(
      monday: monday,
      roles: {admission, operator, StaffRole.photographer},
      directory: employees,
      availability: {
        for (final employee in employees)
          employee.uid: {for (var day = 16; day <= 22; day++) '2026-11-$day'},
      },
      leaves: [],
      qualifications: [
        qualification('gate', admission),
        for (final ride in rides.keys)
          StaffQualification(
            id: ride, staffUid: ride, role: operator, title: rides[ride]!,
            status: 'approved', completedAt: DateTime.utc(2025), attractionId: ride,
          ),
      ],
      attractions: rides,
    );
    expect(result.gaps, hasLength(7));
    for (var day = 16; day <= 22; day++) {
      final shifts = result.assignments.where((shift) => shift.date.day == day);
      expect(shifts.where((shift) => shift.roleCode == admission.code), hasLength(1));
      expect(shifts.map((shift) => shift.attractionId).whereType<String>(), unorderedEquals(rides.keys));
    }
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

  test(
    'each open ride has its own required post and optional staff never masks a shortage',
    () {
      final result = arrangeStaffWeek(
        monday: monday,
        roles: {operator, admission},
        directory: [
          staff('A', {operator, admission}),
          staff('B', {admission}),
          staff('C', {admission}),
        ],
        availability: {
          for (final uid in ['A', 'B', 'C']) uid: {'2026-11-16'},
        },
        leaves: [],
        qualifications: [
          qualification('A', operator),
          qualification('A', admission),
          qualification('B', admission),
          qualification('C', admission),
        ],
        attractions: {'coaster': 'Coaster', 'wheel': 'Ferris Wheel'},
      );
      final mondayShifts = result.assignments
          .where((shift) => shift.date == monday)
          .toList();
      expect(mondayShifts, hasLength(3));
      expect(mondayShifts.map((shift) => shift.docId).toSet(), hasLength(3));
      expect(
        mondayShifts
            .singleWhere((shift) => shift.attractionId != null)
            .attractionId,
        'coaster',
      );
      expect(
        result.gaps.where((gap) => gap.startsWith('2026-11-16')).single,
        contains('Ferris Wheel'),
      );
    },
  );

  test('photography fills up to three posts while the counter needs one', () {
    const photographer = StaffRole.photographer;
    const counter = StaffRole.photoCounterStaff;
    final ids = ['A', 'B', 'C', 'D', 'E'];
    final result = arrangeStaffWeek(
      monday: monday,
      roles: {photographer, counter},
      directory: [
        for (final uid in ids) staff(uid, {photographer, counter}),
      ],
      availability: {
        for (final uid in ids) uid: {'2026-11-16'},
      },
      leaves: [],
      qualifications: [
        for (final uid in ids) ...[
          qualification(uid, photographer),
          qualification(uid, counter),
        ],
      ],
      attractions: {},
    );
    expect(
      result.assignments.where((shift) => shift.roleCode == photographer.code),
      hasLength(3),
    );
    expect(
      result.assignments.where((shift) => shift.roleCode == counter.code),
      hasLength(1),
    );
    expect(
      result.assignments.map((shift) => shift.staffUid).toSet(),
      hasLength(4),
    );
  });
}
