import 'package:flutter/material.dart';
import '../../photos/photo_repository.dart';
import '../admin_models.dart';
import '../admin_widgets.dart';
import 'park_admin_repository.dart';
import '../../park/venue_configuration.dart';

class ParkManagementPage extends StatefulWidget {
  final ParkAdminRepository repository;
  const ParkManagementPage({super.key, required this.repository});
  @override
  State<ParkManagementPage> createState() => _ParkManagementPageState();
}

class _ParkManagementPageState extends State<ParkManagementPage> {
  late final campaigns = widget.repository.records('campaigns'),
      rewards = widget.repository.records('rewardCatalogue'),
      vouchers = widget.repository.records('rewardVouchers'),
      loyalty = widget.repository.settings('loyalty'),
      photos = widget.repository.settings('photos'),
      weather = widget.repository.settings('weather');
  String tab = 'Promotions', query = '';
  String campaignFilter = 'all';
  int page = 0;

  String _campaignState(Map<String, dynamic> row) {
    if (row['active'] != true) return 'Paused';
    final starts = adminDate(row['startsAt']);
    final ends = adminDate(row['endsAt']);
    if (starts == null || ends == null) return 'Needs review';
    final now = DateTime.now();
    if (starts.isAfter(now)) return 'Scheduled';
    if (!ends.isAfter(now)) return 'Expired';
    return 'Running';
  }
  Future<void> edit(String kind, Map<String, dynamic> data) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ParkPolicyEditor(
        repository: widget.repository,
        kind: kind,
        initial: data,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AdminHeading(
        'Promotions & Rewards',
        'Manage park offers, earning rules and visitor benefits.',
      ),
      const SizedBox(height: 23),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final section in [
            'Promotions',
            'Reward Catalogue',
            'Loyalty Rules',
            'Guest Recovery',
          ])
            ChoiceChip(
              label: Text(section),
              selected: tab == section,
              onSelected: (_) => setState(() {
                tab = section;
                query = '';
                campaignFilter = 'all';
                page = 0;
              }),
            ),
        ],
      ),
      const SizedBox(height: 22),
      if (tab == 'Promotions' || tab == 'Reward Catalogue') ...[
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                key: ValueKey(tab),
                onChanged: (v) => setState(() {
                  query = v;
                  page = 0;
                }),
                decoration: const InputDecoration(
                  hintText: 'Search name or code',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            if (tab == 'Promotions') ...[
              AdminSelect(
                value: campaignFilter,
                options: const {
                  'all': 'All Campaigns',
                  'running': 'Running',
                  'scheduled': 'Scheduled',
                  'paused': 'Paused',
                  'expired': 'Expired',
                },
                width: 160,
                onChanged: (v) => setState(() {
                  campaignFilter = v;
                  page = 0;
                }),
              ),
            ],
            AdminButton(
              tab == 'Promotions' ? 'Create Campaign' : 'Add Reward',
              icon: Icons.add,
              onPressed: () =>
                  edit(tab == 'Promotions' ? 'campaign' : 'reward', {}),
            ),
          ],
        ),
        const SizedBox(height: 20),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: tab == 'Promotions' ? campaigns : rewards,
          builder: (context, s) {
            if (s.hasError) {
              return const AdminEmpty(
                'Unable to load offers',
                'Check your connection and reopen this section.',
              );
            }
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = s.data!,
                rows =
                    all
                        .where(
                          (d) => '${d['name']} ${d['code'] ?? ''}'
                              .toLowerCase()
                              .contains(query.toLowerCase()) &&
                              (tab != 'Promotions' || campaignFilter == 'all' ||
                                  _campaignState(d).toLowerCase() == campaignFilter),
                        )
                        .toList()
                      ..sort(
                        (a, b) => (a['name'] ?? '').toString().compareTo(
                          (b['name'] ?? '').toString(),
                        ),
                      );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (tab == 'Promotions')
                  AdminStats(children: [
                    AdminStat('Running Now',
                      '${all.where((d) => _campaignState(d) == 'Running').length}',
                      'Offers accepting redemptions now', Icons.play_circle_outline),
                    AdminStat('Scheduled',
                      '${all.where((d) => _campaignState(d) == 'Scheduled').length}',
                      'Upcoming campaigns; review dates', Icons.event_outlined),
                    AdminStat('Recorded Redemptions',
                      '${all.fold<int>(0, (n, d) => n + ((d['usageCount'] as num?)?.toInt() ?? 0))}',
                      'All campaigns, not unique visitors', Icons.redeem_outlined),
                    AdminStat('Near Usage Cap',
                      '${all.where((d) { final cap = (d['totalUsageLimit'] as num?)?.toInt() ?? 0;
                         final used = (d['usageCount'] as num?)?.toInt() ?? 0;
                         return cap > 0 && used >= cap * 0.8 && _campaignState(d) == 'Running';
                      }).length}',
                      'Running promotions with 80%+ quota used', Icons.warning_amber_outlined),
                  ])
                else
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: vouchers,
                    builder: (context, result) {
                      final catalogueIds = all.map((r) => r['id']).toSet();
                      final issued = (result.data ?? const <Map<String, dynamic>>[])
                          .where((v) => catalogueIds.contains(v['rewardId'])).toList();
                      final redeemed = issued.where((v) => v['status'] == 'used').length;
                      final outstanding = issued.where((v) => v['status'] == 'available').toList();
                      final expiring = outstanding.where((v) {
                        final expiry = adminDate(v['expiresAt']);
                        return expiry != null && expiry.isAfter(DateTime.now()) &&
                          expiry.isBefore(DateTime.now().add(const Duration(days: 7)));
                      }).length;
                      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (result.hasError) const Text('Voucher performance unavailable. Check administrator access.',
                          style: TextStyle(color: adminMuted)),
                        AdminStats(children: [
                          AdminStat('Active Rewards',
                            '${all.where((r) => r['active'] == true).length}',
                            'Currently available to visitors', Icons.card_giftcard_outlined),
                          AdminStat('Vouchers Issued', '${issued.length}',
                            'Issued from this reward catalogue', Icons.confirmation_number_outlined),
                          AdminStat('Vouchers Redeemed', '$redeemed',
                            'Voucher uses recorded by the system', Icons.redeem_outlined),
                          AdminStat('Expiring in 7 Days', '$expiring',
                            'Unredeemed vouchers nearing expiry', Icons.alarm_outlined),
                        ]),
                      ]);
                    },
                  ),
                const SizedBox(height: 20),
                if (rows.isEmpty)
                  const AdminEmpty(
                    'No matching offers',
                    'Create a campaign or reward to publish a visitor benefit.',
                  ),
                if (tab == 'Reward Catalogue' && rows.isNotEmpty)
                  AdminCard(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                    child: Column(children: [
                      for (final row in rows.skip(page * 8).take(8)) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4E8E7),
                                borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.redeem_outlined, color: adminRose)),
                            const SizedBox(width: 15),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${row['name'] ?? 'Unnamed reward'}',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text('${row['benefit'] ?? ''}', maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: adminMuted, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text('${row['pointsCost'] ?? 0} points · ${row['category'] ?? 'reward'} · Valid ${row['validityDays'] ?? '—'} days',
                                  style: const TextStyle(color: adminMuted, fontSize: 11)),
                              ],
                            )),
                            const SizedBox(width: 14),
                            AdminBadge(row['active'] == true ? 'Active' : 'Inactive',
                              tone: row['active'] == true ? 'active' : 'archived'),
                            const SizedBox(width: 12),
                            IconButton(
                              tooltip: 'Edit reward',
                              icon: const Icon(Icons.edit_outlined, color: adminRose),
                              onPressed: () => edit('reward', row)),
                          ]),
                        ),
                        const Divider(height: 1),
                      ],
                    ]),
                  ),
                if (tab == 'Promotions')
                  for (final row in rows.skip(page * 8).take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: AdminCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 16,
                            runSpacing: 12,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.redeem_outlined,
                                    color: adminRose,
                                    size: 34,
                                  ),
                                  const SizedBox(width: 15),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 320,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          row['name'] as String,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          tab == 'Promotions'
                                              ? row['code'] as String
                                              : '${row['pointsCost']} points • ${row['category']}',
                                          style: const TextStyle(
                                            color: adminMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              AdminBadge(
                                tab == 'Promotions'
                                    ? _campaignState(row)
                                    : (row['active'] == true ? 'Active' : 'Inactive'),
                                tone: (tab == 'Promotions'
                                    ? _campaignState(row) == 'Running'
                                    : row['active'] == true) ? 'active' : 'archived',
                              ),
                              AdminButton(
                                'Edit Details',
                                outlined: true,
                                icon: Icons.edit_outlined,
                                onPressed: () => edit(
                                  tab == 'Promotions' ? 'campaign' : 'reward',
                                  row,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 28),
                          Text(
                            tab == 'Promotions'
                                ? '${row['type'] == 'percent' ? '${row['value']}%' : photoMoney(row['value'] as num)} off • ${adminDateLabel(adminDate(row['startsAt']))} – ${adminDateLabel(adminDate(row['endsAt']))}'
                                : '${row['benefit']} • Valid for ${row['validityDays']} days',
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (tab == 'Promotions')
                            Padding(
                              padding: const EdgeInsets.only(top: 9),
                              child: Text(
                                '${(row['scopes'] as List? ?? []).join(' & ')} • '
                                '${row['usageCount'] ?? 0} redemptions • '
                                'Max ${row['perUserLimit'] ?? 1} per visitor • '
                                'Min spend ${photoMoney((row['minimumMinor'] as num?) ?? 0)} • '
                                '${(row['totalUsageLimit'] as num? ?? 0) == 0 ? 'No total cap' : 'Total cap ${row['totalUsageLimit']}'}',
                                style: const TextStyle(
                                  color: adminMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${rows.isEmpty ? 0 : page * 8 + 1}–${(page * 8 + 8).clamp(0, rows.length)} of ${rows.length}',
                    ),
                    IconButton(
                      onPressed: page > 0 ? () => setState(() => page--) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      onPressed: (page + 1) * 8 < rows.length
                          ? () => setState(() => page++)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ] else
        StreamBuilder<Map<String, dynamic>>(
          stream: tab == 'Loyalty Rules' ? loyalty : weather,
          builder: (context, s) {
            if (s.hasError) {
              return const AdminEmpty(
                'Unable to load park settings',
                'Please reopen this section.',
              );
            }
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final d = s.data!,
                kind = tab == 'Loyalty Rules' ? 'loyalty' : 'weather';
            final entries = kind == 'loyalty'
                ? {
                    'Purchase earning rate':
                        '${d['purchasePointsPerRinggit'] ?? 1} pts / RM 1',
                    'Attraction check-in':
                        '+${d['ridePoints'] ?? 10} pts / check-in',
                    'Missed reservations': d['noShowEnabled'] == true
                        ? '${d['noShowPenalty'] ?? 0} pts deducted from the ${d['noShowThreshold'] ?? 2}nd missed booking'
                        : 'No penalty',
                  }
                : {
                    'Rain benefit': d['enabled'] == true ? 'Active' : 'Paused',
                    'Rain threshold': '${d['rainThresholdMm'] ?? 2} mm',
                    'Voucher': d['voucherBenefit'] ?? 'Not set',
                    'Validity': '${d['validityDays'] ?? 30} days',
                  };
            return AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        kind == 'weather'
                            ? Icons.cloud_outlined
                            : Icons.stars_outlined,
                        color: adminRose,
                        size: 40,
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Text(
                          tab,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      AdminButton(
                        'Edit Settings',
                        icon: Icons.tune,
                        outlined: true,
                        onPressed: () => edit(kind, d),
                      ),
                    ],
                  ),
                  const Divider(height: 34),
                  Wrap(
                    spacing: 14, runSpacing: 14,
                    children: [
                      for (final entry in entries.entries)
                        SizedBox(width: 290, child: Container(
                          constraints: const BoxConstraints(minHeight: 104),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCF7F5),
                            border: Border.all(color: adminBorder),
                            borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry.key, style: const TextStyle(color: adminMuted, fontSize: 12)),
                              const SizedBox(height: 8),
                              Text('${entry.value}', style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        )),
                    ],
                  ),
                  if (kind == 'weather') ...[
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AdminButton(
                        'Refresh Weather',
                        outlined: true,
                        icon: Icons.refresh,
                        onPressed: d['enabled'] == true
                            ? () async {
                                try {
                                  final result = await widget.repository
                                      .request('refreshWeather', {});
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          result['raining'] == true
                                              ? 'Rain threshold met. Weather benefit is available.'
                                              : 'Weather updated.',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(photoError(e))),
                                    );
                                  }
                                }
                              }
                            : null,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
    ],
  );
}

class ParkPolicyEditor extends StatefulWidget {
  final ParkAdminRepository repository;
  final String kind;
  final Map<String, dynamic> initial;
  const ParkPolicyEditor({
    super.key,
    required this.repository,
    required this.kind,
    required this.initial,
  });
  @override
  State<ParkPolicyEditor> createState() => _ParkPolicyEditorState();
}

class _ParkPolicyEditorState extends State<ParkPolicyEditor> {
  final fields = <String, TextEditingController>{},
      form = GlobalKey<FormState>();
  late final d = Map<String, dynamic>.from(widget.initial);
  late String type = d['type'] as String? ?? 'percent',
      category = d['category'] as String? ?? 'shopping';
  late bool active = d['active'] != false,
      public = d['public'] != false,
      allowPoints = d['allowPoints'] != false,
      enabled = d['enabled'] == true,
      noShow = d['noShowEnabled'] == true;
  late final scopes = (d['scopes'] as List? ?? ['tickets'])
      .cast<String>()
      .toSet();
  late DateTime
  start = adminDate(d['startsAt']) ?? DateTime.now(),
  end = adminDate(d['endsAt']) ?? DateTime.now().add(const Duration(days: 30));
  bool busy = false;
  String? error;
  String get kind => widget.kind;
  TextEditingController controller(
    String key,
    Object? fallback, {
    bool money = false,
    bool lines = false,
  }) => fields.putIfAbsent(
    key,
    () => TextEditingController(
      text: lines
          ? (d[key] is List
              ? (d[key] as List).join('\n')
              : (d[key] ?? fallback)?.toString() ?? '')
          : money
          ? (((d[key] ?? fallback) as num) / 100).toStringAsFixed(2)
          : (d[key] ?? fallback)?.toString() ?? '',
    ),
  );
  Widget input(
    String key,
    String label, {
    Object? value = '',
    bool number = false,
    bool money = false,
    int lines = 1,
    String? helper,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 17),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label, style: const TextStyle(fontSize: 12.5,
        fontWeight: FontWeight.w700, color: Color(0xFF27313A))),
      const SizedBox(height: 7),
      TextFormField(
      controller: controller(key, value, money: money, lines: lines > 1),
      enabled: !busy,
      maxLines: lines,
      keyboardType: number || money
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      style: const TextStyle(fontSize: 15, height: 1.3),
      decoration: InputDecoration(
        hintText: label,
        hintStyle: const TextStyle(color: Color(0xFFA5A1A1), fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        prefixText: money ? 'RM ' : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE4D4D1))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: adminRose, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      ),
      validator: (v) {
        if (kind == 'campaign' && key == 'description') {
          final text = (v ?? '').trim();
          if (text.length < 12) return 'Write the public conditions (minimum 12 characters).';
          if (text.length > 600) return 'Maximum 600 characters.';
        }
        if (kind == 'reward' && (key == 'terms' || key == 'instructions')) {
          final rows = (v ?? '').split('\n').map((e) => e.trim())
              .where((e) => e.isNotEmpty).toList();
          if (rows.isEmpty) return 'Add at least one clear line.';
          final maxLines = key == 'terms' ? 10 : 6;
          if (rows.length > maxLines || rows.any((e) => e.length > 300)) {
            return 'Maximum $maxLines lines, 300 characters per line.';
          }
        }
        if ([
          'latitude',
          'longitude',
          'kioskLatitude',
          'kioskLongitude',
          'description',
          'subtitle',
          'terms',
          'instructions',
        ].contains(key)) {
          return null;
        }
        if (v == null || v.trim().isEmpty) return 'Complete this field.';
        if ((number || money) && num.tryParse(v) == null) {
          return 'Enter a number.';
        }
        if (kind == 'campaign') {
          if (key == 'description') {
            if (v.trim().length < 12) return 'Explain the offer and its terms (at least 12 characters).';
            if (v.trim().length > 600) return 'Terms must be within 600 characters.';
          }
          if (key == 'code' &&
              !RegExp(r'^[a-zA-Z0-9_-]{2,32}$').hasMatch(v.trim())) {
            return 'Use 2–32 letters, numbers, _ or -.';
          }
          if (key == 'name' && v.trim().length < 2) {
            return 'Use at least 2 characters.';
          }
          if (key == 'value' && type == 'percent') {
            final n = int.tryParse(v);
            if (n == null || n < 1 || n > 100) return 'Choose 1–100%.';
          }
          if (key == 'perUserLimit') {
            final n = int.tryParse(v);
            if (n == null || n < 1 || n > 100) return 'Choose 1–100.';
          }
          if (key == 'totalUsageLimit') {
            final n = int.tryParse(v);
            if (n == null || n < 0 || n > 1000000) return 'Choose 0–1,000,000.';
          }
          if (money) {
            if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(v.trim())) {
              return 'Use RM with up to 2 decimal places.';
            }
            final amount = double.tryParse(v.trim());
            if (amount == null || amount < 0 || amount > 1000000 ||
                (key == 'value' && amount == 0)) {
              return 'Enter an amount from RM0 to RM1,000,000.';
            }
          }
        }
        if (kind == 'reward') {
          final n = int.tryParse(v.trim());
          if (key == 'pointsCost' && (n == null || n < 1 || n > 1000000)) return 'Choose 1–1,000,000 points.';
          if (key == 'validityDays' && (n == null || n < 1 || n > 365)) return 'Choose 1–365 days.';
          if (key == 'sortOrder' && (n == null || n < 0 || n > 10000)) return 'Choose 0–10,000.';
        }
        if (kind == 'loyalty' && key == 'purchasePointsPerRinggit' && ((int.tryParse(v.trim()) ?? -1) < 0 || (int.tryParse(v.trim()) ?? 101) > 100)) return 'Choose 0–100 points per RM.';
        if (kind == 'loyalty' && key == 'ridePoints' && ((int.tryParse(v.trim()) ?? -1) < 0 || (int.tryParse(v.trim()) ?? 10001) > 10000)) return 'Choose 0–10,000 points.';
        if (key == 'noShowThreshold') {
          final count = int.tryParse(v);
          if (count == null || count < 2 || count > 20) {
            return 'Enter a whole number from 2 to 20.';
          }
        }
        return null;
      },
      ),
      if (helper != null) ...[
        const SizedBox(height: 5),
        Text(helper, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: adminMuted)),
      ],
    ]),
  );
  Future<void> date(bool first) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: first ? start : end,
      firstDate: first ? DateTime(2020) : DateTime(start.year, start.month, start.day),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (selected != null) {
      setState(() {
        if (first) {
          start = selected;
          if (!end.isAfter(start)) {
            end = DateTime(selected.year, selected.month, selected.day + 1, 23, 59);
          }
        } else {
          end = DateTime(selected.year, selected.month, selected.day, 23, 59);
        }
      });
    }
  }

  dynamic value(
    String key, {
    bool money = false,
    bool decimal = false,
    bool optional = false,
  }) {
    final raw = fields[key]?.text.trim() ?? '';
    if (optional && raw.isEmpty) return null;
    if (money) return (double.parse(raw) * 100).round();
    if (decimal) return double.parse(raw);
    return int.parse(raw);
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (kind == 'campaign') {
      if (scopes.isEmpty) {
        setState(() => error = 'Select at least one eligible purchase type.');
        return;
      }
      if (!end.isAfter(start)) {
        setState(() => error = 'End date must be later than the start date.');
        return;
      }
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final payload = <String, dynamic>{};
      for (final entry in fields.entries) {
        payload[entry.key] = entry.value.text.trim();
      }
      String action;
      if (kind == 'campaign') {
        action = 'saveCampaign';
        payload.addAll({
          'type': type,
          'value': value('value', money: type == 'fixed'),
          'minimumMinor': value('minimumMinor', money: true),
          'maximumDiscountMinor': value('maximumDiscountMinor', money: true),
          'perUserLimit': value('perUserLimit'),
          'totalUsageLimit': value('totalUsageLimit'),
          'startsAt': start.toUtc().toIso8601String(),
          'endsAt': end.toUtc().toIso8601String(),
          'active': active,
          'public': public,
          'allowPoints': allowPoints,
          'scopes': scopes.toList(),
        });
      } else if (kind == 'reward') {
        action = 'saveReward';
        payload.addAll({
          'id': ?d['id'],
          'pointsCost': value('pointsCost'),
          'validityDays': value('validityDays'),
          'sortOrder': value('sortOrder'),
          'category': category,
          'active': active,
          'terms': (payload['terms'] as String)
              .split('\n')
              .where((s) => s.trim().isNotEmpty)
              .toList(),
          'instructions': (payload['instructions'] as String)
              .split('\n')
              .where((s) => s.trim().isNotEmpty)
              .toList(),
        });
      } else if (kind == 'loyalty') {
        action = 'saveLoyalty';
        for (final key in [
          'purchasePointsPerRinggit',
          'ridePoints',
          'noShowPenalty',
          'noShowThreshold',
        ]) {
          payload[key] = value(key);
        }
        payload['noShowEnabled'] = noShow;
      } else if (kind == 'photos') {
        action = 'savePhotoSettings';
        for (final key in [
          'digitalPriceMinor',
          'printPriceMinor',
          'bundlePriceMinor',
          'largePrintSurchargeMinor',
        ]) {
          payload[key] = value(key, money: true);
        }
        for (final key in ['kioskLatitude', 'kioskLongitude']) {
          payload[key] = value(key, decimal: true, optional: true);
        }
      } else {
        action = 'saveWeather';
        payload.addAll({
          'enabled': enabled,
          'parkName': fields['parkName']?.text.trim() ?? (d['parkName'] ?? VenueConfiguration.name),
          'voucherBenefit': fields['voucherBenefit']?.text.trim() ?? (d['voucherBenefit'] ?? 'Rainy-day park benefit'),
          'latitude': value('latitude', decimal: true, optional: true),
          'longitude': value('longitude', decimal: true, optional: true),
          'rainThresholdMm': value('rainThresholdMm', decimal: true),
          'validityDays': value('validityDays'),
        });
      }
      await widget.repository.request(action, payload);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? 'Review the numbers in this form.'
              : photoError(e),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }


  Widget _policyPanel(String title, IconData icon, List<Widget> children) =>
    Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCFB),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFFE7D9D7)),
        boxShadow: const [BoxShadow(color: Color(0x100F151C),
          blurRadius: 18, offset: Offset(0, 5)),],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 34, height: 34,
            decoration: BoxDecoration(color: const Color(0xFFF6EBE9),
              borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: adminRose)),
          const SizedBox(width: 11),
          Expanded(child: Text(title, style: const TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 17),
        ...children,
      ]),
    );

  Widget _policyColumns(Widget left, Widget right) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 750) return Column(children: [
        left, const SizedBox(height: 15), right]);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: left), const SizedBox(width: 16), Expanded(child: right)]);
    },
  );

  Widget _policyToggle(String label, bool current, ValueChanged<bool> update) =>
    SwitchListTile.adaptive(
      dense: true,
      contentPadding: EdgeInsets.zero,
      activeTrackColor: adminRose,
      title: Text(label, style: const TextStyle(fontSize: 13,
        fontWeight: FontWeight.w600)),
      value: current,
      onChanged: busy ? null : update,
    );

  List<Widget> _editorSections() {
    if (kind == 'campaign') return [
      _policyColumns(
        _policyPanel('Campaign details', Icons.local_offer_outlined, [
          input('name', 'Campaign name'),
          input('code', 'Promo code'),
          input('description', 'Terms & conditions', lines: 4),
        ]),
        _policyPanel('Discount & limits', Icons.percent_outlined, [
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Discount type'),
            items: const [
              DropdownMenuItem(value: 'percent', child: Text('Percentage (%)')),
              DropdownMenuItem(value: 'fixed', child: Text('Fixed amount (RM)')),
            ],
            onChanged: busy ? null : (v) => setState(() {
              type = v!; fields.remove('value')?.dispose();
            }),
          ),
          const SizedBox(height: 15),
          input('value', type == 'percent' ? 'Discount (%)' : 'Discount (RM)',
            number: type == 'percent', money: type == 'fixed', value: 10),
          input('minimumMinor', 'Minimum spend (RM)', money: true, value: 0),
          input('maximumDiscountMinor', 'Maximum discount (RM)', money: true, value: 0),
          Row(children: [
            Expanded(child: input('perUserLimit', 'Per visitor', number: true, value: 1)),
            const SizedBox(width: 12),
            Expanded(child: input('totalUsageLimit', 'Total uses', number: true, value: 0)),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      _policyPanel('Schedule & visibility', Icons.event_available_outlined, [
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: busy ? null : () => date(true),
            icon: const Icon(Icons.calendar_today_outlined, size: 17),
            label: Text('Start: ${adminDateLabel(start)}'))),
          const SizedBox(width: 12),
          Expanded(child: OutlinedButton.icon(
            onPressed: busy ? null : () => date(false),
            icon: const Icon(Icons.event_outlined, size: 17),
            label: Text('End: ${adminDateLabel(end)}'))),
        ]),
        const SizedBox(height: 14),
        const Text('Eligible purchases', style: TextStyle(fontWeight: FontWeight.w600)),
        Wrap(spacing: 12, runSpacing: 8, children: [
          for (final scope in ['tickets','photos']) FilterChip(
            label: Text(scope == 'tickets' ? 'Tickets' : 'Photos'),
            selected: scopes.contains(scope),
            onSelected: busy ? null : (v) => setState(() {
              v ? scopes.add(scope) : scopes.remove(scope);
            })),
        ]),
        _policyToggle('Active', active, (v) => setState(() => active = v)),
        _policyToggle('Show to visitors', public, (v) => setState(() => public = v)),
        _policyToggle('Can combine with loyalty points', allowPoints,
          (v) => setState(() => allowPoints = v)),
      ]),
    ];
    if (kind == 'reward') return [
      _policyColumns(
        _policyPanel('Reward details', Icons.card_giftcard_outlined, [
          input('name', 'Reward name'),
          input('subtitle', 'Short subtitle'),
          input('benefit', 'What guests receive', lines: 2),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [for (final c in ['shopping','dining','photo'])
              DropdownMenuItem(value: c, child: Text(titleCase(c)))],
            onChanged: busy ? null : (v) => setState(() => category = v!),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: input('pointsCost', 'Points required', number: true, value: 100)),
            const SizedBox(width: 12),
            Expanded(child: input('validityDays', 'Valid for (days)', number: true, value: 30)),
          ]),
          _policyToggle('Available to redeem', active,
            (v) => setState(() => active = v)),
        ]),
        _policyPanel('Redemption', Icons.verified_outlined, [
          input('terms', 'Terms & conditions', lines: 5),
          input('instructions', 'How to use', lines: 4),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Advanced', style: TextStyle(fontSize: 13)),
            children: [input('sortOrder','Display order',number: true,value:0)],
          ),
        ]),
      ),
    ];
    if (kind == 'loyalty') return [
      _policyColumns(
        _policyPanel('Earn points', Icons.stars_outlined, [
          input('purchasePointsPerRinggit', 'Points per RM 1', number: true, value: 1),
          input('ridePoints', 'Points per ride check-in', number: true, value: 10),
        ]),
        _policyPanel('Missed reservations', Icons.event_busy_outlined, [
          _policyToggle('Enable penalty', noShow,
            (v) => setState(() => noShow = v)),
          input('noShowThreshold', 'Penalty begins at missed visit #',
            number: true, value: 2),
          input('noShowPenalty', 'Points deducted per no-show',
            number: true, value: 10),
        ]),
      ),
    ];
    if (kind == 'photos') return [
      _policyColumns(
        _policyPanel('Photo prices', Icons.photo_camera_outlined, [
          input('digitalPriceMinor', 'Digital photo (RM)', money: true, value: 2500),
          input('printPriceMinor', 'Photo print (RM)', money: true, value: 3500),
          input('bundlePriceMinor', 'Digital + print (RM)', money: true, value: 5000),
          input('largePrintSurchargeMinor', 'Large print upgrade (RM)',
            money: true, value: 1000),
        ]),
        _policyPanel('Collection kiosk', Icons.print_outlined, [
          input('kioskName', 'Kiosk name', value: 'Park Photo Kiosk'),
          input('kioskLatitude', 'Latitude', number: true),
          input('kioskLongitude', 'Longitude', number: true),
        ]),
      ),
    ];
    return [
      _policyColumns(
        _policyPanel('Weather trigger', Icons.cloud_outlined, [
          _policyToggle('Enable rain compensation', enabled,
            (v) => setState(() => enabled = v)),
          input('rainThresholdMm', 'Rain threshold (mm)', number: true, value: 2),
          ExpansionTile(tilePadding: EdgeInsets.zero,
            title: const Text('Park location', style: TextStyle(fontSize: 13)),
            children: [
              input('parkName', 'Park name', value: VenueConfiguration.name),
              input('latitude', 'Latitude', number: true,
                value: VenueConfiguration.latitude),
              input('longitude', 'Longitude', number: true,
                value: VenueConfiguration.longitude),
            ]),
        ]),
        _policyPanel('Voucher benefit', Icons.redeem_outlined, [
          input('voucherBenefit', 'Reward and redemption details', lines: 3,
            value: 'Rainy-day park benefit'),
          input('validityDays', 'Valid for (days)', number: true, value: 30),
          const Text('Rain-based vouchers only',
            style: TextStyle(fontSize: 11, color: adminMuted)),
        ]),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Dialog(
      backgroundColor: const Color(0xFFF4E8E7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFE8D9D7))),
      elevation: 24,
      shadowColor: const Color(0x770F151C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 990,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 24, 20),
              child: Row(
                children: [
                  Container(width: 48, height: 48,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .65),
                      borderRadius: BorderRadius.circular(15)),
                    child: Icon(kind == 'campaign' ? Icons.local_offer_outlined
                        : kind == 'reward' ? Icons.card_giftcard_outlined
                        : kind == 'loyalty' ? Icons.stars_outlined
                        : Icons.cloud_outlined, color: adminRose)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      kind == 'campaign'
                          ? (d.isEmpty ? 'Create Promotion' : 'Edit Promotion')
                          : kind == 'reward'
                          ? (d.isEmpty ? 'Add Reward' : 'Edit Reward')
                          : kind == 'loyalty'
                          ? 'Edit Loyalty Settings'
                          : kind == 'photos'
                          ? 'Photo Prices & Kiosk'
                          : 'Guest Recovery Settings',
                      style: const TextStyle(
                        fontSize: 24,
                        letterSpacing: -.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: form,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ..._editorSections(),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: busy ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 14),
                  AdminButton(
                    busy ? 'Saving…' : (d.isEmpty ? 'Create' : 'Save Changes'),
                    onPressed: busy ? null : save,
                    icon: Icons.check,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
