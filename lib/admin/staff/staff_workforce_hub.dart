import 'package:flutter/material.dart';
import 'staff_records_repository.dart';
import 'staff_management_page.dart';
import 'staff_schedule_review_page.dart';
import 'staff_leave_review_page.dart';

/// Separate workforce pages under one consistent Admin work area.
class StaffWorkforceHub extends StatefulWidget {
  const StaffWorkforceHub({super.key, required this.repository});
  final StaffRecordsRepository repository;
  @override
  State<StaffWorkforceHub> createState() => _StaffWorkforceHubState();
}

class _StaffWorkforceHubState extends State<StaffWorkforceHub> {
  int selected = 0;
  static const names = ['Staff Accounts','Weekly Schedule','Leave Requests'];
  static const icons = [Icons.badge_outlined, Icons.calendar_month_outlined,
    Icons.event_note_outlined];
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < names.length; i++)
          ChoiceChip(
            label: Text(names[i]), avatar: Icon(icons[i],size:18),
            selected: selected == i, onSelected: (_) => setState(() => selected = i)),
      ]),
      const SizedBox(height: 18),
      if (selected == 0) StaffManagementPage(repository: widget.repository),
      if (selected == 1) StaffScheduleReviewPage(repository: widget.repository),
      if (selected == 2) StaffLeaveReviewPage(repository: widget.repository),
    ],
  );
}
