import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collaborative_asg/admin/admin_models.dart';
import 'package:collaborative_asg/admin/visitor_insights.dart';
import 'package:collaborative_asg/visitor/models/tickets.dart';

void main() {
  TicketOrder order(String id, String owner, DateTime at, String status, int total) =>
      TicketOrder(
        id: id,
        ownerUid: owner,
        status: status,
        packageName: 'Day Pass',
        visitDate: '2026-11-21',
        requestId: id,
        quantity: 1,
        totalMinor: total,
        createdAt: at,
      );

  test('completed orders only, correct same-period comparison', () {
    final visitors = [
      AdminVisitor('alice', {
        'fullName': 'Alice',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 4)),
      }),
      AdminVisitor('bob', {
        'fullName': 'Bob',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 10, 5)),
      }),
    ];
    final insights = VisitorInsights.calculate(visitors, [
      order('old', 'bob', DateTime.utc(2026, 10, 8), 'completed', 10000),
      order('a', 'alice', DateTime.utc(2026, 11, 5), 'completed', 15000),
      order('b', 'bob', DateTime.utc(2026, 11, 6), 'completed', 20000),
      order('pending', 'alice', DateTime.utc(2026, 11, 7), 'pending', 999999),
    ], DateTime(2026, 11, 18));
    expect(insights.salesMinor, 35000);
    expect(insights.priorSalesMinor, 10000);
    expect(insights.buyers, 2);
    expect(insights.returningBuyers, 1);
    expect(insights.newSignups, 1);
    expect(insights.convertedSignups, 1);
  });
}
