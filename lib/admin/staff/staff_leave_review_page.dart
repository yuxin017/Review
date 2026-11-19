import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'staff_records_repository.dart';

class StaffLeaveReviewPage extends StatelessWidget {
  const StaffLeaveReviewPage({super.key, required this.repository});
  final StaffRecordsRepository repository;

  Future<void> _decide(BuildContext context, String id, String decision) async {
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: Text(decision == 'approved' ? 'Approve leave?' : 'Reject leave?'),
        content: TextField(controller: note,
          maxLength: 240, maxLines: 2,
          decoration: const InputDecoration(labelText: 'Decision note (optional)')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm'))],
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (confirmed != true || !context.mounted) return;
    try {
      final reference = repository.db.collection('staffLeaveRequests').doc(id);
      await repository.db.runTransaction((transaction) async {
        final current = await transaction.get(reference);
        if (!current.exists || current.data()?['status'] != 'pending') {
          throw StateError('This leave request has already been reviewed.');
        }
        transaction.update(reference, {
          'status': decision,
          'decisionNote': text,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Leave request ${decision == 'approved' ? 'approved' : 'rejected'}.')));
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Unable to update leave. Check your permissions or refresh.')));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Leave Requests', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      const Text('Review time-off requests before generating the weekly schedule.',
        style: TextStyle(fontSize: 13, color: Color(0xFF847C7A))),
      const SizedBox(height: 14),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: repository.db.collection('staffLeaveRequests').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return const Card(child: Padding(
            padding: EdgeInsets.all(20), child: Text('Leave requests could not be loaded. Check Firestore permissions.')));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final requests = snap.data!.docs.toList()..sort((a,b) =>
              (a.data()['status'] == 'pending' ? '0' : '1').compareTo(
                b.data()['status'] == 'pending' ? '0' : '1'));
          if (requests.isEmpty) return const Card(child: Padding(
            padding: EdgeInsets.all(20), child: Text('No leave requests yet.')));
          return Column(children: [
            for (final request in requests)
              Card(child: ListTile(
                leading: Icon(request.data()['status'] == 'pending'
                  ? Icons.hourglass_top : Icons.event_available_outlined),
                title: Text('${request.data()['staffName'] ?? request.data()['staffUid'] ?? 'Staff'} · ${request.data()['leaveType'] ?? 'Leave'}'),
                subtitle: Text('${request.data()['startOn'] ?? ''} to ${request.data()['endOn'] ?? ''}\n${request.data()['reason'] ?? ''}'),
                isThreeLine: true,
                trailing: request.data()['status'] == 'pending'
                  ? Wrap(spacing: 6, children: [
                    OutlinedButton(onPressed: () => _decide(context,request.id,'rejected'), child: const Text('Reject')),
                    FilledButton(onPressed: () => _decide(context,request.id,'approved'), child: const Text('Approve')),
                  ]) : Text((request.data()['status'] ?? 'unknown').toString()),
              )),
          ]);
        },
      ),
    ],
  );
}
