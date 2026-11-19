import 'package:flutter_test/flutter_test.dart';
import '../lib/admin/visitor_refund_review.dart';

void main() {
  final now = DateTime.utc(2026, 11, 18, 8);
  Map<String, dynamic> order(String id, String status, {
    bool demo = false,
    bool confirmed = true,
    int daysAgo = 2,
  }) => {
    'id': id,
    'ownerUid': 'visitor_a',
    'createdAt': now.subtract(Duration(days: daysAgo)),
    'status': status,
    'isDemo': demo,
    if (confirmed) 'refundConfirmedAt': now.subtract(Duration(days: daysAgo)),
  };

  test('three genuine refunds out of four orders flags for review', () {
    final rows = [
      order('a', 'refunded'), order('b', 'refunded'),
      order('c', 'refunded'), order('d', 'completed'),
    ];
    final found = detectRefundReviewSignals(rows, now);
    expect(found, hasLength(1));
    expect(found.single.confirmedRefunds, 3);
    expect(found.single.orders, 4);
  });

  test('unconfirmed refund requests and synthetic orders do not count', () {
    final rows = [
      order('a', 'refund_requested'),
      order('b', 'refunded', confirmed: false),
      order('c', 'refunded', demo: true),
      order('d', 'refunded', daysAgo: 40),
    ];
    expect(detectRefundReviewSignals(rows, now), isEmpty);
  });

  test('duplicate order ids cannot increase refund count', () {
    final same = order('a', 'refunded');
    expect(detectRefundReviewSignals([same, same, same], now), isEmpty);
  });

  test('refund rate below threshold does not flag', () {
    final rows = [
      ...['a','b','c'].map((id) => order(id,'refunded')),
      ...['d','e','f'].map((id) => order(id,'completed')),
    ];
    expect(detectRefundReviewSignals(rows, now), isEmpty);
  });
}
