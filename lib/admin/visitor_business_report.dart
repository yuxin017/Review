import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../visitor/models/tickets.dart';
import 'admin_models.dart';
import 'admin_widgets.dart';

/// Historical completed ORDER value, not a Stripe settlement statement.
class VisitorMonthlySales {
  final DateTime month;
  final int orderCount, revenueMinor, buyers, returningBuyers;
  const VisitorMonthlySales({
    required this.month,
    required this.orderCount,
    required this.revenueMinor,
    required this.buyers,
    required this.returningBuyers,
  });
  String get label {
    const names = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${names[month.month - 1]} ${month.year}';
  }
  String get shortLabel => label.substring(0, 3);
  double get returningRate => buyers == 0 ? 0 : returningBuyers * 100 / buyers;
}

class VisitorSalesReport {
  final List<VisitorMonthlySales> monthly;
  final List<MapEntry<String, int>> topPackages;
  final int completedOrderValueMinor, completedOrderCount, uniqueBuyers;
  const VisitorSalesReport({
    required this.monthly,
    required this.topPackages,
    required this.completedOrderValueMinor,
    required this.completedOrderCount,
    required this.uniqueBuyers,
  });

  static DateTime _malaysiaDate(DateTime d) => d.toUtc().add(const Duration(hours: 8));

  factory VisitorSalesReport.fromOrders(List<TicketOrder> orders, DateTime now) {
    final completed = orders.where((o) => o.status == 'completed' && o.createdAt != null).toList();
    final firstDate = <String, DateTime>{};
    for (final o in completed) {
      if (o.ownerUid.isEmpty) continue;
      final date = _malaysiaDate(o.createdAt!);
      final previous = firstDate[o.ownerUid];
      if (previous == null || date.isBefore(previous)) firstDate[o.ownerUid] = date;
    }
    final months = <VisitorMonthlySales>[];
    final totalsByPackage = <String, int>{};
    final currentMonth = DateTime(now.year, now.month);
    for (var offset = 5; offset >= 0; offset--) {
      final start = DateTime(currentMonth.year, currentMonth.month - offset);
      final end = DateTime(start.year, start.month + 1);
      final items = completed.where((o) {
        final d = _malaysiaDate(o.createdAt!);
        return !d.isBefore(start) && d.isBefore(end);
      }).toList();
      final buyerIds = items.where((o) => o.ownerUid.isNotEmpty).map((o) => o.ownerUid).toSet();
      final returning = buyerIds.where((id) {
        final first = firstDate[id];
        return first != null && first.isBefore(start);
      }).length;
      for (final item in items) {
        totalsByPackage[item.packageName] = (totalsByPackage[item.packageName] ?? 0) + item.totalMinor;
      }
      months.add(VisitorMonthlySales(
        month: start,
        orderCount: items.length,
        revenueMinor: items.fold<int>(0, (sum, o) => sum + o.totalMinor),
        buyers: buyerIds.length,
        returningBuyers: returning,
      ));
    }
    final packages = totalsByPackage.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return VisitorSalesReport(
      monthly: months,
      topPackages: packages.take(5).toList(),
      completedOrderValueMinor: months.fold<int>(0, (sum, v) => sum + v.revenueMinor),
      completedOrderCount: months.fold<int>(0, (sum, v) => sum + v.orderCount),
      uniqueBuyers: completed.where((o) {
        final day = _malaysiaDate(o.createdAt!);
        final end = DateTime(currentMonth.year, currentMonth.month + 1);
        return o.ownerUid.isNotEmpty &&
            !day.isBefore(months.first.month) && day.isBefore(end);
      }).map((o) => o.ownerUid).toSet().length,
    );
  }

