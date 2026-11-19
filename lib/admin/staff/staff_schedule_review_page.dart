import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'staff_access.dart';
import 'staff_records.dart';
import 'staff_records_repository.dart';
import 'staff_schedule_utils.dart';
import 'staff_schedule_arrangement.dart';

/// Real Firestore draft -> human review -> approved shift publication.
/// All writes must be authorized independently by deployed Firestore rules.
class StaffScheduleReviewPage extends StatefulWidget {
  const StaffScheduleReviewPage({super.key, required this.repository});
  final StaffRecordsRepository repository;
  @override
  State<StaffScheduleReviewPage> createState() => _StaffScheduleReviewPageState();
}

class _StaffScheduleReviewPageState extends State<StaffScheduleReviewPage> {
  DateTime monday = StaffWeek.start(DateTime.now());
  List<StaffShiftPlan> draft = const [];
  List<String> gaps = const [];
  String? message;
  bool busy = false;
  bool showPublished = true;
  final selectedRoles = <StaffRole>{
    StaffRole.operationsManager, StaffRole.attractionOperator,
    StaffRole.admissionStaff, StaffRole.photographer,
    StaffRole.photoCounterStaff, StaffRole.customerSupport,
    StaffRole.marketingStaff,
  };

  String get weekKey => StaffWeek.key(monday);
  FirebaseFirestore get db => widget.repository.db;

  Future<ScheduleDraft> _arrange() async {
    final directory = await widget.repository.watchStaffDirectory().first;
    final availabilitySnap = await db.collection('staffAvailability')
        .where('weekStart', isEqualTo: weekKey).get();
    final availability = <String, Set<String>>{};
    for (final doc in availabilitySnap.docs) {
      final data = doc.data();
      final uid = data['staffUid'];
      if (uid is String) {
        availability[uid] = (data['availableDays'] as List?)
                ?.whereType<String>().toSet() ?? <String>{};
      }
    }
    final leaveSnap = await db.collection('staffLeaveRequests')
        .where('status', isEqualTo: 'approved').get();
    final leaves = leaveSnap.docs.map((doc) => doc.data());
    final qualificationsSnap = await db.collection('staffQualifications').get();
    final qualifications = <StaffQualification>[];
    for (final doc in qualificationsSnap.docs) {
      try { qualifications.add(StaffQualification.fromMap(doc.id, doc.data())); }
      catch (_) { /* Invalid training never grants eligibility. */ }
    }
    return arrangeStaffWeek(
      monday: monday,
      roles: selectedRoles,
      directory: directory,
      availability: availability,
      leaves: leaves,
      qualifications: qualifications,
    );
  }

