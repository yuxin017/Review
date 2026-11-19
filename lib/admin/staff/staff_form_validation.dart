/// Reused by Staff Management UI and Spark onboarding so invalid input is
/// rejected before any Firebase Auth account is provisioned.
/// This is input validation, NOT an authorization or mailbox existence check.
abstract final class StaffFormValidation {
  static String? fullName(String? raw) {
    final input = raw ?? '';
    if (RegExp(r'[\x00-\x1F\x7F<>@#$%^&*_+=\[\]{}|\\/!?;:~`"\\]').hasMatch(input)) {
      return 'Enter a valid name.';
    }
    final name = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) return 'Enter a full name.';
    if (name.length < 2) return 'Name is too short.';
    if (name.length > 120) return 'Name is too long.';
    // ASCII, Latin accented, Japanese and CJK names are supported; punctuation
    // and digits may occur in names, but a name cannot be ONLY numbers.
    if (!RegExp(r'[A-Za-z\u00C0-\u024F\u3040-\u30FF\u3400-\u9FFF]').hasMatch(name)) {
      return 'Enter a valid name.';
    }
    return null;
  }

  static String? email(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return 'Enter an email address.';
    if (value.length > 254) return 'Email is too long.';
    final basic = RegExp(
      r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?)+$',
    );
    if (!basic.hasMatch(value) || value.contains('..') || value.startsWith('.')) {
      return 'Enter a valid email address.';
    }
    return null;
  }
}
