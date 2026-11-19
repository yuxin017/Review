import 'package:cloud_firestore/cloud_firestore.dart';

/// Monday-based week keys, local park calendar dates (Malaysia).
class StaffWeek {
  StaffWeek._();
  static DateTime start(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }
  static DateTime day(DateTime monday, int offset) =>
      DateTime(monday.year, monday.month, monday.day + offset);
  static DateTime parkCalendar(DateTime instant) =>
      instant.toUtc().add(const Duration(hours: 8));

  static DateTime parkTime(DateTime date, int hour) =>
      DateTime.utc(date.year, date.month, date.day, hour - 8);

  static String key(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  static String id(String uid, DateTime weekStart) => '${uid}_${key(weekStart)}';
  static DateTime? fromTimestamp(Object? value) =>
      value is Timestamp ? value.toDate() : value is DateTime ? value : null;
}

class StaffShiftPlan {
  const StaffShiftPlan({
    required this.date,
    required this.staffUid,
    required this.staffName,
    required this.roleCode,
    this.attractionId,
  });
  final DateTime date;
  final String staffUid, staffName, roleCode;
  final String? attractionId;

  String get docId => '${StaffWeek.key(date)}_$roleCode';
  Map<String, dynamic> toFirestore(String weekKey, {bool published = false}) {
    final starts = StaffWeek.parkTime(date, 9);
    final ends = StaffWeek.parkTime(date, 17);
    return {
      'weekStart': weekKey,
      'staffUid': staffUid,
      'staffName': staffName,
      'roleCode': roleCode,
      'startsAt': Timestamp.fromDate(starts.toUtc()),
      'endsAt': Timestamp.fromDate(ends.toUtc()),
      'attractionIds': attractionId == null ? <String>[] : <String>[attractionId!],
      'published': published,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

bool staffLeaveIncludes(Map<String, dynamic> leave, String day) =>
    leave['status'] == 'approved' &&
    leave['startOn'] is String && leave['endOn'] is String &&
    (leave['startOn'] as String).compareTo(day) <= 0 &&
    (leave['endOn'] as String).compareTo(day) >= 0;

const staffMinimumAvailability = 5;

Set<String> staffLeaveDays(DateTime monday, Iterable<Map<String, dynamic>> leave) => {
  for (var offset = 0; offset < 7; offset++)
    if (leave.any((record) => staffLeaveIncludes(
      record, StaffWeek.key(StaffWeek.day(monday, offset)),
    )))
      StaffWeek.key(StaffWeek.day(monday, offset)),
};

int staffAvailabilityMinimum(Set<String> leaveDays) =>
    (7 - leaveDays.length).clamp(0, staffMinimumAvailability).toInt();
