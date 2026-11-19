import 'package:flutter_test/flutter_test.dart';
import 'package:collaborative_asg/admin/staff/staff_training_date_policy.dart';

void main() {
  final completion = DateTime(2026, 11, 17);
  final today = DateTime(2026, 11, 17);

  test('no-expiry course is allowed when review is optional', () {
    expect(StaffTrainingDatePolicy.validate(
      completedAt: completion, expiresOn: null,
      requiresExpiry: false, today: today,
    ), isNull);
  });

  test('ride course requires a review date', () {
    expect(StaffTrainingDatePolicy.validate(
      completedAt: completion, expiresOn: null,
      requiresExpiry: true, today: today,
    ), contains('Choose a review date'));
  });

  test('expiry before completion is rejected', () {
    expect(StaffTrainingDatePolicy.validate(
      completedAt: completion, expiresOn: DateTime(2026, 11, 16),
      requiresExpiry: false, today: today,
    ), contains('must be after'));
  });

  test('expiry equal to completion is rejected even later that day', () {
    expect(StaffTrainingDatePolicy.validate(
      completedAt: completion, expiresOn: DateTime(2026, 11, 17, 23, 59),
      requiresExpiry: true, today: today,
    ), contains('must be after'));
  });

  test('expiry after completion is accepted', () {
    expect(StaffTrainingDatePolicy.validate(
      completedAt: completion, expiresOn: DateTime(2027, 11, 9),
      requiresExpiry: true, today: today,
    ), isNull);
  });

  test('future completion is rejected', () {
    expect(StaffTrainingDatePolicy.validate(
      completedAt: DateTime(2026, 11, 18),
      expiresOn: DateTime(2026, 12, 1), requiresExpiry: true, today: today,
    ), contains('cannot be in the future'));
  });

  test('minimum review date is next calendar day', () {
    expect(StaffTrainingDatePolicy.nextValidDate(completion),
      DateTime(2026, 11, 18));
  });
}
