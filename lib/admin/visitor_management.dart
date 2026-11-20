import 'dart:async';
import 'package:flutter/material.dart';
import '../visitor/models/tickets.dart';
import 'admin_models.dart';
import 'admin_store.dart';
import 'admin_repository.dart';
import 'admin_widgets.dart';
import 'visitor_profile.dart';
import '../visitor/models/membership_policy.dart';
import 'membership_rules_dialog.dart';
import 'visitor_account_report.dart';
import 'visitor_refund_review.dart';

class _VisitorKpiCard extends StatelessWidget {
  final String title, value, detail, helper;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  const _VisitorKpiCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.helper,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBF9),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE9E1DF)),
    ),
    child: SizedBox(height: 128, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text(title,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF625450),
              fontSize: 15, fontWeight: FontWeight.w700))),
          const SizedBox(width: 7),
          Container(width: 38, height: 38,
            decoration: BoxDecoration(color: accent.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: accent, size: 21)),
        ]),
        const SizedBox(height: 8),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(value, maxLines: 1,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800,
              color: Color(0xFF312B2D)))),
        const Spacer(),
        Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF4A3738),
            fontSize: 12, fontWeight: FontWeight.w600)),
        if (helper.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(helper, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF7C6D6A), fontSize: 11)),
        ],
      ],
    )),
  ));
}

class VisitorManagement extends StatefulWidget {
  final AdminStore store;
  final ValueChanged<AdminVisitor> onOpen;
  final String initialQuery;
  const VisitorManagement({
    super.key,
    required this.store,
    required this.onOpen,
    this.initialQuery = '',
  });
  @override
  State<VisitorManagement> createState() => _VisitorManagementState();
}

