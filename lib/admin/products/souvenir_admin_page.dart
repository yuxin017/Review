import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../commerce/stripe_commerce_client.dart'; // PARKSMART_V15_PAYMENT_CROWD
import '../admin_models.dart';
import '../admin_widgets.dart';

// SOUVENIR_ADMIN_V11: all payment information is READ from verified server orders.
// Only the one-way collection operation is authorized for admin clients.
// Never create paid orders from Flutter or infer paid status from URL parameters.

int _amount(dynamic input) => input is num ? input.toInt() : 0;
String souvenirMoney(int minor) => 'RM ${(minor / 100).toStringAsFixed(2)}';
String souvenirShortId(String id) => '#${id.substring(0, id.length < 10 ? id.length : 10).toUpperCase()}';

DateTime _malaysiaDayStart(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).subtract(const Duration(hours: 8));
DateTime _malaysiaDayAfter(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day + 1).subtract(const Duration(hours: 8));

Query<Map<String, dynamic>> souvenirPeriodQuery(
    FirebaseFirestore db, DateTime start, DateTime end) =>
  db.collection('souvenirOrders')
    .where('paidAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_malaysiaDayStart(start)))
    .where('paidAt', isLessThan: Timestamp.fromDate(_malaysiaDayAfter(end)))
    .orderBy('paidAt');

class ParkSouvenirOrder {
  final String id;
  final Map<String, dynamic> data;
  ParkSouvenirOrder(this.id, this.data);
  String get ownerUid => (data['ownerUid'] ?? '').toString();
  String get fulfillment => (data['fulfillmentStatus'] ?? 'awaiting_collection').toString();
  bool get isPaid => data['status'] == 'paid' && data['currency'] == 'MYR';
  bool get isRefunded => data['status'] == 'refunded';
  bool get refundInProgress => ['requested','pending'].contains(data['refundStatus']);
  int get amountMinor => _amount(data['totalMinor']);
  DateTime? get paidAt => adminDate(data['paidAt']);
  DateTime? get collectedAt => adminDate(data['collectedAt']);
  List<Map<String, dynamic>> get lines => [
    for (final row in (data['items'] as List? ?? const []))
      if (row is Map) Map<String, dynamic>.from(row),
  ];
}

// One paid souvenir order contributes to revenue only once, independent of
// whether its fulfillment has been collected. Unpaid payments aren't orders.
Map<String, dynamic> calculateSouvenirSales(List<ParkSouvenirOrder> orders) {
  int totalMinor = 0, units = 0, awaiting = 0, collected = 0, count = 0;
  final products = <String, Map<String, dynamic>>{};
  final dates = <String, Map<String, dynamic>>{};
  for (final order in orders) {
    if (!order.isPaid || order.paidAt == null || order.amountMinor < 0) continue;
    count++;
    totalMinor += order.amountMinor;
    if (order.fulfillment == 'collected') { collected++; } else { awaiting++; }
    final dayTime = order.paidAt!.toUtc().add(const Duration(hours: 8));
    final key = '${dayTime.year.toString().padLeft(4, '0')}-'
        '${dayTime.month.toString().padLeft(2, '0')}-'
        '${dayTime.day.toString().padLeft(2, '0')}';
    final day = dates.putIfAbsent(key, () => {'day': key, 'orders': 0, 'revenueMinor': 0});
    day['orders'] = _amount(day['orders']) + 1;
    day['revenueMinor'] = _amount(day['revenueMinor']) + order.amountMinor;
    for (final line in order.lines) {
      final id = (line['productId'] ?? line['name'] ?? 'unknown').toString();
      final qty = _amount(line['quantity']);
      final itemMinor = _amount(line['lineMinor']);
      units += qty;
      final product = products.putIfAbsent(id, () => {
        'name': (line['name'] ?? 'Souvenir').toString(),
        'quantity': 0, 'revenueMinor': 0,
      });
      product['quantity'] = _amount(product['quantity']) + qty;
      product['revenueMinor'] = _amount(product['revenueMinor']) + itemMinor;
    }
  }
  final top = products.values.toList()
    ..sort((a,b) => _amount(b['revenueMinor']).compareTo(_amount(a['revenueMinor'])));
  final daily = dates.values.toList()
    ..sort((a,b) => '${a['day']}'.compareTo('${b['day']}'));
  return {
    'revenueMinor': totalMinor, 'paidOrders': count, 'units': units,
    'awaitingCollection': awaiting, 'collected': collected,
    'topProducts': top.take(10).toList(), 'daily': daily,
  };
}

Future<Map<String, dynamic>> loadSouvenirSales(
    FirebaseFirestore db, DateTime start, DateTime end) async {
  final result = await souvenirPeriodQuery(db, start, end).get();
  return calculateSouvenirSales([
    for (final doc in result.docs) ParkSouvenirOrder(doc.id, doc.data()),
  ]);
}

// PARKSMART_UNIFIED_SALES_V12: sales channels remain distinct in accounting,
// while the overview combines only independently confirmed paid transactions.
// PARKSMART_UNIFIED_SALES_V13: sales channels remain distinct in accounting,
// while the overview combines only independently confirmed paid transactions.
class SouvenirSalesReportPanel extends StatelessWidget {
  final FirebaseFirestore db;
  final DateTime start;
  final DateTime end;
  final int? ticketPhotoRevenueMinor;
  final int? ticketPhotoOrderCount;
  final List<Map> ticketPhotoDaily;

  const SouvenirSalesReportPanel({
    super.key,
    required this.db,
    required this.start,
    required this.end,
    this.ticketPhotoRevenueMinor,
    this.ticketPhotoOrderCount,
    this.ticketPhotoDaily = const <Map>[],
  });

  List<Map<String, dynamic>> _mergeDaily(List<Map<String, dynamic>> souvenirDaily) {
    final rows = <String, Map<String, dynamic>>{};
    void add(Map<dynamic, dynamic> source, bool souvenir) {
      final day = '${source['day'] ?? ''}';
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) return;
      final row = rows.putIfAbsent(day, () => <String, dynamic>{
        'day': day, 'orders': 0, 'revenueMinor': 0,
        'ticketPhotoMinor': 0, 'souvenirMinor': 0,
      });
      final amount = _amount(source['revenueMinor']);
      row['orders'] = _amount(row['orders']) + _amount(source['orders']);
      row['revenueMinor'] = _amount(row['revenueMinor']) + amount;
      final key = souvenir ? 'souvenirMinor' : 'ticketPhotoMinor';
      row[key] = _amount(row[key]) + amount;
    }
    for (final row in ticketPhotoDaily) add(row, false);
    for (final row in souvenirDaily) add(row, true);
    return rows.values.toList()..sort((a, b) =>
        '${a['day']}'.compareTo('${b['day']}'));
  }

  Widget _stat(String label, String value, IconData icon,
      {required double width, String? subtitle}) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF0DFDE)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFBEFF0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: const Color(0xFFAD5965)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(
              fontSize: 12, color: Color(0xFF776F74),
              fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 16),
          Text(value, style: const TextStyle(fontSize: 22,
            fontWeight: FontWeight.w800, color: Color(0xFF302B31))),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(
              fontSize: 11, color: Color(0xFF8E858A))),
          ],
        ]),
      ),
    );
  }

  Widget _pill(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF8EDEF),
      borderRadius: BorderRadius.circular(50),
    ),
    child: Text('$label: $value', style: const TextStyle(
      fontWeight: FontWeight.w600, fontSize: 12,
      color: Color(0xFF8B4D58))),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: souvenirPeriodQuery(db, start, end).snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return AdminCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Souvenir sales could not load', style: TextStyle(
            fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 7),
          Text('Check the administrator claim, published Firestore Rules and '
              'the paidAt index. Ticket + Photo reporting remains separate.\n${snap.error}'),
        ],
      ));
      if (!snap.hasData) return const Padding(
        padding: EdgeInsets.all(22),
        child: Center(child: CircularProgressIndicator()),
      );
      final sales = calculateSouvenirSales([
        for (final doc in snap.data!.docs)
          ParkSouvenirOrder(doc.id, doc.data()),
      ]);
      final souvenirMinor = _amount(sales['revenueMinor']);
      final souvenirOrders = _amount(sales['paidOrders']);
      final ticketMinor = ticketPhotoRevenueMinor;
      final ticketOrders = ticketPhotoOrderCount;
      final combinedMinor = ticketMinor == null ? null : ticketMinor + souvenirMinor;
      final combinedOrders = ticketOrders == null ? null : ticketOrders + souvenirOrders;
      final meanMinor = combinedMinor != null && combinedOrders != null && combinedOrders > 0
        ? (combinedMinor / combinedOrders).round() : 0;
      final share = combinedMinor == null || combinedMinor <= 0
        ? 0.0 : ticketMinor! / combinedMinor;
      final tops = (sales['topProducts'] as List).cast<Map<String, dynamic>>();
      final souvenirDaily = (sales['daily'] as List).cast<Map<String, dynamic>>();
      final mergedDaily = _mergeDaily(souvenirDaily);
      final activeDays = mergedDaily.where((x) => _amount(x['revenueMinor']) > 0).toList();
      final visibleDays = activeDays.length > 14
        ? activeDays.sublist(activeDays.length - 14) : activeDays;
      var maxDayMinor = 1;
      for (final row in visibleDays) {
        if (_amount(row['revenueMinor']) > maxDayMinor) {
          maxDayMinor = _amount(row['revenueMinor']);
        }
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // V13: primary statistics live directly under Reports & Analytics.
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [
              Color(0xFF65444E), Color(0xFFAC6571),
            ], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
          ),
          child: LayoutBuilder(builder: (context, c) => Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.account_balance_wallet_outlined, color: Colors.white70, size: 19),
                SizedBox(width: 9),
                Text('TOTAL CONFIRMED SALES', style: TextStyle(
                  color: Color(0xFFF8E6E9), fontWeight: FontWeight.w700,
                  letterSpacing: 1, fontSize: 12)),
              ]),
              const SizedBox(height: 12),
              Text(combinedMinor == null ? 'Loading channel totals...'
                  : souvenirMoney(combinedMinor),
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800,
                  fontSize: c.maxWidth > 480 ? 38 : 29)),
              const SizedBox(height: 12),
              Text(combinedOrders == null ? 'Waiting for Ticket + Photo report'
                  : '$combinedOrders confirmed orders across all channels',
                style: const TextStyle(color: Color(0xFFFBEDEF), fontSize: 13)),
              const SizedBox(height: 22),
              ClipRRect(borderRadius: BorderRadius.circular(7), child: Row(children: [
                Expanded(flex: combinedMinor == null || combinedMinor == 0
                    ? 1 : (share * 1000).round().clamp(1, 999).toInt(),
                  child: Container(height: 9, color: const Color(0xFFF6DADD))),
                Expanded(flex: combinedMinor == null || combinedMinor == 0
                    ? 1 : (1000 - (share * 1000).round()).clamp(1, 999).toInt(),
                  child: Container(height: 9, color: const Color(0xFFF2ACB4))),
              ])),
              const SizedBox(height: 13),
              Wrap(spacing: 18, runSpacing: 8, children: [
                Text('● Ticket + Photo  ${ticketMinor == null ? '—' : souvenirMoney(ticketMinor)}',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
                Text('● Souvenir  ${souvenirMoney(souvenirMinor)}',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 13),
        LayoutBuilder(builder: (context, c) {
          final columns = c.maxWidth >= 1050 ? 4 : c.maxWidth >= 560 ? 2 : 1;
          final width = (c.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            _stat('Ticket + Photo', ticketMinor == null ? '—' : souvenirMoney(ticketMinor),
              Icons.confirmation_number_outlined, width: width, subtitle: 'Confirmed sales'),
            _stat('Souvenir', souvenirMoney(souvenirMinor),
              Icons.shopping_bag_outlined, width: width, subtitle: '$souvenirOrders paid orders'),
            _stat('All paid orders', combinedOrders == null ? '—' : '$combinedOrders',
              Icons.receipt_long_outlined, width: width, subtitle: 'All channels'),
            _stat('Average order', combinedMinor == null ? '—' : souvenirMoney(meanMinor),
              Icons.trending_up_outlined, width: width, subtitle: 'Confirmed orders only'),
          ]);
        }),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _pill('Souvenir items sold', '${sales['units']}'),
          _pill('Awaiting collection', '${sales['awaitingCollection']}'),
          _pill('Collected', '${sales['collected']}'),
        ]),
        const SizedBox(height: 22),
        AdminCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,children: [
          const Text('Combined Daily Sales', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          const Text('Ticket + Photo + Souvenir · Malaysia dates',
            style: TextStyle(fontSize: 12, color: Color(0xFF82767C))),
          const SizedBox(height: 16),
          if (visibleDays.isEmpty) const Text('No confirmed sales in this period.')
          else ...[
            for (final row in visibleDays) Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: LayoutBuilder(builder: (context, c) {
                final labelWidth = c.maxWidth >= 500 ? 93.0 : 72.0;
                final valueWidth = c.maxWidth >= 500 ? 110.0 : 90.0;
                final barMax = c.maxWidth - labelWidth - valueWidth - 16;
                final barWidth = (barMax > 12 ? barMax : 12) *
                  (_amount(row['revenueMinor']) / maxDayMinor);
                return Row(children: [
                  SizedBox(width: labelWidth, child: Text('${row['day']}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF6C6066)))),
                  Expanded(child: Align(alignment: Alignment.centerLeft,
                    child: Container(width: barWidth, height: 13,
                      decoration: BoxDecoration(color: const Color(0xFFBD7884),
                        borderRadius: BorderRadius.circular(5))))),
                  SizedBox(width: valueWidth, child: Text(
                    souvenirMoney(_amount(row['revenueMinor'])),
                    textAlign: TextAlign.end, style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700))),
                ]);
              }),
            ),
            if (activeDays.length > 14)
              const Padding(padding: EdgeInsets.only(top: 7), child: Text(
                'Chart shows the last 14 active sales days. Cards cover the full selected period.',
                style: TextStyle(fontSize: 11, color: Color(0xFF82767C)))),
          ],
        ])),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          final two = c.maxWidth >= 850;
          final width = two ? (c.maxWidth - 14) / 2 : c.maxWidth;
          Widget dailyTable() => AdminCard(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.calendar_month_outlined, color: Color(0xFFAD5965), size: 21),
                const SizedBox(width: 9),
                const Expanded(child: Text('Souvenir Daily Sales', style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800))),
                Text('${souvenirDaily.length} day(s)', style: const TextStyle(
                  fontSize: 12, color: Color(0xFF8D8186))),
              ]),
              const SizedBox(height: 6),
              const Text('Verified paid orders · Malaysia time', style: TextStyle(
                color: Color(0xFF887E83), fontSize: 12)),
              const SizedBox(height: 13),
              if (souvenirDaily.isEmpty)
                const Padding(padding: EdgeInsets.all(22), child: Text(
                  'No souvenir payments for this period.'))
              else for (final d in souvenirDaily.reversed) Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(color: const Color(0xFFFBF7F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF2E6E4))),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, color: Color(0xFFA46B76), size: 16),
                  const SizedBox(width: 9),
                  Expanded(child: Text('${d['day']}', style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13))),
                  Text('${d['orders']} orders', style: const TextStyle(
                    color: Color(0xFF7B7075), fontSize: 12)),
                  const SizedBox(width: 14),
                  Text(souvenirMoney(_amount(d['revenueMinor'])),
                    style: const TextStyle(fontWeight: FontWeight.w800,
                      color: Color(0xFFA65060), fontSize: 13)),
                ]),
              ),
            ],
          ));
          final highestProduct = tops.isEmpty ? 1 :
              tops.map((p) => _amount(p['revenueMinor']))
                .reduce((a, b) => a > b ? a : b).clamp(1, 1 << 31).toInt();
          Widget productTable() => AdminCard(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: const [
                Icon(Icons.workspace_premium_outlined,
                  color: Color(0xFFAD5965), size: 21),
                SizedBox(width: 9),
                Expanded(child: Text('Best-Selling Souvenirs', style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 6),
              const Text('Ranked by confirmed paid value', style: TextStyle(
                color: Color(0xFF887E83), fontSize: 12)),
              const SizedBox(height: 13),
              if (tops.isEmpty) const Padding(padding: EdgeInsets.all(22),
                child: Text('No souvenir products sold in this period.'))
              else for (var i = 0; i < tops.length; i++) Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFFFBF7F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF2E6E4))),
                child: Row(children: [
                  Container(width: 29, height: 29,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: const Color(0xFFF2E0E3)),
                    child: Text('${i + 1}', style: const TextStyle(
                      color: Color(0xFF9A5360), fontWeight: FontWeight.w800))),
                  const SizedBox(width: 11),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${tops[i]['name']}', maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700,
                        fontSize: 13)),
                    const SizedBox(height: 5),
                    ClipRRect(borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 5,
                        value: (_amount(tops[i]['revenueMinor']) / highestProduct)
                          .clamp(0.0, 1.0).toDouble(),
                        color: const Color(0xFFBB7C87),
                        backgroundColor: const Color(0xFFF0DDDF))),
                  ])),
                  const SizedBox(width: 13),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(souvenirMoney(_amount(tops[i]['revenueMinor'])),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                        color: Color(0xFF9F5260))),
                    const SizedBox(height: 3),
                    Text('${tops[i]['quantity']} units',
                      style: const TextStyle(fontSize: 11,
                        color: Color(0xFF8C8084))),
                  ]),
                ]),
              ),
            ],
          ));
          return Wrap(spacing: 14, runSpacing: 14, children: [
            SizedBox(width: width, child: dailyTable()),
            SizedBox(width: width, child: productTable()),
          ]);
        }),
        const SizedBox(height: 11),
        const Text('Sales are based on confirmed application orders. Refunds '
          'are not deducted automatically until a verified refund ledger is connected.',
          style: TextStyle(fontSize: 11, color: Color(0xFF82767C))),
      ]);
    },
  );
}


