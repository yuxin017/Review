import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'staff_access.dart';
import '../../attractions/models/attraction.dart';
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
  DateTime monday = StaffWeek.start(StaffWeek.parkCalendar(DateTime.now()));
  List<StaffShiftPlan> draft = const [];
  List<String> gaps = const [];
  String? message;
  bool busy = false;
  bool showPublished = true;
  bool draftGenerated = false;
  static const requiredRoles = <StaffRole>{
    StaffRole.attractionOperator,
    StaffRole.admissionStaff, StaffRole.photographer,
    StaffRole.photoCounterStaff,
  };

  final selectedRoles = <StaffRole>{...requiredRoles, StaffRole.customerSupport};

  String get weekKey => StaffWeek.key(monday);
  FirebaseFirestore get db => widget.repository.db;

  late final _attractionNames = _readAttractions();

  Future<Map<String, String>> _readAttractions() async {
    final snapshot = await db.collection('attractions').get();
    final attractions = <String, String>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['deletedAt'] != null) continue;
      final kind = ParkPlaceKind.values.where((item) => item.name == data['kind']).firstOrNull ??
          ParkPlaceKind.fromCategory(data['category']?.toString() ?? '');
      if (kind == ParkPlaceKind.attractions) {
        attractions[doc.id] = data['name']?.toString() ?? doc.id;
      }
    }
    return attractions;
  }

  Future<ScheduleDraft> _arrange() async {
    final directory = await widget.repository.watchStaffDirectory().first;
    final rosterDays = {
      for (var day = 0; day < 7; day++) StaffWeek.key(StaffWeek.day(monday, day)),
    };
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
      availability: {for (final employee in directory) employee.uid: rosterDays},
      leaves: leaves,
      qualifications: qualifications,
      attractions: await _readAttractions(),
    );
  }

  Future<void> _generate() async {
    if (busy) return;
    setState(() { busy = true; message = null; draft = []; gaps = []; draftGenerated = false; });
    try {
      final result = await _arrange();
      if (mounted) setState(() {
        draft = result.assignments; gaps = result.gaps; draftGenerated = true;
        message = draft.isEmpty ? 'No eligible shifts. Check staff roles, training and approved leave.'
            : 'Draft ready. Review coverage before approving.';
      });
    } catch (_) {
      if (mounted) setState(() => message =
          'Unable to generate the schedule. Check staff roles, training and permissions.');
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
    if (busy || draft.isEmpty || gaps.isNotEmpty) return;
    final confirmed = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve weekly schedule?'),
        content: Text(
          'Publish ${draft.length} shifts for the week of $weekKey? This replaces that week’s published schedule.',
        ),
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
      if (changed || latest.gaps.isNotEmpty) {
        if (mounted) setState(() {
          draft = latest.assignments;
          gaps = latest.gaps;
          message = latest.gaps.isNotEmpty
              ? 'Fill every required post before publishing.'
              : 'Staff details changed. Review the updated draft before publishing.';
        });
        return;
      }
      // Replace that week's previously published assignments atomically.
      final old = await db.collection('staffPublishedShifts')
          .where('weekStart', isEqualTo: weekKey).get();
      final batch = db.batch();
      final replacementIds = draft.map((s) => s.docId).toSet();
      for (final doc in old.docs) {
        final role = StaffRole.fromCode(doc.data()['roleCode']?.toString() ?? '');
        if (!fixedDutyRoles.contains(role) && !replacementIds.contains(doc.id)) {
          batch.delete(doc.reference);
        }
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

  bool get pastWeek => monday.isBefore(StaffWeek.start(StaffWeek.parkCalendar(DateTime.now())));

  void _changeWeek(int amount) => setState(() {
    monday = monday.add(Duration(days: amount * 7));
    draft = []; gaps = []; draftGenerated = false; message = null;
    showPublished = true;
  });

  Future<void> _selectWeek() async {
    final chosen = await showDatePicker(context: context,
      initialDate: monday, firstDate: DateTime(2025), lastDate: DateTime(2035));
    if (chosen != null && mounted) setState(() {
      monday = StaffWeek.start(chosen); draft = []; gaps = []; draftGenerated = false;
      showPublished = true; message = null;
    });
  }

  Widget _timetable(Map<(StaffRole, String), List<String>> assigned, {
    Set<StaffRole> scheduledRoles = const {},
    bool isDraft = false,
  }) {
    final days = [for (var i = 0; i < 7; i++) StaffWeek.day(monday, i)];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 18,
          headingRowColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          dataRowMinHeight: 60,
          dataRowMaxHeight: double.infinity,
          columns: [
            const DataColumn(label: Text('Role')),
            for (final date in days)
              DataColumn(label: Text(_dayLabel(date).replaceFirst(' · ', '\n'))),
          ],
          rows: [
            for (final role in StaffRole.values)
              if (fixedDutyRoles.contains(role) || scheduledRoles.contains(role))
                DataRow(cells: [
                  DataCell(Text(role.label,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
                  for (final date in days)
                    DataCell(SizedBox(
                      width: 114,
                      child: Text(
                        fixedDutyRoles.contains(role)
                            ? 'Regular duty'
                            : assigned[(role, StaffWeek.key(date))]?.join('\n') ??
                                (isDraft ? 'Unfilled' : '—'),
                        style: TextStyle(
                          color: isDraft && !fixedDutyRoles.contains(role) &&
                              !assigned.containsKey((role, StaffWeek.key(date)))
                              ? Theme.of(context).colorScheme.error : null,
                        ),
                      ),
                    )),
                ]),
          ],
        ),
      ),
    );
  }

  Widget _previewDraft() {
    final assigned = <(StaffRole, String), List<String>>{};
    for (final shift in draft) {
      final key = (StaffRole.fromCode(shift.roleCode)!, StaffWeek.key(shift.date));
      assigned.putIfAbsent(key, () => []).add(
        shift.attractionName == null ? shift.staffName
            : '${shift.staffName} · ${shift.attractionName}',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (gaps.isNotEmpty)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ExpansionTile(
              initiallyExpanded: true,
              leading: const Icon(Icons.warning_amber_rounded),
              title: Text('${gaps.length} required posts are unfilled'),
              children: [for (final gap in gaps) ListTile(dense: true, title: Text(gap))],
            ),
          ),
        _timetable(assigned, scheduledRoles: draftGenerated ? selectedRoles : const {}, isDraft: true),
      ],
    );
  }

  Widget _publishedHistory() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: db.collection('staffPublishedShifts')
        .where('weekStart', isEqualTo: weekKey).snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('Could not load the published schedule.');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('staffLeaveRequests')
            .where('status', isEqualTo: 'approved').snapshots(),
        builder: (context, leaveSnapshot) {
          if (leaveSnapshot.hasError) {
            return const Text('Could not check the roster for approved leave.');
          }
          if (!leaveSnapshot.hasData) return const LinearProgressIndicator();
          final approvedLeaves = leaveSnapshot.data!.docs.map((doc) => doc.data());
          return FutureBuilder<Map<String, String>>(
            future: _attractionNames,
            builder: (context, names) {
              final assigned = <(StaffRole, String), List<String>>{};
              for (final doc in snapshot.data!.docs) {
                final data = doc.data();
                final role = StaffRole.fromCode(data['roleCode']?.toString() ?? '');
                final start = StaffWeek.fromTimestamp(data['startsAt']);
                if (role == null || start == null) continue;
                final key = (role, StaffWeek.key(StaffWeek.parkCalendar(start)));
                final ids = (data['attractionIds'] as List?)?.whereType<String>() ?? const <String>[];
                final places = ids.map((id) => names.data?[id]).whereType<String>().join(', ');
                final staffName = data['staffName']?.toString() ?? 'Staff';
                final onLeave = approvedLeaves.any((leave) =>
                    leave['staffUid'] == data['staffUid'] &&
                    staffLeaveIncludes(leave, key.$2));
                final assignment = onLeave ? '$staffName · Cover needed' : staffName;
                assigned.putIfAbsent(key, () => []).add(
                    places.isEmpty ? assignment : '$assignment · $places');
              }
              return _timetable(assigned, scheduledRoles: assigned.keys.map((key) => key.$1).toSet());
            },
          );
        },
      );
    },
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Weekly Staff Schedule',
        style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('Cover the entrance and each attraction every day before publishing.',
        style: TextStyle(color: Color(0xFF827573), fontSize: 13)),
      const SizedBox(height: 16),
      Card(child: Padding(padding: const EdgeInsets.all(16),
        child: Wrap(spacing: 13, runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(onPressed: busy ? null : () => _changeWeek(-1),
              icon: const Icon(Icons.chevron_left), label: const Text('Previous week')),
            OutlinedButton.icon(onPressed: busy ? null : _selectWeek,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text('${StaffWeek.key(monday)} to '
                '${StaffWeek.key(StaffWeek.day(monday, 6))}')),
            OutlinedButton.icon(onPressed: busy ? null : () => _changeWeek(1),
              icon: const Icon(Icons.chevron_right), label: const Text('Next week')),
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
                if (role != StaffRole.superAdmin && !fixedDutyRoles.contains(role))
                  FilterChip(label: Text(role.label),
                    selected: selectedRoles.contains(role),
                    onSelected: busy || requiredRoles.contains(role) ? null : (v) => setState(() {
                      if (v) { selectedRoles.add(role); }
                      else { selectedRoles.remove(role); }
                      draft = []; gaps = []; draftGenerated = false;
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
              FilledButton.icon(onPressed: busy || draft.isEmpty || gaps.isNotEmpty || pastWeek ? null : _approve,
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
