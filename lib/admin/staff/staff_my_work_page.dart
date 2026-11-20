import 'dart:convert';
import 'package:file_picker/file_picker.dart';
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

  Future<void> _applyLeave() async {
    final reason = TextEditingController();
    var leaveType = 'Annual Leave';
    PlatformFile? certificate;
    var pickingCertificate = false;
    String? certificateError;
    DateTime first = DateUtils.dateOnly(DateTime.now());
    DateTime last = first;
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (ctx, update) => AlertDialog(
        title: const Text('Apply Leave'),
        content: SingleChildScrollView(child: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
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
          if (leaveType == 'Sick Leave') ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.attach_file),
              label: Text(certificate?.name ?? 'Attach medical certificate'),
              onPressed: pickingCertificate ? null : () async {
                update(() { pickingCertificate = true; certificateError = null; });
                try {
                  final picked = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                    withData: true,
                  );
                  if (!ctx.mounted || picked == null) return;
                  final file = picked.files.single;
                  final bytes = file.bytes;
                  if (bytes == null || bytes.isEmpty || bytes.length > 650000 ||
                      file.name.length > 160) {
                    update(() => certificateError =
                        'Choose a PDF, JPG or PNG up to 650 KB with a shorter name.');
                  } else {
                    update(() => certificate = file);
                  }
                } catch (_) {
                  if (ctx.mounted) update(() => certificateError = 'Unable to open the file.');
                } finally {
                  if (ctx.mounted) update(() => pickingCertificate = false);
                }
              },
            ),
            if (certificateError != null) Text(certificateError!),
          ],
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('Cancel')),
          FilledButton(
            onPressed: pickingCertificate || (leaveType == 'Sick Leave' && certificate == null)
                ? null : () => Navigator.pop(ctx, true),
            child: const Text('Submit Request'))],
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
        if (leaveType == 'Sick Leave') ...{
          'certificateName': certificate!.name,
          'certificateData': base64Encode(certificate!.bytes!),
        },
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
        ChoiceChip(label: const Text('My Leave'), selected: selected == 1,
          onSelected: (_) => setState(() => selected = 1)),
      ]),
      if (busy) const LinearProgressIndicator(),
      if (feedback != null) Padding(padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(feedback!)),
      const SizedBox(height: 12),
      if (selected == 0) _schedule(),
      if (selected == 1) _leave(),
    ],
  );

  Stream<QuerySnapshot<Map<String, dynamic>>> _ownLeave() => widget.db
      .collection('staffLeaveRequests')
      .where('staffUid', isEqualTo: widget.profile.uid).snapshots();

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
