import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'admin_models.dart';
import 'admin_widgets.dart';

class VisitorMonthSummary {
  final DateTime month;
  final int joined, active;
  const VisitorMonthSummary(this.month, this.joined, this.active);
  static const _monthNames = ['Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'];
  String get label => '${_monthNames[month.month - 1]} ${month.year}';
  String get shortLabel => _monthNames[month.month - 1];
}

/// Uses visitor registrations and Firebase visitorSessions, not sales.
/// Active = signed into the visitor app within the last 30 days.
/// Repeat = visitor app activity on at least two distinct dates in 30 days.
class VisitorAccountReport {
  final List<VisitorMonthSummary> months;
  final int registered, joinedThisMonth, active30Days, repeatActivity,
      inactive60Days, flagged, suspended, archived;
  final Map<String, int> membershipCounts;
  final bool hasActivityRecords;

  const VisitorAccountReport({
    required this.months,
    required this.registered,
    required this.joinedThisMonth,
    required this.active30Days,
    required this.repeatActivity,
    required this.inactive60Days,
    required this.flagged,
    required this.suspended,
    required this.archived,
    required this.membershipCounts,
    required this.hasActivityRecords,
  });

  static DateTime inPark(DateTime day) =>
      day.toUtc().add(const Duration(hours: 8));
  static String key(DateTime d) => '${d.year}-${d.month}-${d.day}';

  factory VisitorAccountReport.calculate(
    List<AdminVisitor> visitors,
    List<AdminActivity> sessions,
    DateTime now,
  ) {
    final today = inPark(now);
    final monthStart = DateTime(today.year, today.month);
    final thirty = now.subtract(const Duration(days: 30));
    final sixty = now.subtract(const Duration(days: 60));
    final visitorIds = visitors.map((v) => v.id).toSet();
    final activeDates = <String, Set<String>>{};
    final latest = <String, DateTime>{};
    final monthActivity = <String, Set<String>>{};
    for (final s in sessions) {
      final uid = s.ownerUid;
      final date = adminDate(s.data['lastSeenAt']) ?? s.at;
      if (uid.isEmpty || date == null || !visitorIds.contains(uid)) continue;
      final parkDate = inPark(date);
      final monthKey = '${parkDate.year}-${parkDate.month}';
      monthActivity.putIfAbsent(monthKey, () => <String>{}).add(uid);
      final prev = latest[uid];
      if (prev == null || date.isAfter(prev)) latest[uid] = date;
      if (!date.isBefore(thirty) && !date.isAfter(now)) {
        activeDates.putIfAbsent(uid, () => <String>{}).add(key(parkDate));
      }
    }
    final membershipCounts = <String, int>{};
    for (final v in visitors) {
      final membership = v.membershipLabel;
      membershipCounts[membership] = (membershipCounts[membership] ?? 0) + 1;
    }
    final months = <VisitorMonthSummary>[];
    for (var offset = 5; offset >= 0; offset--) {
      final start = DateTime(monthStart.year, monthStart.month - offset);
      final end = DateTime(start.year, start.month + 1);
      final count = visitors.where((v) {
        final joined = v.joined;
        if (joined == null) return false;
        final d = inPark(joined);
        return !d.isBefore(start) && d.isBefore(end);
      }).length;
      months.add(VisitorMonthSummary(start, count,
        monthActivity['${start.year}-${start.month}']?.length ?? 0));
    }
    return VisitorAccountReport(
      months: months,
      registered: visitors.length,
      joinedThisMonth: months.last.joined,
      active30Days: activeDates.length,
      repeatActivity: activeDates.values.where((days) => days.length >= 2).length,
      inactive60Days: sessions.isEmpty ? 0 : visitors.where((v) =>
        v.status == 'active' && v.joined != null && v.joined!.isBefore(sixty) &&
        (latest[v.id] == null || latest[v.id]!.isBefore(sixty))).length,
      flagged: visitors.where((v) => v.watchlisted || v.risk != 'normal').length,
      suspended: visitors.where((v) => v.status == 'suspended').length,
      archived: visitors.where((v) => v.status == 'archived').length,
      membershipCounts: membershipCounts,
      hasActivityRecords: sessions.isNotEmpty,
    );
  }

  String get nextAction {
    if (!hasActivityRecords) {
      return 'No visitor-app activity has been recorded. Check session tracking before measuring engagement.';
    }
    if (inactive60Days > active30Days) {
      return '$inactive60Days visitors have not used the app for over 60 days. Consider a return-visit campaign.';
    }
    if (flagged > 0) {
      return '$flagged accounts need attention. Review the evidence before making access decisions.';
    }
    return 'Review membership participation and repeat activity to understand which visitors stay engaged.';
  }
}

