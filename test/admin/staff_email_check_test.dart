import 'package:flutter_test/flutter_test.dart';
import '../../lib/admin/staff/staff_email_check.dart';

void main() {
  test('existing employee email is detected case-insensitively', () {
    expect(
      StaffEmailCheck.findDuplicate(
        ' LCB7202@GMAIL.COM ', ['lcb7202@gmail.com', 'someone@example.com'],
      ),
      isNotNull,
    );
  });

  test('a new email passes local employee-directory precheck', () {
    expect(
      StaffEmailCheck.findDuplicate('new@example.com', ['old@example.com']),
      isNull,
    );
  });

  test('blank email is not reported as a duplicate', () {
    expect(StaffEmailCheck.findDuplicate('', ['old@example.com']), isNull);
  });
}
