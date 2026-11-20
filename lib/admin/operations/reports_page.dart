import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../photos/photo_repository.dart';
import '../admin_models.dart';
import '../admin_widgets.dart';
import '../products/souvenir_admin_page.dart';
import 'park_admin_repository.dart';

// PARKSMART_UNIFIED_SALES_V12: aggregate separate sales channels exactly once.
// Server report daily rows represent Ticket + Photo; confirmed souvenir rows
// are merged by Malaysia reporting day for unified PDF totals.
List<Map<String, dynamic>> _combinedParkDaily(Map<String, dynamic> report) {
  final days = <String, Map<String, dynamic>>{};
  void merge(dynamic raw) {
    if (raw is! Map) return;
    final day = (raw['day'] ?? '').toString();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) return;
    final existing = days.putIfAbsent(day, () => {
      'day': day, 'orders': 0, 'revenueMinor': 0,
    });
    existing['orders'] = ((existing['orders'] as num) +
      ((raw['orders'] as num?) ?? 0)).toInt();
    existing['revenueMinor'] = ((existing['revenueMinor'] as num) +
      ((raw['revenueMinor'] as num?) ?? 0)).toInt();
  }
  for (final raw in (report['daily'] as List? ?? const [])) merge(raw);
  final souvenir = report['souvenir'];
  if (souvenir is Map) {
    for (final raw in (souvenir['daily'] as List? ?? const [])) merge(raw);
  }
  return days.values.toList()..sort((a, b) =>
    (a['day'] as String).compareTo(b['day'] as String));
}

