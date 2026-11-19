import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'staff_records_repository.dart';
import 'staff_schedule_utils.dart';

/// Admin checks submitted availability for any historical or future week.
class StaffAvailabilityReviewPage extends StatefulWidget {
  const StaffAvailabilityReviewPage({super.key, required this.repository});
  final StaffRecordsRepository repository;
  @override
  State<StaffAvailabilityReviewPage> createState() => _StaffAvailabilityReviewPageState();
}

class _StaffAvailabilityReviewPageState extends State<StaffAvailabilityReviewPage> {
  DateTime monday = StaffWeek.start(DateTime.now());
  void move(int weeks) => setState(() {
    monday = monday.add(Duration(days: 7 * weeks));
  });

  @override
  Widget build(BuildContext context) {
    final weekKey = StaffWeek.key(monday);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Staff Availability',
        style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      const Text('Who can work each day? Check this before generating the schedule.',
        style: TextStyle(color: Color(0xFF7B7071), fontSize: 13)),
      const SizedBox(height: 14),
      Card(child: Padding(padding: const EdgeInsets.all(14),
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(onPressed: () => move(-1),
            icon: const Icon(Icons.chevron_left), label: const Text('Previous')),
          OutlinedButton.icon(icon: const Icon(Icons.calendar_today_outlined),
            label: Text('$weekKey to ${StaffWeek.key(StaffWeek.day(monday, 6))}'),
            onPressed: () async {
              final chosen = await showDatePicker(context: context,
                initialDate: monday,
                firstDate: DateTime(2025), lastDate: DateTime(2035));
              if (chosen != null && mounted) setState(() =>
                monday = StaffWeek.start(chosen));
            }),
          OutlinedButton.icon(onPressed: () => move(1),
            icon: const Icon(Icons.chevron_right), label: const Text('Next')),
        ]))),
      const SizedBox(height: 12),
      StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
        stream: widget.repository.db.collection('staffAvailability')
          .where('weekStart', isEqualTo: weekKey).snapshots(),
        builder: (context, availabilitySnap) {
          if (availabilitySnap.hasError) return const Card(child: Padding(
            padding: EdgeInsets.all(18),
            child: Text('Unable to read staff availability. Workforce rules may not be deployed.')));
          if (!availabilitySnap.hasData) return const LinearProgressIndicator();
          final byUid = {
            for (final doc in availabilitySnap.data!.docs)
              doc.data()['staffUid']?.toString() ?? '': doc.data(),
          };
          return StreamBuilder(
            stream: widget.repository.watchStaffDirectory(),
            builder: (context, directorySnap) {
              if (directorySnap.hasError) return const Card(child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('Could not load staff accounts.')));
              if (!directorySnap.hasData) return const LinearProgressIndicator();
              final staff = directorySnap.data!.where((p) => p.isActive).toList();
              final submitted = staff.where((p) => byUid.containsKey(p.uid)).length;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Card(color: const Color(0xFFF8EFEC),
                  child: Padding(padding: const EdgeInsets.all(18),
                    child: Text('$submitted of ${staff.length} active staff '
                      'submitted availability for this week',
                      style: const TextStyle(fontWeight: FontWeight.w700)))),
                if (staff.isEmpty) const Card(child: ListTile(
                  title: Text('No active staff to schedule'))),
                for (final person in staff)
                  Card(child: Padding(padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(byUid.containsKey(person.uid)
                            ? Icons.check_circle_outline : Icons.schedule,
                            color: byUid.containsKey(person.uid)
                              ? const Color(0xFF5F8D71) : const Color(0xFFAA8066)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(person.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w700))),
                          Text(byUid.containsKey(person.uid) ? 'Submitted' : 'Not submitted',
                            style: const TextStyle(fontSize: 12)),
                        ]),
                        if (byUid.containsKey(person.uid)) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (var offset = 0; offset < 7; offset++)
                              Builder(builder: (context) {
                                final day = StaffWeek.day(monday,offset);
                                final available = (byUid[person.uid]?['availableDays'] as List?)
                                  ?.contains(StaffWeek.key(day)) == true;
                                return Chip(label: Text(const ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][offset]),
                                  backgroundColor: available
                                    ? const Color(0xFFE1F0E5) : const Color(0xFFF6EEEB),
                                  labelStyle: TextStyle(fontSize: 11,
                                    color: available ? const Color(0xFF386E50)
                                      : const Color(0xFF9E9390)),
                                );
                              }),
                          ]),
                        ],
                      ]))),
              ]);
            },
          );
        },
      ),
    ]);
  }
}
