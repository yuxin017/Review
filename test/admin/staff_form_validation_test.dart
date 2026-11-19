import 'package:flutter_test/flutter_test.dart';
import 'package:collaborative_asg/admin/staff/staff_form_validation.dart';

void main() {
  test('full name rejects blank and numeric-only entries', () {
    expect(StaffFormValidation.fullName(''), isNotNull);
    expect(StaffFormValidation.fullName('123'), isNotNull);
    expect(StaffFormValidation.fullName('1'), isNotNull);
    expect(StaffFormValidation.fullName('<script>'), isNotNull);
    expect(StaffFormValidation.fullName('John\nTan'), isNotNull);
  });

  test('full name supports Malaysian, Chinese and spaced names', () {
    expect(StaffFormValidation.fullName('Loo Chee Beng'), isNull);
    expect(StaffFormValidation.fullName('李小明'), isNull);
    expect(StaffFormValidation.fullName("Nur Aisyah"), isNull);
    expect(StaffFormValidation.fullName('Jean-Pierre Tan'), isNull);
  });

  test('email rejects placeholders and malformed addresses', () {
    for (final value in ['11', '', 'hello', '@gmail.com', 'a@',
      'a@gmail', 'a@@gmail.com', 'a b@gmail.com', 'a..b@gmail.com']) {
      expect(StaffFormValidation.email(value), isNotNull, reason: value);
    }
  });

  test('email accepts common real inbox formats', () {
    expect(StaffFormValidation.email('lcb7202@gmail.com'), isNull);
    expect(StaffFormValidation.email('member+staff@example.com'), isNull);
    expect(StaffFormValidation.email('  team@example.com  '), isNull);
  });
}
