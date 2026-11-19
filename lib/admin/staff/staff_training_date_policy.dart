/// Date-only validation for staff training records.
///
/// The admin selects calendar dates, not timestamps. An expiry must therefore
/// be a LATER calendar day than the completion day, even when its stored
/// timestamp is at 23:59:59 on the chosen expiry date.
abstract final class StaffTrainingDatePolicy {
  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime nextValidDate(DateTime completedAt) =>
      DateTime(completedAt.year, completedAt.month, completedAt.day + 1);

  static String? validate({
    required DateTime completedAt,
    required DateTime? expiresOn,
    required bool requiresExpiry,
    DateTime? today,
  }) {
    final completedDay = dateOnly(completedAt);
    final currentDay = dateOnly(today ?? DateTime.now());
    if (completedDay.isAfter(currentDay)) {
      return 'Completion date cannot be in the future.';
    }
    if (requiresExpiry && expiresOn == null) {
      return 'Choose a review date for this ride training.';
    }
    if (expiresOn != null && !dateOnly(expiresOn).isAfter(completedDay)) {
      return 'Expiry / review date must be after the completion date.';
    }
    return null;
  }
}
