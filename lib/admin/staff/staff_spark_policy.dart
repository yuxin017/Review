import 'staff_access.dart';
import 'staff_form_validation.dart';

/// Input and ID formatting checks for the Spark-plan employee demo.
/// These are client-side checks, not authorization. Firestore Rules remain
/// responsible for protecting the staff identity and qualification records.
class StaffSparkPolicy {
  const StaffSparkPolicy._();

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  static String staffIdFromNumber(int value) {
    if (value < 10000000 || value > 99999999) {
      throw ArgumentError('Staff ID number must contain eight digits.');
    }
    return 'STF-$value';
  }

  static void validate({
    required String fullName,
    required String email,
    required Set<StaffRole> eligibleRoles,
  }) {
    final nameError = StaffFormValidation.fullName(fullName);
    if (nameError != null) throw ArgumentError(nameError);
    final emailError = StaffFormValidation.email(email);
    if (emailError != null) throw ArgumentError(emailError);
    if (eligibleRoles.isEmpty ||
        eligibleRoles.length > 7 ||
        eligibleRoles.contains(StaffRole.superAdmin)) {
      throw ArgumentError('Select 1–7 regular employee roles, not Super Admin.');
    }
  }
}
