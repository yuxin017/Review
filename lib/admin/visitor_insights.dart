import '../visitor/models/tickets.dart';
import 'admin_models.dart';

/// Counts only orders recorded as completed, not pending Stripe checkouts.
/// These are recorded sales; payment settlement must be reconciled separately.
class VisitorInsights {
  final int salesMinor, priorSalesMinor;
  final int buyers, priorBuyers;
  final int returningBuyers, priorReturningBuyers;
  final int newSignups, priorNewSignups;
  final int convertedSignups, priorConvertedSignups;

  const VisitorInsights({
    required this.salesMinor,
    required this.priorSalesMinor,
    required this.buyers,
    required this.priorBuyers,
    required this.returningBuyers,
    required this.priorReturningBuyers,
    required this.newSignups,
    required this.priorNewSignups,
    required this.convertedSignups,
    required this.priorConvertedSignups,
  });

  static DateTime _parkDate(DateTime timestamp) {
    final local = timestamp.toUtc().add(const Duration(hours: 8));
    return DateTime(local.year, local.month, local.day);
  }

  static VisitorInsights calculate(
    List<AdminVisitor> visitors,
    List<TicketOrder> orders,
    DateTime today,
  ) {
    final start = DateTime(today.year, today.month, 1);
    final priorStart = DateTime(today.year, today.month - 1, 1);
    final lastPriorDay = DateTime(today.year, today.month, 0).day;
    final priorThrough = DateTime(
      priorStart.year,
      priorStart.month,
      today.day < lastPriorDay ? today.day : lastPriorDay,
    );
    bool current(DateTime? d) {
      if (d == null) return false;
      final day = _parkDate(d);
      return !day.isBefore(start) && !day.isAfter(today);
    }
    bool prior(DateTime? d) {
      if (d == null) return false;
      final day = _parkDate(d);
      return !day.isBefore(priorStart) && !day.isAfter(priorThrough);
    }
    final completed = orders.where((o) => o.status == 'completed').toList();
    final currentOrders = completed.where((o) => current(o.createdAt)).toList();
    final priorOrders = completed.where((o) => prior(o.createdAt)).toList();
    Set<String> buyerIds(List<TicketOrder> items) => items
        .where((o) => o.ownerUid.isNotEmpty)
        .map((o) => o.ownerUid)
        .toSet();
    final buyersNow = buyerIds(currentOrders);
    final buyersPrior = buyerIds(priorOrders);
    bool hadEarlierOrder(String uid, DateTime startOfPeriod) => completed.any(
      (o) => o.ownerUid == uid &&
          o.createdAt != null &&
          _parkDate(o.createdAt!).isBefore(startOfPeriod),
    );
    final nowSignups = visitors.where((v) => current(v.joined)).map((v) => v.id).toSet();
    final oldSignups = visitors.where((v) => prior(v.joined)).map((v) => v.id).toSet();
    return VisitorInsights(
      salesMinor: currentOrders.fold<int>(0, (sum, o) => sum + o.totalMinor),
      priorSalesMinor: priorOrders.fold<int>(0, (sum, o) => sum + o.totalMinor),
      buyers: buyersNow.length,
      priorBuyers: buyersPrior.length,
      returningBuyers: buyersNow.where((id) => hadEarlierOrder(id, start)).length,
      priorReturningBuyers: buyersPrior.where((id) => hadEarlierOrder(id, priorStart)).length,
      newSignups: nowSignups.length,
      priorNewSignups: oldSignups.length,
      convertedSignups: nowSignups.intersection(buyersNow).length,
      priorConvertedSignups: oldSignups.intersection(buyersPrior).length,
    );
  }

  double get returningRate => buyers == 0 ? 0 : returningBuyers * 100 / buyers;
  double get priorReturningRate => priorBuyers == 0 ? 0 : priorReturningBuyers * 100 / priorBuyers;
  double get newConversionRate => newSignups == 0 ? 0 : convertedSignups * 100 / newSignups;
  double get priorConversionRate => priorNewSignups == 0 ? 0 : priorConvertedSignups * 100 / priorNewSignups;

  static String changeLabel(num current, num previous, {bool percentagePoints = false}) {
    if (previous == 0 && !percentagePoints) return 'No prior baseline';
    final diff = percentagePoints ? current - previous : (current - previous) * 100 / previous;
    final prefix = diff > 0 ? '+' : '';
    return '$prefix${diff.toStringAsFixed(1)}${percentagePoints ? ' pp' : '%'} vs prior MTD';
  }
}