class VisitorAccountTrendChart extends StatelessWidget {
  final VisitorAccountReport report;
  const VisitorAccountTrendChart({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final maxValue = report.months.fold<int>(1,
      (max, v) => math.max(max, math.max(v.joined, v.active)));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFFFFBF9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6D8D1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Visitor Growth Trend', style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w700,
          color: Color(0xFF362D2F))),
        const SizedBox(height: 5),
        const Text('New accounts and visitors who used the app',
          style: TextStyle(fontSize: 12, color: Color(0xFF756A69))),
        const SizedBox(height: 14),
        Row(children: [
          _legend(const Color(0xFFB9797D), 'New Visitors'),
          const SizedBox(width: 18),
          _legend(const Color(0xFF7D988A), 'Active Visitors'),
        ]),
        const SizedBox(height: 14),
        SizedBox(height: 170, child: Row(crossAxisAlignment: CrossAxisAlignment.end,
          children: [for (final m in report.months)
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('${m.joined} / ${m.active}', maxLines: 1,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF655756))),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: _bar(m.joined, maxValue, const Color(0xFFB9797D))),
                  const SizedBox(width: 3),
                  Expanded(child: _bar(m.active, maxValue, const Color(0xFF7D988A))),
                ]),
                const SizedBox(height: 7),
                Text(m.shortLabel, style: const TextStyle(fontSize: 11,
                  color: Color(0xFF655756), fontWeight: FontWeight.w600)),
              ]),
            )),
          ])),
        const SizedBox(height: 7),
        Text(report.hasActivityRecords
          ? 'App activity is based on recorded sessions.'
          : 'No app activity records available yet.',
          style: const TextStyle(fontSize: 11, color: Color(0xFF806C67))),
      ]),
    );
  }

  Widget _bar(int value, int max, Color color) => Container(
    height: math.max(3.0, 114.0 * value / max),
    decoration: BoxDecoration(color: color,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(5))),
  );

  Widget _legend(Color color, String label) => Row(mainAxisSize: MainAxisSize.min,
    children: [Container(width: 9, height: 9, decoration: BoxDecoration(
      color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 6), Text(label,
        style: const TextStyle(fontSize: 11, color: Color(0xFF6D5F60)))],
  );
}

Future<void> printVisitorAccountReport(VisitorAccountReport report) async {
  final pdf = pw.Document();
  final maxValue = report.months.fold<int>(1, (v, row) =>
      math.max(v, math.max(row.joined, row.active)));
  pdf.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(34), build: (_) => [
      pw.Text('THEME PARK · VISITOR ACCOUNTS',
        style: pw.TextStyle(color: PdfColor.fromHex('#9B656A'),
          fontWeight: pw.FontWeight.bold, fontSize: 12)),
      pw.SizedBox(height: 10),
      pw.Text('Visitor Growth & Engagement Report',
        style: pw.TextStyle(fontSize: 21, fontWeight: pw.FontWeight.bold)),
      pw.Text('${report.months.first.label} - ${report.months.last.label}'),
      pw.SizedBox(height: 18),
      pw.Text('Registered accounts: ${report.registered}'),
      pw.Text('New this month: ${report.joinedThisMonth}'),
      pw.Text('Used app in 30 days: ${report.active30Days}'),
      pw.Text('Used app on two or more days: ${report.repeatActivity}'),
      pw.Text('Inactive over 60 days: ${report.inactive60Days}'),
      pw.Text('Accounts requiring review: ${report.flagged}'),
      pw.SizedBox(height: 19),
      pw.Text('Monthly visitor growth', style: pw.TextStyle(
        fontSize: 15, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 10),
      for (final row in report.months) pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 9),
        child: pw.Row(children: [
          pw.SizedBox(width: 64, child: pw.Text(row.label)),
          pw.Container(width: math.max(2.0, 220.0 * row.joined / maxValue),
            height: 11, color: PdfColor.fromHex('#B9797D')),
          pw.SizedBox(width: 6),
          pw.Text('New: ${row.joined}  Active: ${row.active}',
            style: const pw.TextStyle(fontSize: 9)),
        ]),
      ),
      pw.SizedBox(height: 14),
      pw.TableHelper.fromTextArray(
        headers: ['Month', 'New Visitors', 'Visitors using app'],
        data: [for (final m in report.months)
          [m.label, '${m.joined}', '${m.active}']],
      ),
      pw.SizedBox(height: 17),
      pw.Text('Membership distribution', style: pw.TextStyle(
        fontSize: 15, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 9),
      pw.TableHelper.fromTextArray(headers: ['Level', 'Visitors'],
        data: [for (final entry in report.membershipCounts.entries)
          [entry.key, '${entry.value}']]),
      pw.SizedBox(height: 18),
      pw.Text('Suggested next action', style: pw.TextStyle(
        fontWeight: pw.FontWeight.bold)),
      pw.Text(report.nextAction),
      pw.SizedBox(height: 15),
      pw.Text('This report uses account registrations and available visitor-app session logs, not ticket revenue. '
          'No visitor names, email addresses or phone numbers are included. '
          'Demo records may be present; earlier activity records may be missing and the current month is incomplete.',
        style: const pw.TextStyle(fontSize: 9)),
    ]));
  await Printing.layoutPdf(onLayout: (_) async => pdf.save(),
    name: 'Visitor_Accounts_Report.pdf');
}

class VisitorAccountReportDialog extends StatelessWidget {
  final VisitorAccountReport report;
  const VisitorAccountReportDialog({super.key, required this.report});

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(14),
    backgroundColor: const Color(0xFFF6EEE9),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: ConstrainedBox(constraints: const BoxConstraints(
      maxWidth: 780, maxHeight: 720), child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(22, 17, 12, 12),
          child: Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Visitor Accounts Report', style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold)),
                Text('Growth, app activity and membership. No sales figures.',
                  style: TextStyle(color: Color(0xFF796C68), fontSize: 12)),
              ])),
            IconButton(onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close)),
          ])),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VisitorAccountTrendChart(report: report),
              const SizedBox(height: 15),
              const Text('Membership distribution', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              for (final entry in report.membershipCounts.entries)
                Padding(padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Expanded(child: Text(entry.key)),
                    Text('${entry.value} visitors'),
                  ])),
              const SizedBox(height: 12),
              Text(report.nextAction, style: const TextStyle(
                fontSize: 13, height: 1.4)),
            ]))),
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          const Expanded(child: Text('No personal details are exported.',
            style: TextStyle(fontSize: 12, color: Color(0xFF796C68)))),
          AdminButton('Save / Print PDF', icon: Icons.picture_as_pdf_outlined,
            onPressed: () async {
              try {
                await printVisitorAccountReport(report);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Unable to create PDF. Please try again.')));
                }
              }
            }),
        ])),
      ])),
  );
}
