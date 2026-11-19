import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../photos/photo_repository.dart';
import '../admin_models.dart';
import '../admin_widgets.dart';
import 'park_admin_repository.dart';

Future<Uint8List> buildParkReportPdf(Map<String, dynamic> report) async {
  final document = pw.Document(),
      summary = Map<String, dynamic>.from(report['summary']);
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Text(
          'THEME PARK',
          style: pw.TextStyle(fontSize: 25, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Sales & Attendance Report',
          style: const pw.TextStyle(fontSize: 18),
        ),
        pw.Text('${report['start']} to ${report['end']}'),
        pw.SizedBox(height: 22),
        pw.TableHelper.fromTextArray(
          headers: ['Measure', 'Total'],
          data: [
            ['Confirmed purchase value', photoMoney(summary['revenueMinor'])],
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
          'Daily Sales',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: ['Park Day', 'Orders', 'Amount (MYR)'],
          data: [
            for (final row in (report['daily'] as List).cast<Map>())
              [row['day'], '${row['orders']}', photoMoney(row['revenueMinor'])],
          ],
        ),
        pw.SizedBox(height: 22),
        pw.Text(
          'Top 10 Products',
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

class ParkReportsPage extends StatefulWidget {
  final ParkAdminRepository repository;
  const ParkReportsPage({super.key, required this.repository, this.embedded = false});
  final bool embedded;
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
  late Future<Map<String, dynamic>> report = load();
  bool exporting = false;
  Future<Map<String, dynamic>> load() => widget.repository.request('report', {
    'start': period.start.toUtc().toIso8601String(),
    'end': period.end.add(const Duration(days: 1)).toUtc().toIso8601String(),
  });
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
      await FilePicker.saveFile(
        fileName:
            'ThemePark-Report-${period.start.toIso8601String().substring(0, 10)}.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: await buildParkReportPdf(data),
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
          'Sales trends and best-selling products.',
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Icon(Icons.calendar_month_outlined, color: adminRose, size: 18),
            const SizedBox(width: 8),
            Text('${adminDateLabel(period.start)} – ${adminDateLabel(period.end)}',
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
        else if (!s.hasData)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(50),
              child: CircularProgressIndicator(),
            ),
          )
        else ...[
          Builder(
            builder: (context) {
              final d = s.data!,
                  summary = d['summary'] as Map,
                  daily = (d['daily'] as List).cast<Map>();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminStats(children: [
                    AdminStat('Confirmed Sales',
                      photoMoney(summary['revenueMinor']),
                      'Recorded sales',
                      Icons.payments_outlined),
                    AdminStat('Paid Orders',
                      '${((summary['ticketOrders'] as num? ?? 0) + (summary['photoOrders'] as num? ?? 0)).toInt()}',
                      'Paid transactions', Icons.receipt_long_outlined),
                    AdminStat('Average Order Value',
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
                          'Daily Purchase Value',
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
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    AdminButton(exporting ? 'Exporting…' : 'Download Sales Report (PDF)',
                      icon: Icons.picture_as_pdf_outlined,
                      onPressed: !exporting ? () => export(d) : null),

                  ]),
                  const SizedBox(height: 20),
                  _table(
                    'Top 10 Products',
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
  Widget _table(
    String title,
    List<String> headers,
    List<List<dynamic>> rows,
  ) => AdminCard(
    padding: EdgeInsets.zero,
    child: ExpansionTile(
      initiallyExpanded: false,
      iconColor: adminRose,
      collapsedIconColor: adminRose,
      tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      title: Text(title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),

      children: [
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No records in this period.'),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [for (final header in headers) DataColumn(label: Text(header))],
              rows: [
                for (final row in rows)
                  DataRow(cells: [for (final cell in row) DataCell(Text('$cell'))]),
              ],
            ),
          ),
      ],
    ),
  );
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