class _VisitorManagementState extends State<VisitorManagement> {
  late final searchText = TextEditingController(text: widget.initialQuery);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanRefunds());
    refundTimer = Timer.periodic(const Duration(minutes: 15), (_) => _scanRefunds());
  }

  Future<void> _scanRefunds() async {
    if (!mounted || isCheckingRefunds) return;
    final repository = widget.store.repository;
    if (repository is! FirebaseAdminRepository) return;
    setState(() => isCheckingRefunds = true);
    try {
      final count = await VisitorRefundReviewService(repository).scanAndFlag();
      if (mounted) setState(() {
        refundScanMessage = count > 0
          ? '$count visitor account(s) added to the review queue for repeated confirmed refunds.'
          : 'Refund pattern check completed. No new accounts need review.';
      });
    } catch (_) {
      if (mounted) setState(() => refundScanMessage =
        'Refund pattern check could not run. Review permissions or connection.');
    } finally {
      if (mounted) setState(() => isCheckingRefunds = false);
    }
  }

  @override
  void dispose() {
    refundTimer?.cancel();
    searchText.dispose();
    super.dispose();
  }

  late String query = widget.initialQuery;
  String status = 'all', membership = 'all', section = 'all';
  String overviewFilter = 'all';
  final resultsAnchor = GlobalKey();
  void showVisitors(String filter) {
    _change(() {
      overviewFilter = filter;
      section = filter == 'review' ? 'review' : 'all';
      status = 'all';
      membership = 'all';
      selected.clear();
      searchText.clear();
      query = '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = resultsAnchor.currentContext;
      if (target != null && mounted) {
        Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut, alignment: .08);
      }
    });
  }
  Timer? refundTimer;
  bool isCheckingRefunds = false;
  String? refundScanMessage;
  int page = 0, perPage = 10;
  bool ascending = true;
  String sort = 'name';
  final Set<String> selected = {};
  List<AdminVisitor> get filtered {
    final list = widget.store.visitors.where((v) {
      // The status dropdown and the Archived tab must agree. Previously
      // 'All Visitors' excluded archived records even after selecting Archived
      // in the status dropdown, producing an empty list.
      final archivedOnly = section == 'archived' ||
          (section == 'all' && status == 'archived');
      if ((v.status == 'archived') != archivedOnly) return false;
      if (section == 'review' && !(v.watchlisted || v.risk != 'normal')) return false;
      if (overviewFilter == 'new') {
        final joined = v.joined?.toUtc().add(const Duration(hours: 8));
        final now = DateTime.now().toUtc().add(const Duration(hours: 8));
        if (joined == null || joined.year != now.year || joined.month != now.month) return false;
      }
      if (overviewFilter == 'active') {
        final from = DateTime.now().subtract(const Duration(days: 30));
        final active = widget.store.sessions.any((s) {
          final at = adminDate(s.data['lastSeenAt']) ?? s.at;
          return s.ownerUid == v.id && at != null && !at.isBefore(from);
        });
        if (!active) return false;
      }
      if (status != 'all' && v.status != status) return false;
      if (membership != 'all' && v.displayMembershipKey != membership) {
        return false;
      }
      final text =
          '${v.name} ${v.email} ${v.phone} ${v.id} ${visitorReference(v.id)}'
              .toLowerCase();
      return text.contains(query.toLowerCase().trim());
    }).toList();
    list.sort((a, b) {
      final result = switch (sort) {
        'joined' => (a.joined ?? DateTime(1970)).compareTo(
            b.joined ?? DateTime(1970)),
        'membership' => (a.lifetimeEarnedPoints ?? -1).compareTo(
            b.lifetimeEarnedPoints ?? -1),
        'spent' => _visitorSpend(a).compareTo(_visitorSpend(b)),
        _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      };
      return ascending ? result : -result;
    });
    return list;
  }

  void _change(VoidCallback action) => setState(() {
    action();
    page = 0;
  });

  List<TicketOrder> _completedOrders(AdminVisitor v) => widget.store.orders
      .where((order) => order.status == 'completed' && order.ownerUid == v.id)
      .toList();

  int _visitorSpend(AdminVisitor v) => _completedOrders(v)
      .fold<int>(0, (sum, order) => sum + order.totalMinor);

  Future<void> _editMembershipRules() async {
    var foodRewards = <Map<String, dynamic>>[];
    try {
      final repository = widget.store.repository.parkRepository;
      if (repository != null) {
        final rewards = await repository.records('rewardCatalogue').first.timeout(const Duration(seconds: 5));
        foodRewards = rewards.where((r) =>
            r['active'] == true && r['id'] is String).toList();
      }
    } catch (_) {
      // Keep membership configuration available if the catalogue cannot load.
    }
    if (!mounted) return;
    final policy = await showDialog<MembershipPolicy>(
      context: context,
      builder: (_) => MembershipRulesDialog(
        current: widget.store.membershipPolicy, foodRewards: foodRewards),
    );
    if (policy == null || !mounted) return;
    final success = await widget.store.perform(
      () => widget.store.repository.saveMembershipPolicy(policy),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success
          ? 'Membership settings saved. Visitor accounts will update automatically.'
          : (widget.store.error?.toLowerCase().contains('permission') == true
              ? 'Membership settings are blocked by Firestore security rules. Your role may be correct; the live membership rules must be updated.'
              : widget.store.error ?? 'Could not save membership settings. Please try again.')),
    ));
  }

  Future<void> _status(List<String> ids, String next) async {
    final reason = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          next == 'active'
              ? 'Activate visitor accounts'
              : next == 'archived'
              ? 'Archive visitor accounts'
              : 'Suspend visitor accounts',
        ),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                next == 'archived'
                    ? 'Archive ${ids.length} selected account(s)? Records and bookings are kept. You can restore access from the Archived filter.'
                    : next == 'active'
                    ? 'Restore visitor-app access for ${ids.length} selected account(s)?'
                    : 'Suspend visitor-app access for ${ids.length} selected account(s)? Existing records and bookings are kept.',
              ),
              const SizedBox(height: 18),
              TextField(
                controller: reason,
                maxLength: 300,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Add an account-management reason',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          AdminButton(
            next == 'active'
                ? 'Activate'
                : next == 'archived'
                ? 'Archive'
                : 'Suspend',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    final text = reason.text;
    reason.dispose();
    if (result != true || !mounted) return;
    if (next != 'active' && text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter a reason before restricting an account.')));
      return;
    }
    final success = await widget.store.perform(
      () => widget.store.repository.setVisitorStatus(ids, next, text),
    );
    if (success && mounted) {
      setState(() => selected.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Visitor account status updated.')),
      );
    }
  }

  Future<void> _watchlist(List<AdminVisitor> visitors, bool enabled) async {
    final done = await widget.store.perform(
      () => widget.store.repository.setWatchlist(visitors, enabled),
    );
    if (done && mounted) {
      setState(() => selected.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Visitors added to the watchlist.'
                : 'Visitors removed from the watchlist.',
          ),
        ),
      );
    }
  }

  void _openAccountReport() {
    final report = VisitorAccountReport.calculate(
      widget.store.visitors, widget.store.sessions, DateTime.now(),
    );
    showDialog<void>(context: context,
      builder: (_) => VisitorAccountReportDialog(report: report));
  }

  Widget _visitorOverview(VisitorAccountReport report) {
    final cards = <Widget>[
      _VisitorKpiCard(title: 'Total Visitors',
        value: '${report.registered}', detail: 'Registered accounts',
        helper: '', onTap: () => showVisitors('all'),
        icon: Icons.groups_outlined, accent: const Color(0xFFAA7475)),
      _VisitorKpiCard(title: 'New This Month',
        value: '${report.joinedThisMonth}', detail: 'Joined this month',
        helper: '', onTap: () => showVisitors('new'),
        icon: Icons.person_add_alt_outlined, accent: const Color(0xFF6883A1)),
      _VisitorKpiCard(title: 'Active in 30 Days',
        value: report.hasActivityRecords ? '${report.active30Days}' : '—',
        detail: 'App activity in the past 30 days',
        helper: report.hasActivityRecords ? '' : 'Activity not recorded',
        onTap: () => showVisitors('active'),
        icon: Icons.devices_outlined, accent: const Color(0xFF608776)),
      _VisitorKpiCard(title: 'Accounts to Review',
        value: '${report.flagged}', detail: 'Waiting for account review',
        helper: '', onTap: () => showVisitors('review'),
        icon: Icons.shield_outlined, accent: const Color(0xFFA4814A)),
    ];
    return LayoutBuilder(builder: (context, box) {
      final columns = box.maxWidth >= 1080 ? 4 : box.maxWidth >= 580 ? 2 : 1;
      const gap = 12.0;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final card in cards) SizedBox(
          width: (box.maxWidth - gap * (columns - 1)) / columns, child: card),
      ]);
    });
  }

  Widget _sectionChoice(String label, String key, IconData icon) =>
      ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 15), const SizedBox(width: 5), Text(label)]),
        selected: section == key,
        selectedColor: const Color(0xFFE7CBC7),
        backgroundColor: const Color(0xFFF9F2EF),
        side: const BorderSide(color: Color(0xFFE4D5D0)),
        onSelected: (_) => _change(() { section = key; status = 'all'; overviewFilter = 'all'; }));

  @override
  Widget build(BuildContext context) {
    final store = widget.store, list = filtered;
    final reviewing = section == 'review';
    final reviewCount = reviewing
        ? store.visitors.where((visitor) => visitor.status != 'archived' &&
            (visitor.watchlisted || visitor.risk != 'normal')).length
        : 0;
    final scanMessage = refundScanMessage;
    final lastPage = list.isEmpty ? 0 : (list.length - 1) ~/ perPage;
    final current = page.clamp(0, lastPage);
    final visible = list.skip(current * perPage).take(perPage).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminHeading(
          'Visitor Accounts',
          'Understand visitor growth, engagement and account health',
        ),
        const SizedBox(height: 17),
        Builder(builder: (context) {
          final report = VisitorAccountReport.calculate(
            store.visitors, store.sessions, DateTime.now());
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFFCF8F6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEAE1DE))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _visitorOverview(report),
              const SizedBox(height: 12),
              VisitorAccountTrendChart(report: report),
              const SizedBox(height: 11),
              Row(children: [
                const Icon(Icons.lightbulb_outline, color: Color(0xFFA2646A), size: 20),
                const SizedBox(width: 9),
                Expanded(child: Text(report.nextAction, style: const TextStyle(
                  fontSize: 12, color: Color(0xFF5C4748)))),
              ]),
            ]),
          );
        }),
        const SizedBox(height: 16),
        Row(children: [
          _sectionChoice('All Visitors', 'all', Icons.people_outline),
          const SizedBox(width: 8),
          _sectionChoice('Review Queue', 'review', Icons.flag_outlined),
          const SizedBox(width: 8),
          _sectionChoice('Archived', 'archived', Icons.archive_outlined),
        ]),
        if (reviewing && store.repository is FirebaseAdminRepository)
          TextButton.icon(
            onPressed: isCheckingRefunds ? null : _scanRefunds,
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(isCheckingRefunds ? 'Checking refunds…' : 'Check refunds'),
          ),
        if (reviewing && !isCheckingRefunds && scanMessage != null)
          Text(scanMessage, style: const TextStyle(color: adminMuted, fontSize: 12)),
        const SizedBox(height: 24),
        KeyedSubtree(
          key: resultsAnchor,
          child: AdminCard(
          padding: const EdgeInsets.all(15),
          child: LayoutBuilder(builder: (context, c) {
            // Keep one neat toolbar row; smaller windows can scroll sideways.
            final searchWidth = (c.maxWidth - 620).clamp(250.0, 450.0).toDouble();
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                SizedBox(
                  width: searchWidth,
                  child: TextField(
                    key: const Key('visitor-search'),
                    controller: searchText,
                    onChanged: (v) => _change(() => query = v),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: 'Search visitor name, email or ID',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                AdminSelect(
                  value: status,
                  options: const {
                    'all': 'All Status',
                    'active': 'Active',
                    'suspended': 'Suspended',
                    'archived': 'Archived',
                  },
                  onChanged: (v) => _change(() {
                    status = v;
                    if (v == 'archived') {
                      section = 'archived';
                    } else if (section == 'archived') {
                      section = 'all';
                    }
                    overviewFilter = 'all';
                    selected.clear();
                  }),
                  width: 132,
                ),
                const SizedBox(width: 10),
                AdminSelect(
                  value: membership,
                  options: {
                    'all': 'All Memberships',
                    for (final tier in store.membershipPolicy.levels)
                      tier.key: '${tier.name} Member',
                  },
                  onChanged: (v) => _change(() => membership = v),
                  width: 160,
                ),

                const SizedBox(width: 10),
                AdminButton(
                  'Manage Tiers',
                  outlined: true,
                  icon: Icons.workspace_premium_outlined,
                  onPressed: store.busy ? null : _editMembershipRules,
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: 'See visitor growth, app engagement and membership trends. No visitor identities are exported.',
                  child: AdminButton(
                    'Visitor Report',
                    icon: Icons.analytics_outlined,
                    outlined: true,
                    onPressed: _openAccountReport,
                  ),
                ),
              ]),
            );
          }),
        )),
        if (overviewFilter != 'all') Padding(
          padding: const EdgeInsets.only(top: 9),
          child: Align(alignment: Alignment.centerLeft, child: InputChip(
            label: Text(overviewFilter == 'new' ? 'Visitors who joined this month'
              : overviewFilter == 'active' ? 'Visitors active in 30 days'
              : 'Accounts requiring review'),
            onDeleted: () => showVisitors('all'),
          )),
        ),
        const SizedBox(height: 18),
        if (selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AdminCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${selected.length} selected',
                    style: const TextStyle(fontSize: 12),
                  ),
                  AdminButton(
                    'Activate',
                    outlined: true,
                    onPressed: store.busy
                        ? null
                        : () => _status(selected.toList(), 'active'),
                  ),
                  AdminButton(
                    'Suspend',
                    outlined: true,
                    onPressed: store.busy
                        ? null
                        : () => _status(selected.toList(), 'suspended'),
                  ),
                  AdminButton(
                    'Add to Watchlist',
                    outlined: true,
                    onPressed: store.busy
                        ? null
                        : () => _watchlist(
                            store.visitors
                                .where((v) => selected.contains(v.id))
                                .toList(),
                            true,
                          ),
                  ),
                  AdminButton(
                    'Remove',
                    outlined: true,
                    onPressed: store.busy
                        ? null
                        : () => _status(selected.toList(), 'archived'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => selected.clear()),
                    child: const Text(
                      'Clear Selection',
                      style: TextStyle(color: adminRose, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Theme(
          data: Theme.of(context).copyWith(
            dataTableTheme: const DataTableThemeData(
              headingRowColor: WidgetStatePropertyAll(Color(0xFFF7F3F1)),
            ),
          ),
          child: AdminCard(
          padding: EdgeInsets.zero,
          child: list.isEmpty
              ? reviewing && reviewCount == 0
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('No cases awaiting review'),
                    )
                  : const AdminEmpty(
                      'No matching visitors',
                      'Try changing your search or filters.',
                      icon: Icons.people_outline,
                    )
              : AdminTable(
                  minWidth: 1110,
                  sortColumnIndex: sort == 'membership'
                      ? 3
                      : sort == 'spent'
                      ? 5
                      : sort == 'joined'
                      ? 6
                      : 1,
                  sortAscending: ascending,
                  columns: [
                    DataColumn(
                      label: Checkbox(
                        value:
                            visible.isNotEmpty &&
                            visible.every((v) => selected.contains(v.id)),
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            selected.addAll(visible.map((v) => v.id));
                          } else {
                            selected.removeAll(visible.map((v) => v.id));
                          }
                        }),
                      ),
                    ),
                    DataColumn(
                      label: const Text('Visitor'),
                      onSort: (_, value) => setState(() {
                        sort = 'name';
                        ascending = value;
                      }),
                    ),
                    const DataColumn(label: Text('Visitor ID')),
                    DataColumn(
                      label: const Text('Membership'),
                      onSort: (_, value) => setState(() {
                        sort = 'membership';
                        ascending = value;
                      }),
                    ),
                    const DataColumn(label: Text('Orders')),
                    DataColumn(
                      label: const Text('Total Spent'),
                      onSort: (_, value) => setState(() {
                        sort = 'spent';
                        ascending = value;
                      }),
                    ),
                    DataColumn(
                      label: const Text('Date Joined'),
                      onSort: (_, value) => setState(() {
                        sort = 'joined';
                        ascending = value;
                      }),
                    ),
                    const DataColumn(label: Text('Status')),
                    if (reviewing) ...[
                      const DataColumn(label: Text('Review reason')),
                      const DataColumn(label: Text('Last updated')),
                    ],
                    const DataColumn(label: Text('Actions')),
                  ],
                  rows: [
                    for (final v in visible)
                      DataRow(
                        cells: [
                          DataCell(
                            Checkbox(
                              value: selected.contains(v.id),
                              onChanged: store.busy
                                  ? null
                                  : (value) => setState(() {
                                      if (value == true) {
                                        selected.add(v.id);
                                      } else {
                                        selected.remove(v.id);
                                      }
                                    }),
                            ),
                          ),
                          DataCell(
                            InkWell(
                              onTap: () => widget.onOpen(v),
                              child: Row(
                                children: [
                                  AdminAvatar(v.name, photo: v.photo),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 195,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Flexible(child: Text(
                                            v.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          )),
                                          if (v.watchlisted || v.risk != 'normal') ...[
                                            const SizedBox(width: 4),
                                            const Icon(Icons.flag_outlined, color: Colors.orange, size: 14),
                                          ],
                                        ]),
                                        const SizedBox(height: 4),
                                        Text(
                                          v.email,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: adminMuted, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              visitorReference(v.id),
                              style: const TextStyle(
                                color: adminMuted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          DataCell(Builder(builder: (context) {
                            final level = store.membershipPolicy.levels.firstWhere(
                              (level) => level.key == v.displayMembershipKey,
                              orElse: () => store.membershipPolicy.levels.first,
                            );
                            final color = membershipAccent(level.colorKey);
                            return Container(
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .10),
                                border: Border.all(color: color.withValues(alpha: .18)),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              child: Text(v.membershipLabel,
                                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                            );
                          })),
                          DataCell(Text('${_completedOrders(v).length}')),
                          DataCell(Text(money(_visitorSpend(v)))),
                          DataCell(Text(
                            adminDateLabel(v.joined),
                            style: const TextStyle(fontSize: 11, color: adminMuted),
                          )),
                          DataCell(AdminBadge(titleCase(v.status))),
                          if (reviewing) ...[
                            DataCell(SizedBox(
                              width: 240,
                              child: Text(
                                v.note.trim().isEmpty
                                    ? 'Flagged for review'
                                    : v.note.trim().split('\n').last,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ), onTap: () => widget.onOpen(v)),
                            DataCell(Text(adminTimeLabel(
                              adminDate(v.metadata['updatedAt']),
                            ))),
                          ],
                          DataCell(
                            PopupMenuButton<String>(
                              tooltip: 'Actions for ${v.name}',
                              onSelected: (action) {
                                if (action == 'view') widget.onOpen(v);
                                if (action == 'edit') {
                                  editVisitor(context, store, v);
                                }
                                if (action == 'active' ||
                                    action == 'suspended' ||
                                    action == 'archived') {
                                  _status([v.id], action);
                                }
                                if (action == 'watch') {
                                  _watchlist([v], !v.watchlisted);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'view',
                                  child: Text('View Details'),
                                ),
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit Profile'),
                                ),
                                PopupMenuItem(
                                  value: v.status == 'active'
                                      ? 'suspended'
                                      : 'active',
                                  child: Text(
                                    v.status == 'active'
                                        ? 'Suspend Account'
                                        : 'Activate Account',
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'watch',
                                  child: Text(
                                    v.watchlisted
                                        ? 'Remove from Watchlist'
                                        : 'Add to Watchlist',
                                  ),
                                ),
                                if (v.status != 'archived')
                                  const PopupMenuItem(
                                    value: 'archived',
                                    child: Text('Archive Account'),
                                  ),
                              ],
                              icon: const Icon(Icons.more_vert, size: 20),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
          ),
        ),
        if (list.isNotEmpty) ...[
          const SizedBox(height: 16),
          AdminCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Showing ${current * perPage + 1} to ${(current + 1) * perPage > list.length ? list.length : (current + 1) * perPage} of ${list.length} results',
                  style: const TextStyle(color: adminMuted, fontSize: 12),
                ),
                AdminSelect(
                  value: '$perPage',
                  options: const {
                    '5': '5 per page',
                    '10': '10 per page',
                    '25': '25 per page',
                    '50': '50 per page',
                  },
                  onChanged: (v) => _change(() => perPage = int.parse(v)),
                  width: 125,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Previous page',
                      onPressed: current > 0
                          ? () => setState(() => page = current - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: adminRose,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '${current + 1}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'of ${lastPage + 1}',
                      style: const TextStyle(color: adminMuted, fontSize: 12),
                    ),
                    IconButton(
                      tooltip: 'Next page',
                      onPressed: current < lastPage
                          ? () => setState(() => page = current + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