  String get recommendation {
    if (monthly.every((v) => v.orderCount == 0)) {
      return 'No completed ticket purchases are recorded for this period. Check checkout availability and payment confirmation.';
    }
    final thisMonth = monthly.last;
    final lastMonth = monthly[monthly.length - 2];
    if (thisMonth.orderCount > 0 && thisMonth.returningRate < 25) {
      return 'Few ticket buyers are returning. Consider a return-visit offer and check whether members are using their rewards.';
    }
    if (lastMonth.revenueMinor > 0 && thisMonth.revenueMinor < lastMonth.revenueMinor) {
      return 'Sales are currently below the previous full month. The current month may be incomplete; check daily purchases before changing promotions.';
    }
    return 'Ticket demand is being recorded. Compare the strongest-selling packages and focus offers on repeat visits.';
  }
}

String visitorReportMoney(int minor) {
  final fixed = (minor / 100).toStringAsFixed(2);
  return 'RM $fixed';
}

class VisitorSalesTrendChart extends StatelessWidget {
  final VisitorSalesReport data;
  const VisitorSalesTrendChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final maxMinor = data.monthly.fold<int>(0, (max, item) =>
        math.max(max, item.revenueMinor));
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4E9E4),
        border: Border.all(color: const Color(0xFFE8DAD5)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bar_chart_rounded, size: 21, color: Color(0xFF985F65)),
          const SizedBox(width: 9),
          const Expanded(child: Text('Ticket sales over the last 6 months',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF352B2C)))),
          Text('MYR', style: TextStyle(color: Colors.brown.shade600, fontSize: 12)),
        ]),
        const SizedBox(height: 5),
        const Text('Completed ticket orders · not confirmed Stripe payouts',
          style: TextStyle(fontSize: 12, color: Color(0xFF796B68))),
        const SizedBox(height: 18),
        SizedBox(height: 175, child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [for (final item in data.monthly) Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(item.revenueMinor == 0 ? '—' : '${(item.revenueMinor / 100).round()}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: Color(0xFF533F3E))),
              const SizedBox(height: 6),
              Container(
                height: maxMinor == 0 ? 3 : math.max(3.0, 124.0 * item.revenueMinor / maxMinor),
                decoration: BoxDecoration(
                  color: item == data.monthly.last
                      ? const Color(0xFF9D5359) : const Color(0xFFC98B89),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                ),
              ),
              const SizedBox(height: 8),
              Text(item.shortLabel, style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF705C59))),
            ]),
          ))],
        )),
        const SizedBox(height: 8),
        const Text('Includes sample orders if demo data has been imported.',
          style: TextStyle(fontSize: 11, color: Color(0xFF796B68))),
      ]),
    );
  }
}

