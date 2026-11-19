import 'package:flutter_test/flutter_test.dart';
import '../lib/admin/admin_models.dart';
import '../lib/admin/visitor_account_report.dart';

void main() {
  test('reports registrations and activity without sales', () {
    final now = DateTime.utc(2026, 11, 18, 4);
    final visitors = [
      AdminVisitor('a', {'fullName': 'A',
        'createdAt': DateTime.utc(2026, 11, 2)}),
      AdminVisitor('b', {'fullName': 'B',
        'createdAt': DateTime.utc(2026, 8, 2)}),
    ];
    final sessions = [
      AdminActivity('a_1', {'ownerUid': 'a',
        'lastSeenAt': DateTime.utc(2026, 11, 15)}),
      AdminActivity('a_2', {'ownerUid': 'a',
        'lastSeenAt': DateTime.utc(2026, 11, 16)}),
    ];
    final report = VisitorAccountReport.calculate(visitors, sessions, now);
    expect(report.registered, 2);
    expect(report.joinedThisMonth, 1);
    expect(report.active30Days, 1);
    expect(report.repeatActivity, 1);
    expect(report.months.last.joined, 1);
    expect(report.months.last.active, 1);
  });
}