Future<Uint8List> buildParkReportPdf(
  Map<String, dynamic> report, {
  Uint8List? logoBytes,
}) async {
  final document = pw.Document(),
      summary = Map<String, dynamic>.from(report['summary']);
  final channel = report['souvenir'] is Map ? (report['souvenir'] as Map) : <String, dynamic>{};
  final ticketPhotoMinor = (summary['revenueMinor'] as num? ?? 0).toInt();
  final souvenirMinor = (channel['revenueMinor'] as num? ?? 0).toInt();
  final totalMinor = ticketPhotoMinor + souvenirMinor;
  final totalOrders = (((summary['ticketOrders'] as num?) ?? 0) +
     ((summary['photoOrders'] as num?) ?? 0) +
     ((channel['paidOrders'] as num?) ?? 0)).toInt();
  final daily = _combinedParkDaily(report);
  final chartRows = daily.reversed.take(10).toList().reversed;
  final peak = chartRows.fold<int>(1, (max, row) {
    final value = row['revenueMinor'] as int;
    return value > max ? value : max;
  });
  final logo = logoBytes == null ? null : pw.MemoryImage(logoBytes);
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Row(children: [
          if (logo != null) ...[
            pw.Image(logo, width: 58, height: 58, fit: pw.BoxFit.contain),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('THEME PARK', style: pw.TextStyle(
                fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.Text('Unified Sales & Attendance Report', style: const pw.TextStyle(fontSize: 15)),
            ],
          )),
        ]),
        pw.SizedBox(height: 8),
        pw.Text('${report['start']} to ${report['end']} · Malaysia time'),
        pw.SizedBox(height: 22),
        if (chartRows.isNotEmpty) ...[
          pw.Text('Sales by day · MYR', style: pw.TextStyle(
            fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          for (final row in chartRows)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(children: [
                pw.SizedBox(width: 68, child: pw.Text('${row['day']}',
                  style: const pw.TextStyle(fontSize: 9))),
                pw.SizedBox(width: 200, child: pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Container(height: 8,
                    width: 200 * (row['revenueMinor'] as int).clamp(0, peak) / peak,
                    color: PdfColor.fromHex('#A44854')),
                )),
                pw.SizedBox(width: 10),
                pw.Text(photoMoney(row['revenueMinor']), style: const pw.TextStyle(fontSize: 9)),
              ]),
            ),
          pw.SizedBox(height: 16),
        ],
        pw.TableHelper.fromTextArray(
          headers: ['Measure', 'Total'],
          data: [
            ['Total confirmed sales (all channels)', photoMoney(totalMinor)],
            ['Ticket + Photo sales', photoMoney(ticketPhotoMinor)],
            ['Souvenir sales', photoMoney(souvenirMinor)],
            ['Paid orders (all channels)', '$totalOrders'],
            ['Ticket orders', '${summary['ticketOrders']}'],
            ['Photo orders', '${summary['photoOrders']}'],
            ['Park admissions', '${summary['parkAdmissions']}'],
            ['Attraction check-ins', '${summary['rideAdmissions']}'],
            ['Reservations', '${summary['reservations']}'],
            ['Cancellations', '${summary['cancellations']}'],
            ['Vouchers issued in period', '${summary['vouchersIssued'] ?? 0}'],
            [
              'Issued vouchers redeemed to date',
              '${summary['vouchersRedeemed'] ?? 0}',
            ],
            [
              'Issued voucher redemption rate',
              '${summary['voucherRedemptionRate'] ?? 0}%',
            ],
            ['Voucher uses in period', '${summary['voucherUseEvents'] ?? 0}'],
          ],
        ),
        pw.SizedBox(height: 24),
        pw.Text(
          'Combined Daily Sales (All Channels)',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: ['Park Day', 'Orders', 'Amount (MYR)'],
          data: [
            for (final row in _combinedParkDaily(report))
              [row['day'], '${row['orders']}', photoMoney(row['revenueMinor'])],
          ],
        ),
        pw.SizedBox(height: 22),
        pw.Text(
          'Top 10 Ticket + Photo Products',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: ['Product', 'Quantity', 'Amount (MYR)'],
          data: [
            for (final row in (report['topProducts'] as List).cast<Map>())
              [
                row['name'],
                '${row['quantity']}',
                photoMoney(row['revenueMinor']),
              ],
          ],
        ),
        // SOUVENIR_ADMIN_V11: separate channel accounting and combined total.
        if (report['souvenir'] is Map) ...[
          pw.SizedBox(height: 22),
          pw.Text('Souvenir Sales',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['Metric', 'Value'],
            data: [
              ['Ticket + Photo', photoMoney(summary['revenueMinor'])],
              ['Souvenir', photoMoney((report['souvenir'] as Map)['revenueMinor'])],
              ['Combined confirmed sales', photoMoney(
                ((summary['revenueMinor'] as num? ?? 0) +
                 (((report['souvenir'] as Map)['revenueMinor'] as num?) ?? 0)).toInt())],
              ['Paid souvenir orders', '${(report['souvenir'] as Map)['paidOrders']}'],
              ['Souvenir units sold', '${(report['souvenir'] as Map)['units']}'],
              ['Awaiting collection', '${(report['souvenir'] as Map)['awaitingCollection']}'],
              ['Collected', '${(report['souvenir'] as Map)['collected']}'],
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text('Top Souvenir Products',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.TableHelper.fromTextArray(
            headers: ['Product', 'Units', 'Paid Value'],
            data: [
              if (((report['souvenir'] as Map)['topProducts'] as List).isEmpty)
                ['No souvenir sales', '0', 'RM 0.00']
              else
                for (final item in ((report['souvenir'] as Map)['topProducts'] as List).cast<Map>())
                  [item['name'], '${item['quantity']}', photoMoney(item['revenueMinor'])],
            ],
          ),
        ],
        pw.SizedBox(height: 22),
        pw.Text(
          'Top 10 Attractions',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: ['Attraction', 'Check-ins'],
          data: [
            for (final row in (report['topAttractions'] as List).cast<Map>())
              [row['name'], '${row['visits']}'],
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          'Purchase values reflect confirmed application orders. Reporting days use Malaysia time.',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
    ),
  );
  return document.save();
}

enum _ReportView {
  overview('Sales & Attendance', {}),
  admissions('Admissions', {'Park check-ins': 'parkAdmissions', 'Attraction check-ins': 'rideAdmissions'}),
  queue('Reservations', {'Reservations': 'reservations', 'Cancellations': 'cancellations'}),
  rewards('Rewards', {'Vouchers issued': 'vouchersIssued', 'Vouchers redeemed': 'vouchersRedeemed'}),
  photos('Smart Photos', {'Confirmed photo orders': 'photoOrders'}),
  staff('Staff & Leave', {
    'Published shift assignments': 'staffShifts',
    'Approved leave overlapping period': 'approvedLeave',
    'Pending leave overlapping period': 'pendingLeave',
  });

  const _ReportView(this.label, this.metrics);
  final String label;
  final Map<String, String> metrics;
}

Future<Uint8List> _buildFocusedReport(
  _ReportView view, Map<String, dynamic> report, Uint8List logo,
) async {
  final summary = report['summary'] as Map;
  final metrics = {
    for (final entry in view.metrics.entries)
      entry.key: (summary[entry.value] as num?)?.toInt() ?? 0,
  };
  final peak = metrics.values.fold<int>(1, (max, value) => value > max ? value : max);
  final pdf = pw.Document();
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    footer: (context) => pw.Align(alignment: pw.Alignment.centerRight,
      child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}')),
    build: (_) => [
      pw.Row(children: [
        pw.Image(pw.MemoryImage(logo), width: 62, height: 62, fit: pw.BoxFit.contain),
        pw.SizedBox(width: 14),
        pw.Text('${view.label} Report', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.SizedBox(height: 14),
      pw.Text('${report['start']} to ${report['end']} · Malaysia time'),
      pw.SizedBox(height: 20),
      for (final entry in metrics.entries)
        pw.Padding(padding: const pw.EdgeInsets.only(bottom: 12), child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('${entry.key}  ${entry.value}'),
            pw.SizedBox(height: 4),
            pw.Container(height: 9, width: 220 * entry.value / peak,
              color: PdfColor.fromHex('#A44854')),
          ],
        )),
      pw.TableHelper.fromTextArray(
        headers: ['Metric', 'Total'],
        data: [for (final entry in metrics.entries) [entry.key, '${entry.value}']],
      ),
    ],
  ));
  return pdf.save();
}

class ParkReportsPage extends StatefulWidget {
  final ParkAdminRepository repository;
  const ParkReportsPage({super.key, required this.repository, this.embedded = false, this.souvenirDb});
  final bool embedded;
  final FirebaseFirestore? souvenirDb;
  @override
  State<ParkReportsPage> createState() => _ParkReportsPageState();
}

class _ParkReportsPageState extends State<ParkReportsPage> {
  late DateTimeRange period = DateTimeRange(
    start: DateTime(DateTime.now().year, DateTime.now().month, 1),
    end: DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    ),
  );
  _ReportView view = _ReportView.overview;
  late Future<Map<String, dynamic>> report = load();
  bool exporting = false;
  String _dateKey(DateTime date) => date.toIso8601String().substring(0, 10);

  DateTime _parkMidnight(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).subtract(const Duration(hours: 8));

  Future<Map<String, dynamic>> load() async {
    final selectedView = view;
    final from = period.start;
    final to = period.end;
    final start = _parkMidnight(from);
    final end = _parkMidnight(to).add(const Duration(days: 1));
    final dates = {'start': _dateKey(from), 'end': _dateKey(to)};
    if (selectedView != _ReportView.staff || widget.souvenirDb == null) {
      final result = await widget.repository.request('report', {
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
      });
      return {...result, ...dates};
    }
    final db = widget.souvenirDb!;
    final results = await Future.wait([
      db.collection('staffPublishedShifts')
          .where('startsAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('startsAt', isLessThan: Timestamp.fromDate(end)).get(),
      db.collection('staffLeaveRequests')
          .where('endOn', isGreaterThanOrEqualTo: dates['start']).get(),
    ]);
    final leaves = results[1].docs.map((doc) => doc.data()).where((leave) {
      final firstDay = leave['startOn'];
      return firstDay is String && firstDay.compareTo(dates['end']!) <= 0;
    }).toList();
    return {
      ...dates,
      'summary': {
        'staffShifts': results[0].docs.where((doc) => doc.data()['published'] == true).length,
        'approvedLeave': leaves.where((leave) => leave['status'] == 'approved').length,
        'pendingLeave': leaves.where((leave) => leave['status'] == 'pending').length,
      },
    };
  }

  void _selectReport(_ReportView option) {
    if (view == option) return;
    setState(() {
      view = option;
      report = load();
    });
  }

  Future<void> dates() async {
    DateTime from = period.start;
    DateTime to = period.end;
    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => Dialog(
          elevation: 22,
          shadowColor: const Color(0x600D1420),
          backgroundColor: const Color(0xFFF6EBE9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Icon(Icons.date_range_outlined, color: adminRose),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Report period',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700))),
                  IconButton(onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close_rounded)),
                ]),
                const SizedBox(height: 18),
                Wrap(spacing: 7, runSpacing: 7, children: [
                  for (final days in [7, 30, 90]) OutlinedButton(
                    onPressed: () => update(() {
                      to = DateTime.now();
                      from = DateTime(to.year, to.month, to.day)
                          .subtract(Duration(days: days - 1));
                    }),
                    child: Text('Last $days days')),
                ]),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined, size: 17),
                    label: Text(adminDateLabel(from)),
                    onPressed: () async {
                      final pickedDate = await showDatePicker(
                        context: dialogContext, initialDate: from,
                        firstDate: DateTime(2020), lastDate: DateTime.now());
                      if (pickedDate != null) update(() { from = pickedDate;
                        if (to.isBefore(from)) to = from; });
                    })),
                  const SizedBox(width: 12),
                  Expanded(child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_outlined, size: 17),
                    label: Text(adminDateLabel(to)),
                    onPressed: () async {
                      final pickedDate = await showDatePicker(
                        context: dialogContext,
                        initialDate: to.isBefore(from) ? from : to,
                        firstDate: from, lastDate: DateTime.now());
                      if (pickedDate != null) update(() => to = pickedDate);
                    })),
                ]),
                const SizedBox(height: 8),
                if (to.difference(from).inDays > 92)
                  const Text('Select up to 93 days.',
                    style: TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel')),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: to.isBefore(from) ||
                    to.difference(from).inDays > 92 ? null : () =>
                      Navigator.pop(dialogContext, DateTimeRange(start: from, end: to)),
                    child: const Text('Apply')),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() { period = picked; report = load(); });
    }
  }

  Future<void> export(Map<String, dynamic> data) async {
    setState(() => exporting = true);
    try {
      final logo = await rootBundle.load('assets/images/Theme_Park_Main_Logo.png');
      final logoBytes = logo.buffer.asUint8List(logo.offsetInBytes, logo.lengthInBytes);
      final selectedView = view;
      await FilePicker.saveFile(
        fileName:
            'ThemePark-${selectedView.name}-${_dateKey(period.start)}.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: selectedView == _ReportView.overview ? await buildParkReportPdf({
          ...data,
          // SOUVENIR_ADMIN_V11: include verified souvenir totals in exported PDF.
          if (widget.souvenirDb != null)
            'souvenir': await loadSouvenirSales(widget.souvenirDb!, period.start, period.end),
        }, logoBytes: logoBytes) : await _buildFocusedReport(selectedView, data, logoBytes),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(photoError(e))));
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: report,
    builder: (context, s) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          widget.embedded ? 'Sales Performance' : 'Reports & Analytics',
          widget.embedded ? 'Sales trends and best-selling products.'
              : 'Sales, attendance, reservations, rewards, photos and staff.',
        ),
        if (!widget.embedded) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final option in _ReportView.values)
              if (option != _ReportView.staff || widget.souvenirDb != null)
                ChoiceChip(label: Text(option.label), selected: view == option,
                  onSelected: exporting ? null : (_) => _selectReport(option)),
          ]),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            const Icon(Icons.calendar_month_outlined, color: adminRose, size: 18),
            const SizedBox(width: 8),
            Text('${_dateKey(period.start)} – ${_dateKey(period.end)}',
              style: const TextStyle(color: adminMuted, fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: dates, icon: const Icon(Icons.tune, size: 16),
              label: const Text('Change period'),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh reports',
              onPressed: () => setState(() => report = load()),
              icon: const Icon(Icons.refresh, color: adminRose),
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (s.hasError)
          AdminCard(
            child: Column(
              children: [
                const Icon(Icons.insights_outlined, size: 50, color: adminRose),
                const SizedBox(height: 15),
                Text(photoError(s.error!)),
                const SizedBox(height: 15),
                AdminButton(
                  'Try Again',
                  onPressed: () => setState(() => report = load()),
                ),
              ],
            ),
          )
        else if (s.connectionState == ConnectionState.waiting || !s.hasData)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(50),
              child: CircularProgressIndicator(),
            ),
          )
        else if (view != _ReportView.overview)
          AdminCard(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final metric in view.metrics.entries)
                ListTile(title: Text(metric.key),
                  trailing: Text('${(s.data!['summary'] as Map)[metric.value] ?? 0}')),
              Align(alignment: Alignment.centerRight,
                child: AdminButton('Download PDF', icon: Icons.picture_as_pdf_outlined,
                  onPressed: exporting ? null : () => export(s.data!))),
            ],
          ))
        else ...[
          Builder(
            builder: (context) {
              final d = s.data!,
                  summary = d['summary'] as Map,
                  daily = (d['daily'] as List).cast<Map>();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // PARKSMART_REPORT_V13_INTEGRATED: one unified dashboard.
                  // Do not show Ticket+Photo cards/chart again underneath.
                  if (widget.souvenirDb != null) ...[
                    SouvenirSalesReportPanel(
                      db: widget.souvenirDb!,
                      start: period.start,
                      end: period.end,
                      ticketPhotoRevenueMinor:
                        (summary['revenueMinor'] as num? ?? 0).toInt(),
                      ticketPhotoOrderCount:
                        ((summary['ticketOrders'] as num? ?? 0) +
                         (summary['photoOrders'] as num? ?? 0)).toInt(),
                      ticketPhotoDaily: daily,
                    ),
                    const SizedBox(height: 18),
                  ] else ...[
                  const Text('Ticket + Photo Breakdown',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  AdminStats(children: [
                    AdminStat('Ticket + Photo Sales',
                      photoMoney(summary['revenueMinor']),
                      'Recorded sales',
                      Icons.payments_outlined),
                    AdminStat('Ticket + Photo Orders',
                      '${((summary['ticketOrders'] as num? ?? 0) + (summary['photoOrders'] as num? ?? 0)).toInt()}',
                      'Paid transactions', Icons.receipt_long_outlined),
                    AdminStat('Ticket + Photo Average',
                      photoMoney(((summary['ticketOrders'] as num? ?? 0) + (summary['photoOrders'] as num? ?? 0)) > 0
                          ? (((summary['revenueMinor'] as num? ?? 0) /
                              ((summary['ticketOrders'] as num? ?? 0) + (summary['photoOrders'] as num? ?? 0))).round()) : 0),
                      'Per transaction', Icons.trending_up_outlined),
                    AdminStat('Top Selling Product',
                      (d['topProducts'] as List?)?.isNotEmpty == true
                          ? '${(d['topProducts'] as List).first['name']}' : 'No sales yet',
                      'Highest sales value', Icons.local_offer_outlined),
                  ]),
                  const SizedBox(height: 20),
                  AdminCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Daily Ticket + Photo Purchase Value',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const SizedBox(height: 14),
                        if (daily.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(40),
                            child: Text(
                              'No confirmed purchases in this period.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        else ...[
                          SizedBox(
                            height: 230,
                            child: CustomPaint(
                              painter: SalesChart(daily),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${daily.first['day']}',
                                style: const TextStyle(fontSize: 11, color: adminMuted)),
                              if (daily.length > 2) Text('${daily[daily.length ~/ 2]['day']}',
                                style: const TextStyle(fontSize: 11, color: adminMuted)),
                              if (daily.length > 1) Text('${daily.last['day']}',
                                style: const TextStyle(fontSize: 11, color: adminMuted)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ],
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    AdminButton(exporting ? 'Exporting…' : 'Download Sales Report (PDF)',
                      icon: Icons.picture_as_pdf_outlined,
                      onPressed: !exporting ? () => export(d) : null),

                  ]),
                  const SizedBox(height: 20),
                  _table(
                    'Top 10 Ticket + Photo Products',
                    ['Product', 'Quantity', 'Purchase Value'],
                    [
                      for (final row in (d['topProducts'] as List).cast<Map>())
                        [
                          row['name'],
                          '${row['quantity']}',
                          photoMoney(row['revenueMinor']),
                        ],
                    ],
                  ),
                  const SizedBox(height: 23),
                  _table(
                    'Top 10 Attractions',
                    ['Attraction', 'Completed Check-ins'],
                    [
                      for (final row
                          in (d['topAttractions'] as List).cast<Map>())
                        [row['name'], '${row['visits']}'],
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ],
    ),
  );
  // PARKSMART_REPORT_V14_RANKING_GRID
  // Full-width responsive ranking cards, replacing the old narrow DataTable.
  Widget _table(
    String title,
    List<String> headers,
    List<List<dynamic>> rows,
  ) {
    final isAttractions = title.toLowerCase().contains('attraction');

    double score(List<dynamic> row) {
      final raw = isAttractions
          ? (row.length > 1 ? row[1] : 0)
          : (row.length > 2 ? row[2] : 0);
      final cleaned = raw.toString().replaceAll(RegExp(r'[^0-9.]'), '');
      return double.tryParse(cleaned) ?? 0;
    }

    final maxScore = rows.fold<double>(
      1,
      (current, row) => score(row) > current ? score(row) : current,
    );
    final totalCount = rows.fold<int>(
      0,
      (current, row) => current +
          (row.length > 1 ? (int.tryParse('${row[1]}') ?? 0) : 0),
    );

    return AdminCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          childrenPadding: EdgeInsets.zero,
          iconColor: adminRose,
          collapsedIconColor: adminRose,
          title: Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF9ECEB),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  isAttractions
                      ? Icons.attractions_outlined
                      : Icons.workspace_premium_outlined,
                  color: adminRose,
                  size: 23,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isAttractions
                          ? 'Ranked by completed check-ins'
                          : 'Ranked by confirmed purchase value',
                      style:
                          const TextStyle(color: adminMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          children: [
            const Divider(height: 1, color: adminBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9EEED),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '${rows.length} ${isAttractions ? 'attractions' : 'products'} ranked',
                          style: const TextStyle(
                            color: Color(0xFF9F505C),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F7F8),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          isAttractions
                              ? '$totalCount check-ins in this ranking'
                              : '$totalCount units in this ranking',
                          style: const TextStyle(
                            color: Color(0xFF59616C),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'No records in this period.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: adminMuted),
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, size) {
                        final columns = size.maxWidth >= 940 ? 2 : 1;
                        final cardWidth = columns == 2
                            ? (size.maxWidth - 14) / 2
                            : size.maxWidth;
                        return Wrap(
                          spacing: 14,
                          runSpacing: 13,
                          children: [
                            for (var i = 0; i < rows.length; i++)
                              SizedBox(
                                width: cardWidth,
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: i == 0
                                        ? const Color(0xFFFFF7F6)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: i == 0
                                          ? const Color(0xFFEAC6C4)
                                          : const Color(0xFFF0E5E4),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 36,
                                            height: 36,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: i < 3
                                                  ? const Color(0xFFF2DCDD)
                                                  : const Color(0xFFF3F1F1),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '${i + 1}',
                                              style: TextStyle(
                                                color: i < 3
                                                    ? const Color(0xFF9F505C)
                                                    : const Color(0xFF727780),
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${rows[i][0]}',
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  isAttractions
                                                      ? 'Completed check-ins'
                                                      : '${rows[i].length > 1 ? rows[i][1] : 0} units sold',
                                                  style: const TextStyle(
                                                    color: adminMuted,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            isAttractions
                                                ? '${rows[i].length > 1 ? rows[i][1] : 0}'
                                                : '${rows[i].length > 2 ? rows[i][2] : 'RM 0.00'}',
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF9F505C),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 13),
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        child: LinearProgressIndicator(
                                          value: (score(rows[i]) / maxScore)
                                              .clamp(0.0, 1.0).toDouble(),
                                          minHeight: 6,
                                          backgroundColor:
                                              const Color(0xFFF3E9E8),
                                          valueColor:
                                              const AlwaysStoppedAnimation<Color>(
                                            Color(0xFFC9828A),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SalesChart extends CustomPainter {
  final List<Map> rows;
  SalesChart(this.rows);
  @override
  void paint(Canvas canvas, Size size) {
    final maximum = rows.fold<num>(
          1,
          (n, r) =>
              (r['revenueMinor'] as num) > n ? r['revenueMinor'] as num : n,
        ),
        bottom = size.height - 22,
        step = size.width / rows.length;
    final line = Paint()
      ..color = adminBorder
      ..strokeWidth = 1;
    for (int i = 0; i < 5; i++) {
      final y = bottom * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [adminRose, Color(0xFFE7BDB1)],
      ).createShader(Offset.zero & size);
    for (int i = 0; i < rows.length; i++) {
      final height =
              ((rows[i]['revenueMinor'] as num) / maximum) * (bottom - 12),
          x = i * step + step * .15;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, bottom - height, step * .7, height),
          const Radius.circular(5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(SalesChart oldDelegate) => rows != oldDelegate.rows;
}
