import 'package:flutter_test/flutter_test.dart';
import '../../lib/admin/staff/staff_access.dart';
import '../../lib/admin/staff/staff_training_batch_policy.dart';

void main() {
  final completed = DateTime(2026, 11, 1);
  final expires = DateTime(2027, 11, 1);

  test('ride training needs an exact ride', () {
    expect(StaffTrainingBatchPolicy.validate(
      role: StaffRole.attractionOperator,
      attractionId: null,
      completedAt: completed,
      expiresAt: expires,
    ), 'Select a ride for each ride course.');
  });

  test('ride training requires a scheduled review date', () {
    expect(StaffTrainingBatchPolicy.validate(
      role: StaffRole.attractionOperator,
      attractionId: 'ferris-wheel',
      completedAt: completed,
      expiresAt: null,
    ), 'Set a review date for each ride course.');
  });

  test('expiry must follow completion', () {
    expect(StaffTrainingBatchPolicy.validate(
      role: StaffRole.attractionOperator,
      attractionId: 'ferris-wheel',
      completedAt: completed,
      expiresAt: completed,
    ), 'Expiry must be after completion.');
  });

  test('ride with matching ride and review date passes', () {
    expect(StaffTrainingBatchPolicy.validate(
      role: StaffRole.attractionOperator,
      attractionId: 'ferris-wheel',
      completedAt: completed,
      expiresAt: expires,
    ), isNull);
  });

  test('non-ride system course can have no fixed expiry', () {
    expect(StaffTrainingBatchPolicy.validate(
      role: StaffRole.photographer,
      attractionId: null,
      completedAt: completed,
      expiresAt: null,
    ), isNull);
  });

  test('super admin cannot be a training qualification', () {
    expect(StaffTrainingBatchPolicy.validate(
      role: StaffRole.superAdmin,
      attractionId: null,
      completedAt: completed,
      expiresAt: expires,
    ), 'Select a valid course.');
  });
}
