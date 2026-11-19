import 'package:flutter_test/flutter_test.dart';
import 'package:collaborative_asg/admin/staff/staff_access.dart';

void main() {
  final monday = DateTime.utc(2026, 11, 23, 10);
  final tuesday = DateTime.utc(2026, 11, 24, 10);

  StaffShift shift(
    String id,
    StaffRole role,
    DateTime day, {
    bool published = true,
    Set<String> attractionIds = const {},
  }) => StaffShift(
    id: id,
    role: role,
    startsAt: DateTime.utc(day.year, day.month, day.day, 9),
    endsAt: DateTime.utc(day.year, day.month, day.day, 18),
    published: published,
    attractionIds: attractionIds,
  );

  test('photographer can upload, but cannot scan admission tickets', () {
    final access = StaffAccess(
      accountActive: true,
      eligibleRoles: {StaffRole.photographer},
      shifts: [shift('p1', StaffRole.photographer, monday)],
    );
    expect(access.can(StaffPermission.uploadPhotos, at: monday), isTrue);
    expect(access.can(StaffPermission.validateAdmission, at: monday), isFalse);
  });

  test('same employee receives different permissions on different shifts', () {
    final access = StaffAccess(
      accountActive: true,
      eligibleRoles: {StaffRole.attractionOperator, StaffRole.admissionStaff},
      qualifiedAttractionIds: {'ferris-wheel'},
      shifts: [
        shift('m', StaffRole.attractionOperator, monday,
            attractionIds: {'ferris-wheel'}),
        shift('t', StaffRole.admissionStaff, tuesday),
      ],
    );
    expect(
      access.can(StaffPermission.operateAssignedAttraction,
          attractionId: 'ferris-wheel', at: monday),
      isTrue,
    );
    expect(access.can(StaffPermission.validateAdmission, at: monday), isFalse);
    expect(access.can(StaffPermission.validateAdmission, at: tuesday), isTrue);
    expect(
      access.can(StaffPermission.operateAssignedAttraction,
          attractionId: 'ferris-wheel', at: tuesday),
      isFalse,
    );
  });

  test('ride operator cannot manage an unassigned or unqualified attraction', () {
    final access = StaffAccess(
      accountActive: true,
      eligibleRoles: {StaffRole.attractionOperator},
      qualifiedAttractionIds: {'ferris-wheel'},
      shifts: [
        shift('m', StaffRole.attractionOperator, monday,
            attractionIds: {'ferris-wheel', 'carousel'}),
      ],
    );
    expect(
      access.can(StaffPermission.operateAssignedAttraction,
          attractionId: 'carousel', at: monday),
      isFalse,
    );
  });

  test('draft shifts and off-duty staff have no work permissions', () {
    final access = StaffAccess(
      accountActive: true,
      eligibleRoles: {StaffRole.admissionStaff},
      shifts: [shift('draft', StaffRole.admissionStaff, monday,
          published: false)],
    );
    expect(access.can(StaffPermission.validateAdmission, at: monday), isFalse);
    expect(access.can(StaffPermission.validateAdmission, at: tuesday), isFalse);
  });

  test('inactive account is denied regardless of shifts', () {
    final access = StaffAccess(
      accountActive: false,
      eligibleRoles: {StaffRole.photographer},
      shifts: [shift('p1', StaffRole.photographer, monday)],
    );
    expect(access.can(StaffPermission.uploadPhotos, at: monday), isFalse);
  });

  test('verified super admin can manage staff but not bypass ride training', () {
    const access = StaffAccess(
      accountActive: true,
      verifiedSuperAdmin: true,
      eligibleRoles: {},
      shifts: [],
    );
    expect(access.can(StaffPermission.manageStaff, at: monday), isTrue);
    expect(
      access.can(StaffPermission.operateAssignedAttraction,
          attractionId: 'ferris-wheel', at: monday),
      isFalse,
    );
  });
}