Future<void> printVisitorSalesReport(VisitorSalesReport report) async {
  final pdf = pw.Document();
  final maxSales = report.monthly.fold<int>(1, (v, row) => math.max(v, row.revenueMinor));
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(34),
    build: (_) => [
      pw.Text('THEME PARK', style: pw.TextStyle(fontSize: 13,
        fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#985F65'))),
      pw.SizedBox(height: 10),
      pw.Text('Visitor Purchase & Loyalty Report',
        style: pw.TextStyle(fontSize: 21, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 5),
      pw.Text('Period: ${report.monthly.first.label} - ${report.monthly.last.label}'),
      pw.SizedBox(height: 15),
      pw.Text('Completed order value: ${visitorReportMoney(report.completedOrderValueMinor)}'),
      pw.Text('Completed ticket orders: ${report.completedOrderCount}'),
      pw.Text('Distinct purchasing visitors: ${report.uniqueBuyers}'),
      pw.SizedBox(height: 22),
      pw.Text('Monthly ticket sales', style: pw.TextStyle(fontSize: 15,
        fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 10),
      for (final item in report.monthly) pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 9),
        child: pw.Row(children: [
          pw.SizedBox(width: 67, child: pw.Text(item.label,
            style: const pw.TextStyle(fontSize: 10))),
          pw.Container(width: math.max(2.0, 255.0 * item.revenueMinor / maxSales),
            height: 13, color: PdfColor.fromHex('#B9787D')),
          pw.SizedBox(width: 9),
          pw.Text(visitorReportMoney(item.revenueMinor),
            style: const pw.TextStyle(fontSize: 10)),
        ]),
      ),
      pw.SizedBox(height: 16),
      pw.TableHelper.fromTextArray(
        headers: ['Month', 'Orders', 'Buyers', 'Returning buyers', 'Sales (MYR)'],
        data: [for (final item in report.monthly) [
          item.label, '${item.orderCount}', '${item.buyers}',
          '${item.returningBuyers}', (item.revenueMinor / 100).toStringAsFixed(2),
        ]],
      ),
      pw.SizedBox(height: 20),
      pw.Text('Top ticket packages by order value',
        style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 7),
      if (report.topPackages.isEmpty) pw.Text('No recorded package purchases')
      else pw.TableHelper.fromTextArray(
        headers: ['Package', 'Recorded value (MYR)'],
        data: [for (final entry in report.topPackages)
          [entry.key, (entry.value / 100).toStringAsFixed(2)]],
      ),
      pw.SizedBox(height: 19),
      pw.Text('Suggested action', style: pw.TextStyle(fontSize: 14,
        fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 5),
      pw.Text(report.recommendation),
      pw.SizedBox(height: 22),
      pw.Text('Reporting note: Figures use application orders marked completed. They are not a bank or Stripe settlement report. Synthetic demo data may be included. Current month totals may be incomplete. No visitor identity is exported.',
        style: const pw.TextStyle(fontSize: 9)),
    ],
  ));
  await Printing.layoutPdf(onLayout: (_) async => pdf.save(),
    name: 'Visitor_Purchase_Report.pdf');
}

class VisitorBusinessReportDialog extends StatelessWidget {
  final VisitorSalesReport report;
  const VisitorBusinessReportDialog({super.key, required this.report});

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    backgroundColor: const Color(0xFFF6EEE9),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 880, maxHeight: 770),
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(23, 19, 14, 17),
          child: Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Visitor Business Report', style: TextStyle(fontSize: 23,
                  fontWeight: FontWeight.w800, color: Color(0xFF352B2C))),
                SizedBox(height: 5),
                Text('Revenue trends, returning visitors and ticket performance',
                  style: TextStyle(fontSize: 12, color: Color(0xFF746865))),
              ])),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ])),
        const Divider(height: 1),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(19),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            VisitorSalesTrendChart(data: report),
            const SizedBox(height: 18),
            Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(
              color: const Color(0xFFFFFAF7), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Monthly breakdown', style: TextStyle(fontSize: 17,
                  fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                SingleChildScrollView(scrollDirection: Axis.horizontal,
                  child: DataTable(columns: const [
                    DataColumn(label: Text('Month')), DataColumn(label: Text('Orders')),
                    DataColumn(label: Text('Buyers')), DataColumn(label: Text('Returned')),
                    DataColumn(label: Text('Recorded sales')),
                  ], rows: [for (final item in report.monthly) DataRow(cells: [
                    DataCell(Text(item.label)), DataCell(Text('${item.orderCount}')),
                    DataCell(Text('${item.buyers}')),
                    DataCell(Text('${item.returningBuyers}')),
                    DataCell(Text(visitorReportMoney(item.revenueMinor))),
                  ])]),
                ),
              ])),
            const SizedBox(height: 15),
            Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(
              color: const Color(0xFFEBDAD4), borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lightbulb_outline, color: Color(0xFF915B63)),
                const SizedBox(width: 11),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Business recommendation', style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text(report.recommendation, style: const TextStyle(fontSize: 13)),
                ])),
              ])),
          ]),
        )),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          child: Row(children: [
            const Expanded(child: Text('No names or contact details in the PDF.',
              style: TextStyle(fontSize: 12, color: Color(0xFF746865)))),
            AdminButton('Print / Save PDF', icon: Icons.picture_as_pdf_outlined,
              onPressed: () async {
                try {
                  await printVisitorSalesReport(report);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not create PDF. Please try again.')),
                    );
                  }
                }
              }),
          ])),
      ])),
  );
}
