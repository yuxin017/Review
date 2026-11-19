import 'package:flutter_test/flutter_test.dart';
import '../../lib/admin/staff/staff_schedule_utils.dart';

void main() {
  test('week starts on Monday regardless of selected day', () {
    expect(StaffWeek.key(StaffWeek.start(DateTime(2026, 11, 18))), '2026-11-16');
    expect(StaffWeek.key(StaffWeek.day(DateTime(2026, 11, 16), 6)), '2026-11-22');
  });
  test('approved leave blocks a shift on its covered dates', () {
    final leave = {'status': 'approved', 'startOn': '2026-11-17', 'endOn': '2026-11-19'};
    expect(staffLeaveIncludes(leave, '2026-11-16'), isFalse);
    expect(staffLeaveIncludes(leave, '2026-11-18'), isTrue);
    expect(staffLeaveIncludes({...leave, 'status':'pending'}, '2026-11-18'), isFalse);
  });

  test('minimum availability allows for a week with more than two approved leave days', () {
    final days = staffLeaveDays(DateTime(2026, 11, 16), [
      {'status': 'approved', 'startOn': '2026-11-16', 'endOn': '2026-11-19'},
    ]);
    expect(staffAvailabilityMinimum({}), 5);
    expect(staffAvailabilityMinimum(days), 3);
  });

}