  Future<void> _generate() async {
    if (busy) return;
    setState(() { busy = true; message = null; draft = []; gaps = []; });
    try {
      final result = await _arrange();
      if (mounted) setState(() {
        draft = result.assignments; gaps = result.gaps;
        message = draft.isEmpty ? 'No eligible shifts. Ask staff to submit availability.'
            : 'Draft ready. Review coverage before approving.';
      });
    } catch (_) {
      if (mounted) setState(() => message =
          'Unable to generate the schedule. Check staff availability, training and permissions.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _saveDraft() async {
    if (busy || draft.isEmpty) return;
    setState(() { busy = true; message = null; });
    try {
      final batch = db.batch();
      for (final shift in draft) {
        // Existing staffShiftDrafts rules only permit these original fields.
        final data = shift.toFirestore(weekKey);
        data.remove('weekStart');
        batch.set(db.collection('staffShiftDrafts').doc(shift.docId), data);
      }
      await batch.commit();
      if (mounted) setState(() => message = 'Draft saved. Staff cannot see it until approved.');
    } catch (_) {
      if (mounted) setState(() => message = 'Could not save draft. Check administrator permissions.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _approve() async {
    if (busy || draft.isEmpty) return;
    final confirmed = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve weekly schedule?'),
        content: Text(gaps.isEmpty
          ? 'Publish ${draft.length} shifts for the week of $weekKey? This replaces that week’s published schedule.'
          : '${gaps.length} shifts remain unfilled. Publish ${draft.length} shifts and replace that week’s published schedule?'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve & Publish'))],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { busy = true; message = null; });
    try {
      final latest = await _arrange();
      final latestByShift = {
        for (final shift in latest.assignments) shift.docId: shift,
      };
      final changed = latestByShift.length != draft.length || draft.any((shift) {
        final current = latestByShift[shift.docId];
        return current?.staffUid != shift.staffUid ||
            current?.attractionId != shift.attractionId;
      });
      if (changed) {
        if (mounted) setState(() {
          draft = latest.assignments;
          gaps = latest.gaps;
          message = 'Staff details changed. Review the updated draft before publishing.';
        });
        return;
      }
      // Replace that week's previously published assignments atomically.
      final old = await db.collection('staffPublishedShifts')
          .where('weekStart', isEqualTo: weekKey).get();
      final batch = db.batch();
      final replacementIds = draft.map((s) => s.docId).toSet();
      for (final doc in old.docs) {
        if (!replacementIds.contains(doc.id)) batch.delete(doc.reference);
      }
      for (final shift in draft) {
        batch.set(db.collection('staffPublishedShifts').doc(shift.docId),
            shift.toFirestore(weekKey, published: true));
      }
      await batch.commit();
      if (mounted) setState(() => message =
          'Approved and published. Assigned staff can now view their weekly schedule.');
    } catch (_) {
      if (mounted) setState(() => message =
          'Publishing failed. The existing approved schedule was not changed. Check Firestore rules.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _dayLabel(DateTime value) {
    const days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    return '${days[value.weekday - 1]} · ${StaffWeek.key(value)}';
  }

  bool get pastWeek => monday.isBefore(StaffWeek.start(DateTime.now()));

  void _changeWeek(int amount) => setState(() {
    monday = monday.add(Duration(days: amount * 7));
    draft = []; gaps = []; message = null;
    showPublished = true;
  });

  Future<void> _selectWeek() async {
    final chosen = await showDatePicker(context: context,
      initialDate: monday, firstDate: DateTime(2025), lastDate: DateTime(2035));
    if (chosen != null && mounted) setState(() {
      monday = StaffWeek.start(chosen); draft = []; gaps = [];
      showPublished = true; message = null;
    });
  }

  Widget _previewDraft() {
    if (draft.isEmpty) return const Card(child: Padding(
      padding: EdgeInsets.all(20), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('No draft generated', style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 7),
          Text('1. Confirm staff availability and leave requests.\n'
            '2. Choose the week and roles.\n'
            '3. Select Generate Draft to propose assignments.'),
        ])));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var offset = 0; offset < 7; offset++)
        Builder(builder: (context) {
          final date = StaffWeek.day(monday, offset);
          final assignments = draft.where((s) =>
            StaffWeek.key(s.date) == StaffWeek.key(date)).toList();
          return Card(child: ExpansionTile(
            initiallyExpanded: offset < 2,
            title: Text(_dayLabel(date), style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text('${assignments.length} planned assignments'),
            children: assignments.isEmpty
              ? [const ListTile(title: Text('No available staff assigned'))]
              : [for (final assignment in assignments)
                  ListTile(dense: true,
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(assignment.staffName),
                    subtitle: Text('${assignment.roleCode.replaceAll('_',' ')}'
                      ' · 09:00–17:00${assignment.attractionId == null ? '' : ' · Assigned ride'}'))],
          ));
        }),
      if (gaps.isNotEmpty) Card(color: const Color(0xFFFFF2EA),
        child: Padding(padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text('${gaps.length} shifts cannot be filled',
              style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final issue in gaps.take(8))
                Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(issue)),
              if (gaps.length > 8) Text('+ ${gaps.length - 8} more'),
            ]))),
    ]);
  }

