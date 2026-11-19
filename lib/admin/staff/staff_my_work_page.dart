import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'staff_records.dart';
import 'staff_access.dart';
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
  DateTime monday = StaffWeek.start(StaffWeek.parkCalendar(DateTime.now()));
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
      _availabilityReminders(),
      if (selected == 0) _schedule(),
      if (selected == 1) _availability(),
      if (selected == 2) _leave(),
    ],
  );

  Stream<QuerySnapshot<Map<String, dynamic>>> _ownLeave() => widget.db
      .collection('staffLeaveRequests')
      .where('staffUid', isEqualTo: widget.profile.uid).snapshots();

  Widget _availabilityReminders() {
    final current = StaffWeek.start(StaffWeek.parkCalendar(DateTime.now()));
    return Column(children: [
      for (final week in {StaffWeek.key(current): current,
        StaffWeek.key(StaffWeek.day(current, 7)): StaffWeek.day(current, 7),
        weekKey: monday}.values)
        if (!week.isBefore(current))
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: widget.db.collection('staffAvailabilityReminders')
                .doc(StaffWeek.key(week)).snapshots(),
            builder: (context, reminder) {
              if (reminder.data?.exists != true) return const SizedBox.shrink();
              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: widget.db.collection('staffAvailability')
                    .doc(StaffWeek.id(widget.profile.uid, week)).snapshots(),
                builder: (context, availability) {
                  if (!availability.hasData) return const SizedBox.shrink();
                  final days = availability.data?.data()?['availableDays'] as List?;
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _ownLeave(),
                    builder: (context, leave) {
                      if (!leave.hasData) return const SizedBox.shrink();
                      final leaveDays = staffLeaveDays(
                        week, leave.data!.docs.map((doc) => doc.data()),
                      );
                      final weekDays = {
                        for (var index = 0; index < 7; index++)
                          StaffWeek.key(StaffWeek.day(week, index)),
                      };
                      final available = (days ?? []).whereType<String>().toSet()
                          .intersection(weekDays).difference(leaveDays);
                      if (available.length >= staffAvailabilityMinimum(leaveDays)) {
                        return const SizedBox.shrink();
                      }
                      return Card(child: ListTile(
                        leading: const Icon(Icons.notifications_outlined),
                        title: const Text('Submit your availability'),
                        subtitle: Text('Week of ${StaffWeek.key(week)}'),
                        trailing: TextButton(
                          onPressed: () => setState(() { monday = week; selected = 1; }),
                          child: const Text('Fill Availability'),
                        ),
                      ));
                    },
                  );
                },
              );
            },
          ),
    ]);
  }

  Widget _weekPicker() => OutlinedButton.icon(icon: const Icon(Icons.calendar_month),
    label: Text('Week of $weekKey'),
    onPressed: () async {
      final date = await showDatePicker(context: context, initialDate: monday,
        firstDate: DateTime(2025), lastDate: DateTime(2035));
      if (date != null && mounted) setState(() => monday = StaffWeek.start(date));
    });

  Widget _schedule() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(alignment: Alignment.centerLeft, child: _weekPicker()),
      const SizedBox(height: 12),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _ownLeave(),
        builder: (context, leave) {
          if (leave.hasError) return const Text('Could not load approved leave.');
          if (!leave.hasData) return const LinearProgressIndicator();
          final leaveDays = staffLeaveDays(
            monday, leave.data!.docs.map((doc) => doc.data()),
          );
          final fixed = widget.profile.eligibleRoles.where(fixedDutyRoles.contains).firstOrNull;
          if (fixed != null) {
            return _weekSchedule({}, leaveDays, fixedRole: fixed);
          }
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: widget.db.collection('staffPublishedShifts')
                .where('staffUid', isEqualTo: widget.profile.uid).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Text('Could not load your schedule.');
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final shifts = <String, Map<String, dynamic>>{};
              for (final doc in snapshot.data!.docs) {
                final shift = doc.data();
                final starts = StaffWeek.fromTimestamp(shift['startsAt']);
                if (shift['weekStart'] != weekKey ||
                    shift['published'] != true || starts == null) continue;
                shifts[StaffWeek.key(StaffWeek.parkCalendar(starts))] = shift;
              }
              return _weekSchedule(shifts, leaveDays);
            },
          );
        },
      ),
    ],
  );

  Widget _weekSchedule(
    Map<String, Map<String, dynamic>> shifts,
    Set<String> leaveDays, {
    StaffRole? fixedRole,
  }) {
    final theme = Theme.of(context);
    final today = StaffWeek.key(StaffWeek.parkCalendar(DateTime.now()));
    final labels = MaterialLocalizations.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var index = 0; index < 7; index++)
          Builder(builder: (context) {
            final date = StaffWeek.day(monday, index);
            final key = StaffWeek.key(date);
            final shift = shifts[key];
            final onLeave = leaveDays.contains(key);
            final role = fixedRole ?? StaffRole.fromCode(shift?['roleCode']?.toString() ?? '');
            final hasShift = role != null && !onLeave;
            final start = StaffWeek.fromTimestamp(shift?['startsAt']);
            final end = StaffWeek.fromTimestamp(shift?['endsAt']);
            String displayTime(DateTime instant) => labels.formatTimeOfDay(
              TimeOfDay.fromDateTime(StaffWeek.parkCalendar(instant)),
            );
            final hours = start != null && end != null
                ? '${displayTime(start)} – ${displayTime(end)}'
                : '09:00–17:00';
            return Column(children: [
              if (index > 0) const Divider(height: 1),
              ListTile(
                tileColor: key == today ? theme.colorScheme.primaryContainer : null,
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: Text('${date.day}'),
                ),
                title: Text(labels.formatMediumDate(date),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  onLeave ? 'Approved leave' : hasShift ? role.label : 'No scheduled shift',
                ),
                trailing: hasShift ? Text(hours) : null,
              ),
            ]);
          }),
      ]),
    );
  }

  Widget _availability() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _weekPicker(), const SizedBox(height: 12),
    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.db.collection('staffAvailability').doc(availabilityId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Could not load availability. Check permissions.');
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final weekDays = {
          for (var index = 0; index < 7; index++)
            StaffWeek.key(StaffWeek.day(monday, index)),
        };
        final existing = (snapshot.data!.data()?['availableDays'] as List?)
            ?.whereType<String>().toSet().intersection(weekDays) ?? <String>{};
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _ownLeave(),
          builder: (context, leave) {
            if (leave.hasError) return const Text('Could not load approved leave.');
            if (!leave.hasData) return const LinearProgressIndicator();
            final leaveDays = staffLeaveDays(
              monday, leave.data!.docs.map((doc) => doc.data()),
            );
            return _AvailabilityForm(
              key: ValueKey(availabilityId + existing.join(',') + leaveDays.join(',')),
              monday: monday, initial: existing, busy: busy, onSave: _saveAvailability,
              leaveDays: leaveDays,
            );
          },
        );
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
    required this.busy, required this.onSave, required this.leaveDays});
  final DateTime monday;
  final Set<String> initial;
  final Set<String> leaveDays;
  final bool busy;
  final Future<void> Function(Set<String>) onSave;
  @override
  State<_AvailabilityForm> createState() => _AvailabilityFormState();
}
class _AvailabilityFormState extends State<_AvailabilityForm> {
  late final Set<String> checked = widget.initial.difference(widget.leaveDays);
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(15), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose at least ${staffAvailabilityMinimum(widget.leaveDays)} days you can work',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text('${checked.length} selected'),
        for (var i=0;i<7;i++) CheckboxListTile(
          title: Text(StaffWeek.key(StaffWeek.day(widget.monday,i))),
          value: checked.contains(StaffWeek.key(StaffWeek.day(widget.monday,i))),
          subtitle: widget.leaveDays.contains(StaffWeek.key(StaffWeek.day(widget.monday,i)))
              ? const Text('Approved leave') : null,
          onChanged: widget.busy ||
              widget.leaveDays.contains(StaffWeek.key(StaffWeek.day(widget.monday,i)))
              ? null : (v) => setState(() {
            final key = StaffWeek.key(StaffWeek.day(widget.monday,i));
            if (v == true) { checked.add(key); } else { checked.remove(key); }
          }),
        ),
        FilledButton(onPressed: widget.busy ||
            checked.length < staffAvailabilityMinimum(widget.leaveDays)
            ? null : () => widget.onSave(checked),
          child: const Text('Save Availability')),
      ],
    ),
  ));
}
