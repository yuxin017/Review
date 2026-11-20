import 'dart:convert';
import 'package:file_picker/file_picker.dart';
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
  bool busy = false;
  String? feedback;
  late final _leaveRequests = widget.db.collection('staffLeaveRequests')
      .where('staffUid', isEqualTo: widget.profile.uid).snapshots();

  Future<void> _applyLeave() async {
    final reason = TextEditingController();
    var leaveType = 'Annual Leave';
    String? certificateName;
    String? certificateData;
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
              label: Text(certificateName ?? 'Attach medical certificate'),
              onPressed: pickingCertificate ? null : () async {
                update(() { pickingCertificate = true; certificateError = null; });
                try {
                  final picked = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                  );
                  if (!ctx.mounted || picked.isEmpty) return;
                  final file = picked.single;
                  final bytes = await file.readAsBytes();
                  if (!ctx.mounted) return;
                  if (bytes.isEmpty || bytes.length > 650000 || file.name.length > 160) {
                    update(() => certificateError =
                        'Choose a PDF, JPG or PNG up to 650 KB with a shorter name.');
                  } else {
                    update(() {
                      certificateName = file.name;
                      certificateData = base64Encode(bytes);
                    });
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
            onPressed: pickingCertificate || (leaveType == 'Sick Leave' && certificateData == null)
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
          'certificateName': certificateName!,
          'certificateData': certificateData!,
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
      const Text('Leave', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
      const SizedBox(height: 7),
      const Text('Apply for time off and view the status of your requests.'),
      const SizedBox(height: 14),
      if (busy) const LinearProgressIndicator(),
      if (feedback != null) Padding(padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(feedback!)),
      const SizedBox(height: 12),
      _leave(),
    ],
  );

  Widget _leave() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    FilledButton.icon(onPressed: busy ? null : _applyLeave,
      icon: const Icon(Icons.add), label: const Text('Apply Leave')),
    const SizedBox(height: 12),
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _leaveRequests,
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
