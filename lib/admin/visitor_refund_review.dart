import 'package:cloud_firestore/cloud_firestore.dart';
import '../visitor/services/ticket_journey.dart';
import 'admin_models.dart';
import 'admin_repository.dart';

/// A review signal, not a fraud verdict. A confirmed refund must be recorded
/// by trusted administrative/payment software, never by the visitor client.
class RefundReviewSignal {
  final String ownerUid;
  final int orders, confirmedRefunds;
  const RefundReviewSignal(this.ownerUid, this.orders, this.confirmedRefunds);
  double get refundShare => orders == 0 ? 0 : confirmedRefunds / orders;
  String get explanation =>
      '$confirmedRefunds confirmed refunds from $orders orders in the last 30 days '
      '(${(refundShare * 100).round()}%). Review the refund reasons before deciding whether to suspend.';
}

/// Pure detector, independently testable. Only server-confirmed refunds count.
/// Supported order fields: ownerUid, createdAt, status, refundStatus,
/// refundConfirmedAt/refundedAt, isDemo. A request alone never counts.
List<RefundReviewSignal> detectRefundReviewSignals(
  List<Map<String, dynamic>> orders,
  DateTime now, {
  int minRefunds = 3,
  double minShare = 0.60,
}) {
  final cutoff = now.subtract(const Duration(days: 30));
  final byOwner = <String, Map<String, bool>>{};
  for (final row in orders) {
    if (row['isDemo'] == true) continue;
    final uid = row['ownerUid'];
    final orderId = row['orderId'] ?? row['requestId'] ?? row['id'];
    if (uid is! String || uid.isEmpty || orderId is! String || orderId.isEmpty) {
      continue;
    }
    final created = adminDate(row['createdAt']);
    if (created == null || created.isBefore(cutoff) || created.isAfter(now)) {
      continue;
    }
    final refundDate = adminDate(row['refundConfirmedAt'] ?? row['refundedAt']);
    final confirmedStatus = row['status'] == 'refunded' ||
        row['refundStatus'] == 'succeeded' || row['refundStatus'] == 'refunded';
    final confirmed = confirmedStatus && refundDate != null &&
        !refundDate.isBefore(cutoff) && !refundDate.isAfter(now);
    final map = byOwner.putIfAbsent(uid, () => <String, bool>{});
    // Repeated records of the same order must not inflate the refund count.
    map[orderId] = (map[orderId] ?? false) || confirmed;
  }
  final signals = <RefundReviewSignal>[];
  for (final entry in byOwner.entries) {
    final total = entry.value.length;
    final refunded = entry.value.values.where((v) => v).length;
    if (refunded >= minRefunds && refunded / total >= minShare) {
      signals.add(RefundReviewSignal(entry.key, total, refunded));
    }
  }
  signals.sort((a, b) => b.refundShare.compareTo(a.refundShare));
  return signals;
}

/// No Cloud Functions or Blaze needed. Scans when Super Admin opens the visitor
/// screen and while it stays open. It is NOT an always-on server-side trigger.
class VisitorRefundReviewService {
  final FirebaseAdminRepository repository;
  VisitorRefundReviewService(this.repository);

  Future<int> scanAndFlag() async {
    final db = repository.firebase.db;
    final actorUid = repository.firebase.auth.currentUser?.uid;
    if (actorUid == null) return 0;
    final now = DateTime.now();
    final cutoff = Timestamp.fromDate(now.subtract(const Duration(days: 30)));
    final orders = await db.collection('orders')
        .where('createdAt', isGreaterThanOrEqualTo: cutoff)
        .orderBy('createdAt', descending: true).limit(2000).get();
    final items = [
      for (final doc in orders.docs) <String, dynamic>{...doc.data(), 'id': doc.id},
    ];
    final signals = detectRefundReviewSignals(items, now);
    var changed = 0;
    for (final signal in signals.take(50)) {
      if (signal.ownerUid == actorUid) continue;
      final visitor = await db.collection('visitors').doc(signal.ownerUid).get();
      if (!visitor.exists) continue;
      final ref = db.collection('visitorAdmin').doc(signal.ownerUid);
      // Transaction makes the update idempotent and preserves manual notes.
      final flagged = await db.runTransaction<bool>((tx) async {
        final snapshot = await tx.get(ref);
        final old = snapshot.data() ?? <String, dynamic>{};
        if (old['watchlisted'] == true) return false;
        final previousNote = (old['notes'] as String? ?? '').trim();
        // If an admin previously cleared this exact flag, respect that review.
        final evidence = '${signal.confirmedRefunds} confirmed refunds from ${signal.orders} orders';
        if (previousNote.contains('Automatic refund review: $evidence')) {
          return false;
        }
        final explanation = 'Automatic refund review: ${signal.explanation}';
        final remaining = 1999 - explanation.length;
        final safeNote = previousNote.length > remaining
            ? previousNote.substring(0, remaining) : previousNote;
        final combined = safeNote.isEmpty ? explanation :
            '$safeNote\n$explanation';
        final membership = old['membership'] as String? ?? 'normal';
        tx.set(ref, {
          'membership': membership,
          'riskLevel': 'review',
          'watchlisted': true,
          'notes': combined,
          'updatedBy': actorUid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(db.collection('adminAudit').doc(TicketJourney.newId()), {
          'action': 'watchlist_added',
          'targetIds': [signal.ownerUid],
          'actorUid': actorUid,
          'details': {
            'source': 'confirmed_refund_pattern',
            'confirmedRefunds': signal.confirmedRefunds,
            'orders': signal.orders,
            'reviewRequired': true,
          },
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (flagged) changed++;
    }
    return changed;
  }
}
