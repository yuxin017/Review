import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'staff_records.dart';
import 'staff_schedule_utils.dart';

/// Employee self-service on the separate Staff Firebase session.
/// Access to underlying records is controlled by Firestore Security Rules.
class StaffMyWorkPage extends StatefulWidget {
  const StaffMyWorkPage({super.key, required this.db, required this.profile});
  final FirebaseFirestore db;
  final StaffProfile profile;
  @override
  State<StaffMyWorkPage> createState() => _StaffMyWorkPageState();
}

class _StaffMyWorkPageState extends State<StaffMyWorkPage> {
  int selected = 0;
  DateTime monday = StaffWeek.start(DateTime.now());
  bool busy = false;
  String? feedback;
  String get weekKey => StaffWeek.key(monday);
  String get availabilityId => StaffWeek.id(widget.profile.uid, monday);

  Future<void> _saveAvailability(Set<String> dates) async {
    setState(() { busy = true; feedback = null; });
    try {
      await widget.db.collection('staffAvailability').doc(availabilityId).set({
        'staffUid': widget.profile.uid,
        'weekStart': weekKey,
        'availableDays': dates.toList()..sort(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => feedback = 'Availability saved for $weekKey.');
    } catch (_) {
      if (mounted) setState(() => feedback =
          'Could not save availability. Check your connection or staff permissions.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _applyLeave() async {
    final reason = TextEditingController();
    var leaveType = 'Annual Leave';
    DateTime first = DateUtils.dateOnly(DateTime.now());
    DateTime last = first;
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (ctx, update) => AlertDialog(
        title: const Text('Apply Leave'),
        content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(value: leaveType,
            decoration: const InputDecoration(labelText: 'Leave type'),
            items: ['Annual Leave','Sick Leave','Emergency Leave','Unpaid Leave']
                .map((type) => DropdownMenuItem(value:type,child:Text(type))).toList(),
            onChanged: (v) { if (v != null) update(() => leaveType = v); }),
          const SizedBox(height: 12),
          OutlinedButton.icon(icon: const Icon(Icons.date_range),
            label: Text('${StaffWeek.key(first)} to ${StaffWeek.key(last)}'),
            onPressed: () async {
              final range = await showDateRangePicker(context: ctx,
                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDateRange: DateTimeRange(start: first, end: last));
              if (range != null) update(() { first = range.start; last = range.end; });
            }),
          const SizedBox(height: 12),
          TextField(controller: reason, maxLines: 3, maxLength: 300,
            decoration: const InputDecoration(labelText: 'Reason', hintText: 'Briefly explain the request')),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('Submit Request'))],
      )),
    );
    final note = reason.text.trim();
    reason.dispose();
    if (confirmed != true || !mounted) return;
    if (note.length < 3) {
      setState(() => feedback = 'Please enter a short reason for your leave.');
      return;
    }
    setState(() { busy = true; feedback = null; });
    try {
      await widget.db.collection('staffLeaveRequests').add({
        'staffUid': widget.profile.uid,
        'staffName': widget.profile.fullName,
        'leaveType': leaveType,
        'startOn': StaffWeek.key(first),
        'endOn': StaffWeek.key(last),
        'reason': note,
        'status': 'pending',
        'decisionNote': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => feedback = 'Leave request submitted for admin review.');
    } catch (_) {
      if (mounted) setState(() => feedback = 'Leave request could not be submitted. Check permissions.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('My Work', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
      const SizedBox(height: 7),
      Text('Welcome, ${widget.profile.fullName}. View approved shifts and submit time-off requests.'),
      const SizedBox(height: 14),
      Wrap(spacing: 8, children: [
        ChoiceChip(label: const Text('My Schedule'), selected: selected == 0,
          onSelected: (_) => setState(() => selected = 0)),
        ChoiceChip(label: const Text('My Availability'), selected: selected == 1,
          onSelected: (_) => setState(() => selected = 1)),
        ChoiceChip(label: const Text('Apply Leave / History'), selected: selected == 2,
          onSelected: (_) => setState(() => selected = 2)),
      ]),
      if (busy) const LinearProgressIndicator(),
      if (feedback != null) Padding(padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(feedback!)),
      const SizedBox(height: 12),
      if (selected == 0) _schedule(),
      if (selected == 1) _availability(),
      if (selected == 2) _leave(),
    ],
  );

  Widget _weekPicker() => OutlinedButton.icon(icon: const Icon(Icons.calendar_month),
    label: Text('Week of $weekKey'),
    onPressed: () async {
      final date = await showDatePicker(context: context, initialDate: monday,
        firstDate: DateTime(2025), lastDate: DateTime(2035));
      if (date != null && mounted) setState(() => monday = StaffWeek.start(date));
    });

  Widget _schedule() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _weekPicker(), const SizedBox(height: 12),
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.db.collection('staffPublishedShifts')
        .where('staffUid', isEqualTo: widget.profile.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Card(child: ListTile(
          title: Text('Could not load your schedule.'), subtitle: Text('Check your connection or ask your supervisor.')));
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final shifts = snapshot.data!.docs.where((doc) =>
            doc.data()['weekStart'] == weekKey && doc.data()['published'] == true).toList()
          ..sort((a,b) => (StaffWeek.fromTimestamp(a.data()['startsAt']) ?? DateTime(1970))
              .compareTo(StaffWeek.fromTimestamp(b.data()['startsAt']) ?? DateTime(1970)));
        if (shifts.isEmpty) return const Card(child: ListTile(
          title: Text('No approved shifts this week'),
          subtitle: Text('Your supervisor will publish your schedule after review.')));
        return Column(children: [for (final shift in shifts) Card(child: ListTile(
          leading: const Icon(Icons.event_available_outlined),
          title: Text((shift.data()['roleCode'] ?? '').toString().replaceAll('_',' ')),
          subtitle: Text('${StaffWeek.key(StaffWeek.fromTimestamp(shift.data()['startsAt']) ?? DateTime.now())} · 09:00–17:00'),
        ))]);
      },
    ),
  ]);

  Widget _availability() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _weekPicker(), const SizedBox(height: 12),
    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.db.collection('staffAvailability').doc(availabilityId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Could not load availability. Check permissions.');
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final existing = (snapshot.data!.data()?['availableDays'] as List?)?.whereType<String>().toSet() ?? <String>{};
        return _AvailabilityForm(key: ValueKey(availabilityId + existing.join(',')),
          monday: monday, initial: existing, busy: busy, onSave: _saveAvailability);
      },
    ),
  ]);

  Widget _leave() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    FilledButton.icon(onPressed: busy ? null : _applyLeave,
      icon: const Icon(Icons.add), label: const Text('Apply Leave')),
    const SizedBox(height: 12),
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.db.collection('staffLeaveRequests')
          .where('staffUid', isEqualTo: widget.profile.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Could not load leave history.');
        if (!snapshot.hasData) return const LinearProgressIndicator();
        if (snapshot.data!.docs.isEmpty) return const Card(child: ListTile(title: Text('No leave requests')));
        return Column(children: [for (final doc in snapshot.data!.docs) Card(child: ListTile(
          title: Text('${doc.data()['leaveType'] ?? 'Leave'} · ${doc.data()['status'] ?? 'pending'}'),
          subtitle: Text('${doc.data()['startOn'] ?? ''} to ${doc.data()['endOn'] ?? ''}\n${doc.data()['decisionNote'] ?? ''}'),
          isThreeLine: true,
        ))]);
      },
    ),
  ]);
}

class _AvailabilityForm extends StatefulWidget {
  const _AvailabilityForm({super.key, required this.monday, required this.initial,
    required this.busy, required this.onSave});
  final DateTime monday;
  final Set<String> initial;
  final bool busy;
  final Future<void> Function(Set<String>) onSave;
  @override
  State<_AvailabilityForm> createState() => _AvailabilityFormState();
}
class _AvailabilityFormState extends State<_AvailabilityForm> {
  late final Set<String> checked = {...widget.initial};
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(15), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Select the days you can work', style: TextStyle(fontWeight: FontWeight.bold)),
        for (var i=0;i<7;i++) CheckboxListTile(
          title: Text(StaffWeek.key(StaffWeek.day(widget.monday,i))),
          value: checked.contains(StaffWeek.key(StaffWeek.day(widget.monday,i))),
          onChanged: widget.busy ? null : (v) => setState(() {
            final key = StaffWeek.key(StaffWeek.day(widget.monday,i));
            if (v == true) { checked.add(key); } else { checked.remove(key); }
          }),
        ),
        FilledButton(onPressed: widget.busy ? null : () => widget.onSave(checked),
          child: const Text('Save Availability')),
      ],
    ),
  ));
}