class SouvenirOrdersAdminPage extends StatefulWidget {
  final FirebaseFirestore db;
  final String adminUid;
  final List<AdminVisitor> visitors;
  const SouvenirOrdersAdminPage({super.key, required this.db,
    required this.adminUid, required this.visitors});
  @override
  State<SouvenirOrdersAdminPage> createState() => _SouvenirOrdersAdminPageState();
}

class _SouvenirOrdersAdminPageState extends State<SouvenirOrdersAdminPage> {
  String filter = 'All', search = '';
  String? markingId;
  String? refundingId;
  bool exporting = false;
  static const filters = ['All', 'Awaiting Collection', 'Collected', 'Refunded'];

  String buyer(String uid) {
    for (final visitor in widget.visitors) {
      if (visitor.id == uid) return visitor.name;
    }
    return uid.isEmpty ? 'Unknown visitor' : visitorReference(uid);
  }
  String email(String uid) {
    for (final visitor in widget.visitors) {
      if (visitor.id == uid) return visitor.email;
    }
    return '';
  }

  Future<void> markCollected(ParkSouvenirOrder order) async {
    if (!order.isPaid || order.refundInProgress || order.fulfillment != 'awaiting_collection' || markingId != null) return;
    final agreed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Confirm souvenir collection'),
      content: Text('Have you handed every item in ${souvenirShortId(order.id)} to '
        '${buyer(order.ownerUid)}? This action is recorded and cannot be reversed from this page.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark Collected')),
      ],
    ));
    if (agreed != true || !mounted) return;
    setState(() => markingId = order.id);
    try {
      final ref = widget.db.collection('souvenirOrders').doc(order.id);
      await widget.db.runTransaction((tx) async {
        final live = await tx.get(ref);
        final data = live.data();
        if (data == null || data['status'] != 'paid' || data['currency'] != 'MYR' ||
            data['fulfillmentStatus'] != 'awaiting_collection') {
          throw StateError('Order was already collected or is no longer paid. Refresh the list.');
        }
        tx.update(ref, {
          'fulfillmentStatus': 'collected',
          'collectedAt': FieldValue.serverTimestamp(),
          'collectedByUid': widget.adminUid,
        });
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Collection confirmed. Visitor order updated.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Collection could not be saved: $e')));
    } finally {
      if (mounted) setState(() => markingId = null);
    }
  }

  // PARKSMART_V16_REFUND_CROWD_HISTORY: review visitor requests before Stripe calls.
  Future<void> reviewRefund(ParkSouvenirOrder order, String decision) async {
    if (!order.isPaid || order.fulfillment != 'awaiting_collection' ||
        order.data['refundStatus'] != 'requested' || refundingId != null) return;
    final approving = decision == 'approve';
    final agreed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(approving ? 'Approve visitor refund request?' : 'Reject visitor refund request?'),
      content: Text('Order ${souvenirShortId(order.id)} · ${souvenirMoney(order.amountMinor)}\n'
        'Reason: ${order.data['refundReason'] ?? 'Not provided'}\n\n'
        '${approving ? 'Stripe Test refund starts only after approval.' : 'The order remains paid and can then be collected.'}'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false),child: const Text('Back')),
        FilledButton(onPressed: () => Navigator.pop(ctx,true),
          child: Text(approving ? 'Approve Refund' : 'Reject Request'))],
    ));
    if (agreed != true || !mounted) return;
    setState(() => refundingId=order.id);
    try {
      final auth = FirebaseAuth.instanceFor(app: Firebase.app('ThemeParkAdmin'));
      final response = await StripeCommerceClient(auth: auth).reviewSouvenirRefund(order.id, decision);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        response['status'] == 'refunded' ? 'Stripe refund confirmed; inventory restored.' :
        response['status'] == 'rejected' ? 'Request rejected; order remains paid.' :
        'Decision submitted; refund status is being verified.')));
    } catch(e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Refund decision failed. Check Stripe status before retry: $e')));
    } finally { if (mounted) setState(() => refundingId=null); }
  }

  // Excel/Sheets formula injection protection for user-controlled names.
  static String csv(String value) {
    final stripped = value.trimLeft();
    final safe = stripped.startsWith('=') || stripped.startsWith('+') ||
        stripped.startsWith('-') || stripped.startsWith('@')
        ? "'${value}" : value;
    return '"${safe.replaceAll('"', '""')}"';
  }
  Future<void> exportCsv(List<ParkSouvenirOrder> orders) async {
    setState(() => exporting = true);
    try {
      final lines = <String>[
        'Order reference,Paid at (Malaysia),Customer,Email,Items,Total (MYR),Payment status,Fulfillment status,Collected at (Malaysia),Collector UID',
        for (final o in orders) [
          souvenirShortId(o.id),
          o.paidAt == null ? '' : adminTimeLabel(o.paidAt),
          buyer(o.ownerUid), email(o.ownerUid),
          o.lines.map((x) => '${x['name']} x${x['quantity']}').join('; '),
          (o.amountMinor / 100).toStringAsFixed(2),
          (o.data['status'] ?? '').toString(), o.fulfillment,
          o.collectedAt == null ? '' : adminTimeLabel(o.collectedAt),
          (o.data['collectedByUid'] ?? '').toString(),
        ].map((x) => csv(x.toString())).join(','),
      ];
      await FilePicker.saveFile(
        dialogTitle: 'Export souvenir orders',
        fileName: 'ParkSmart-Souvenir-Orders.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: Uint8List.fromList(utf8.encode('\uFEFF${lines.join('\r\n')}')),
      );
    } catch(e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('CSV export failed: $e')));
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  void details(ParkSouvenirOrder order, Map<String, String> shops) {
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Souvenir order ${souvenirShortId(order.id)}'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
        children: [
          Text('Customer: ${buyer(order.ownerUid)}'),
          if (email(order.ownerUid).isNotEmpty) Text('Email: ${email(order.ownerUid)}'),
          Text('Paid at: ${adminTimeLabel(order.paidAt)}'),
          Text('Payment: ${order.data['status']}'),
          Text('Collection: ${order.fulfillment.replaceAll('_', ' ')}'),
          if (order.collectedAt != null)
            Text('Collected at: ${adminTimeLabel(order.collectedAt)}'),
          const Divider(height: 24),
          for (final p in order.lines) Padding(padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['name'] ?? 'Souvenir'}  x${p['quantity'] ?? 0}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${shops[(p['storeId'] ?? '').toString()] ?? 'Store'}  |  '
                  '${souvenirMoney(_amount(p['lineMinor']))}'),
            ])),
          const Divider(),
          Text('Total paid: ${souvenirMoney(order.amountMinor)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SelectableText('Full order reference: ${order.id}',
              style: const TextStyle(fontSize: 11, color: adminMuted)),
        ],
      ))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        if (order.isPaid && !order.refundInProgress && order.fulfillment == 'awaiting_collection')
          FilledButton(onPressed: () {
            Navigator.pop(ctx);
            markCollected(order);
          }, child: const Text('Confirm Collection')),
      ],
    ));
  }

  Widget stockAlert() => StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream: widget.db.collection('parkMenuItems').snapshots(),
    builder:(ctx,s){
      if (!s.hasData || s.hasError) return const SizedBox.shrink();
      final active = s.data!.docs.where((d)=>d.data()['active']==true &&
        ['Souvenirs','Apparel','Toys','Accessories','Collectibles','Gifts']
          .contains(d.data()['category'])).toList();
      final low = active.where((d) {final n=d.data()['stockQuantity'];
        return n is int && n >= 0 && n <= 5;}).toList();
      if (low.isEmpty) return const SizedBox.shrink();
      return Padding(padding: const EdgeInsets.only(bottom: 14),
        child: AdminCard(child: Wrap(spacing: 12, runSpacing: 6, children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFAC6732)),
          Text('${low.length} products have 5 or fewer units in stock',
            style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(low.take(4).map((d) => '${d.data()['name']} (${d.data()['stockQuantity']})').join(', ')),
        ])));
    },
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const AdminHeading('Souvenir Orders',
      'Stripe-confirmed purchases, customer collection and inventory alerts.'),
    const SizedBox(height: 12),
    stockAlert(),
    StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
      stream: widget.db.collection('attractions').snapshots(),
      builder: (context, locationSnap) {
        final shops = <String, String>{};
        for (final d in locationSnap.data?.docs ?? <QueryDocumentSnapshot<Map<String,dynamic>>>[]) {
          shops[d.id] = (d.data()['name'] ?? d.data()['title'] ?? 'Shop').toString();
        }
        return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
          stream: widget.db.collection('souvenirOrders').snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return AdminCard(child:Text(
              'Could not read Souvenir Orders. Check the admin claim and souvenirOrders rules.\n${snap.error}'));
            if (!snap.hasData) return const Center(child:Padding(
              padding: EdgeInsets.all(35),child:CircularProgressIndicator()));
            final all = [for (final doc in snap.data!.docs)
              if (['paid','refunded'].contains(doc.data()['status']) && doc.data()['currency'] == 'MYR')
                ParkSouvenirOrder(doc.id, doc.data())]
              ..sort((a,b) => (b.paidAt?.millisecondsSinceEpoch ?? 0)
                .compareTo(a.paidAt?.millisecondsSinceEpoch ?? 0));
            final q=search.trim().toLowerCase();
            final filtered=all.where((o) {
              if(filter == 'Awaiting Collection' && o.fulfillment != 'awaiting_collection') return false;
              if(filter == 'Collected' && (o.fulfillment != 'collected' || o.isRefunded)) return false;
              if(filter == 'Refunded' && !o.isRefunded) return false;
              if(filter == 'Awaiting Collection' && o.isRefunded) return false;
              if(q.isEmpty) return true;
              return o.id.toLowerCase().contains(q) ||
                buyer(o.ownerUid).toLowerCase().contains(q) ||
                email(o.ownerUid).toLowerCase().contains(q) ||
                o.lines.any((x) => (x['name'] ?? '').toString().toLowerCase().contains(q));
            }).toList();
            final pending = all.where((o)=>o.isPaid && o.fulfillment=='awaiting_collection').length;
            final refunds = all.where((o)=>o.isRefunded).length;
            final requests = all.where((o)=>o.data['refundStatus']=='requested').length;
            final collected = all.where((o)=>o.isPaid && o.fulfillment=='collected').length;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch,children: [
              Wrap(spacing: 12, runSpacing: 8, children: [
                Chip(label: Text('${all.length} confirmed/refunded orders')),
                Chip(label: Text('$refunds refunded')),
                Chip(label: Text('$requests refund requests')),
                Chip(label: Text('$pending awaiting collection')),
                Chip(label: Text('$collected collected')),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 7, runSpacing: 7, children: [
                for(final f in filters) ChoiceChip(label: Text(f),
                  selected: f == filter,
                  onSelected: (_)=>setState(()=>filter=f)),
              ]),
              const SizedBox(height: 12),
              TextField(onChanged:(v)=>setState(()=>search=v),
                decoration:const InputDecoration(prefixIcon:Icon(Icons.search),
                  labelText:'Search order, customer or product',
                  border:OutlineInputBorder())),
              const SizedBox(height: 9),
              Align(alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.table_view_outlined),
                  onPressed: exporting ? null : () => exportCsv(filtered),
                  label: Text(exporting ? 'Exporting...' : 'Export filtered orders (CSV)'),
                )),
              if (filtered.isEmpty) const AdminCard(child:Text('No souvenir orders match these filters.')),
              for (final order in filtered) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AdminCard(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, children: [
                      Text('Order ${souvenirShortId(order.id)}',
                        style:const TextStyle(fontSize:16,fontWeight:FontWeight.w800)),
                      Text(adminTimeLabel(order.paidAt),
                        style:const TextStyle(color: adminMuted)),
                    ]),
                    const SizedBox(height: 7),
                    Text(buyer(order.ownerUid),
                      style:const TextStyle(fontWeight:FontWeight.w600)),
                    Text(order.lines.map((x)=>'${x['name']} x${x['quantity']}').join(' · '),
                      style:const TextStyle(color:adminMuted)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 12,runSpacing: 8, children: [
                      Chip(label:Text(order.isRefunded ? 'refunded' :
                        order.refundInProgress ? 'refund processing' : order.fulfillment.replaceAll('_',' '))),
                      Text(souvenirMoney(order.amountMinor),style:const TextStyle(
                        fontWeight:FontWeight.w800,fontSize:17,color:adminRose)),
                      TextButton.icon(onPressed:()=>details(order,shops),
                        icon:const Icon(Icons.receipt_long_outlined),label:const Text('Details')),
                      if(order.isPaid && !order.refundInProgress && order.fulfillment == 'awaiting_collection')
                        FilledButton.icon(
                          onPressed:markingId==null ? ()=>markCollected(order):null,
                          icon:markingId==order.id
                            ? const SizedBox(width:15,height:15,child:CircularProgressIndicator(strokeWidth:2))
                            : const Icon(Icons.check_circle_outline),
                          label:const Text('Mark Collected')),
                      if(order.isPaid && order.data['refundStatus']=='requested' &&
                          order.fulfillment=='awaiting_collection') ...[
                        FilledButton.icon(
                          onPressed:refundingId==null ? ()=>reviewRefund(order,'approve') : null,
                          icon:const Icon(Icons.verified_outlined),
                          label:Text(refundingId==order.id ? 'Reviewing...' : 'Approve Refund')),
                        OutlinedButton.icon(
                          onPressed:refundingId==null ? ()=>reviewRefund(order,'reject') : null,
                          icon:const Icon(Icons.close_rounded),
                          label:const Text('Reject Request')),
                      ],
                    ]),
                  ],
                )),
              ),
              const SizedBox(height: 8),
              const Text('Refund requires a visitor request and Admin approval. Stripe verifies payment and stock restoration.',
                style:TextStyle(fontSize:11,color:adminMuted)),
            ]);
          },
        );
      },
    ),
  ]);
}
