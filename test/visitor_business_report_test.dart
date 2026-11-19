import 'package:flutter_test/flutter_test.dart';
import 'package:collaborative_asg/admin/visitor_business_report.dart';
import 'package:collaborative_asg/visitor/models/tickets.dart';

TicketOrder sample(String id, String uid, int amount, DateTime date, String pkg) => TicketOrder(
  id: id,
  packageName: pkg,
  visitDate: '2026-11-18',
  requestId: id,
  quantity: 1,
  totalMinor: amount,
  createdAt: date,
  ownerUid: uid,
  status: 'completed',
);

void main() {
  test('six-month sales report uses completed orders and counts return buyers', () {
    final orders = [
      sample('old', 'visitorA', 10000, DateTime.utc(2026, 5, 20), 'Day Pass'),
      sample('a', 'visitorA', 15000, DateTime.utc(2026, 6, 15), 'Day Pass'),
      sample('b', 'visitorB', 12000, DateTime.utc(2026, 6, 16), 'Family Pass'),
      sample('c', 'visitorA', 20000, DateTime.utc(2026, 11, 5), 'Day Pass'),
      TicketOrder(id: 'pending', requestId: 'pending', packageName: 'Day Pass',
        visitDate: '2026-11-18', quantity: 1, totalMinor: 999999,
        ownerUid: 'visitorC', status: 'pending', createdAt: DateTime.utc(2026, 11, 10)),
    ];
    final report = VisitorSalesReport.fromOrders(orders, DateTime(2026, 11, 18));
    expect(report.monthly.length, 6);
    expect(report.monthly.first.label, 'Jun 2026');
    expect(report.monthly.last.label, 'Nov 2026');
    expect(report.monthly.first.orderCount, 2);
    expect(report.monthly.first.revenueMinor, 27000);
    expect(report.monthly.first.returningBuyers, 1);
    expect(report.monthly.last.revenueMinor, 20000);
    expect(report.completedOrderCount, 3);
    expect(report.completedOrderValueMinor, 47000);
    expect(report.topPackages.first.key, 'Day Pass');
  });
}
