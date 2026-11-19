import 'package:collaborative_asg/admin/staff/staff_access.dart';
import 'package:collaborative_asg/admin/staff/staff_portal_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the menu changes with the assigned shift, not eligible roles', () {
    final admission = StaffPortalNavigation.onDuty(StaffRole.admissionStaff);
    final operator = StaffPortalNavigation.onDuty(StaffRole.attractionOperator);
    final offDuty = StaffPortalNavigation.onDuty(null);

    expect(admission.allows('validation'), isTrue);
    expect(admission.allows('ride-entry'), isFalse);
    expect(operator.allows('validation'), isFalse);
    expect(operator.allows('ride-entry'), isTrue);
    expect(offDuty.allows('validation'), isFalse);
    expect(offDuty.allows('ride-entry'), isFalse);
    expect(offDuty.allows('staff-my-work'), isTrue);
  });
}
