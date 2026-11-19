import 'staff_access.dart';

/// Pure validation, shared by the training UI and batch writer.
/// Revalidation also happens at the Firestore Rules boundary.
abstract final class StaffTrainingBatchPolicy {
  static String? validate({
    required StaffRole role,
    required String? attractionId,
    required DateTime? expiresAt,
    required DateTime completedAt,
  }) {
    if (role == StaffRole.superAdmin) return 'Select a valid course.';
    if (role == StaffRole.attractionOperator &&
        (attractionId == null || attractionId.isEmpty)) {
      return 'Select a ride for each ride course.';
    }
    if (role == StaffRole.attractionOperator && expiresAt == null) {
      return 'Set a review date for each ride course.';
    }
    if (expiresAt != null && !expiresAt.isAfter(completedAt)) {
      return 'Expiry must be after completion.';
    }
    return null;
  }
}