  Widget _publishedHistory() => StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream: db.collection('staffPublishedShifts')
      .where('weekStart', isEqualTo: weekKey).snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Card(child: Padding(
        padding: EdgeInsets.all(18), child: Text(
          'Unable to load published shifts. Check workforce Firestore rules.')));
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final records = snapshot.data!.docs.toList()..sort((a,b) {
        final startA = StaffWeek.fromTimestamp(a.data()['startsAt']);
        final startB = StaffWeek.fromTimestamp(b.data()['startsAt']);
        return (startA ?? DateTime(1970)).compareTo(startB ?? DateTime(1970));
      });
      if (records.isEmpty) return const Card(child: Padding(
        padding: EdgeInsets.all(20), child: Text(
          'No approved schedule for this week. Choose another week to view earlier schedules.')));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text('${records.length} approved shifts',
            style: const TextStyle(fontWeight: FontWeight.w700))),
        for (var offset = 0; offset < 7; offset++)
          Builder(builder: (context) {
            final date = StaffWeek.day(monday, offset);
            final assignments = records.where((d) {
              final start = StaffWeek.fromTimestamp(d.data()['startsAt']);
              return start != null && StaffWeek.key(start.toLocal()) == StaffWeek.key(date);
            }).toList();
            return Card(child: ExpansionTile(
              initiallyExpanded: offset < 2,
              title: Text(_dayLabel(date), style: const TextStyle(
                fontWeight: FontWeight.w700)),
              subtitle: Text('${assignments.length} approved assignments'),
              children: assignments.isEmpty
                ? [const ListTile(title: Text('No scheduled shifts'))]
                : [for (final shift in assignments) ListTile(
                    leading: const Icon(Icons.verified_outlined,
                      color: Color(0xFF628A71)),
                    title: Text(shift.data()['staffName']?.toString() ?? 'Staff'),
                    subtitle: Text('${shift.data()['roleCode']?.toString().replaceAll('_',' ') ?? 'Role'}'
                      ' · 09:00–17:00'),
                  )],
            ));
          }),
      ]);
    },
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Weekly Staff Schedule',
        style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('Plan the week, review staffing gaps, then approve the roster.',
        style: TextStyle(color: Color(0xFF827573), fontSize: 13)),
      const SizedBox(height: 16),
      Card(child: Padding(padding: const EdgeInsets.all(16),
        child: Wrap(spacing: 13, runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(onPressed: () => _changeWeek(-1),
              icon: const Icon(Icons.chevron_left), label: const Text('Previous week')),
            OutlinedButton.icon(onPressed: _selectWeek,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text('${StaffWeek.key(monday)} to '
                '${StaffWeek.key(StaffWeek.day(monday, 6))}')),
            OutlinedButton.icon(onPressed: () => _changeWeek(1),
              icon: const Icon(Icons.chevron_right), label: const Text('Next week')),
          ]))),
      const SizedBox(height: 14),
      Card(color: const Color(0xFFF7EEEA),
        child: Padding(padding: const EdgeInsets.all(14),
          child: Wrap(spacing: 16, runSpacing: 8, children: [
            for (final instruction in const [
              '1  Check availability', '2  Generate draft',
              '3  Review unfilled shifts', '4  Approve & publish',
            ]) Text(instruction, style: const TextStyle(
              color: Color(0xFF594849), fontSize: 12,
              fontWeight: FontWeight.w600)),
          ]))),
      const SizedBox(height: 14),
      Wrap(spacing: 9, runSpacing: 9, children: [
        ChoiceChip(label: const Text('Approved Schedule / History'),
          selected: showPublished,
          onSelected: (_) => setState(() => showPublished = true)),
        ChoiceChip(label: const Text('Draft & Review'),
          selected: !showPublished,
          onSelected: (_) => setState(() => showPublished = false)),
      ]),
      const SizedBox(height: 13),
      if (!showPublished) ...[
        Card(child: Padding(padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Roles needed each day',
              style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            Wrap(spacing: 7, runSpacing: 6, children: [
              for (final role in StaffRole.values)
                if (role != StaffRole.superAdmin)
                  FilterChip(label: Text(role.label),
                    selected: selectedRoles.contains(role),
                    onSelected: busy ? null : (v) => setState(() {
                      if (v) { selectedRoles.add(role); }
                      else { selectedRoles.remove(role); }
                      draft = []; gaps = [];
                    })),
            ]),
          ]))),
        const SizedBox(height: 9),
        Card(child: Padding(padding: const EdgeInsets.all(14),
          child: Wrap(spacing: 10, runSpacing: 9,
            crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilledButton.icon(onPressed: busy || pastWeek ? null : () {
                  setState(() => showPublished = false); _generate();
                },
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Generate Draft')),
              OutlinedButton.icon(onPressed: busy || draft.isEmpty ? null : _saveDraft,
                icon: const Icon(Icons.save_outlined), label: const Text('Save Draft')),
              FilledButton.icon(onPressed: busy || draft.isEmpty || pastWeek ? null : _approve,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Approve & Publish')),
            ]))),
        if (pastWeek) const Padding(
          padding: EdgeInsets.all(10), child: Text(
            'Past weeks are view-only. Switch to Approved Schedule / History.',
            style: TextStyle(color: Color(0xFF8A6B68)))),
        const SizedBox(height: 10),
        Text('${draft.length} proposed shifts · ${gaps.length} unfilled',
          style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _previewDraft(),
      ] else _publishedHistory(),
      if (busy) const Padding(padding: EdgeInsets.all(10),
        child: LinearProgressIndicator()),
      if (message != null) Padding(padding: const EdgeInsets.all(12),
        child: Text(message!, style: const TextStyle(color: Color(0xFF72575B)))),
    ],
  );
}
