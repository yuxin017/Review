import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'staff_access.dart';
import 'staff_records.dart';
import 'staff_records_repository.dart';

/// Generates a *draft* seven-day rota. Only a Super Admin can load this
/// screen or write drafts (enforced by firestore.rules). Drafts do not grant
/// any operational staff permissions and are never automatically published.
class StaffAutoSchedulePage extends StatefulWidget {
  const StaffAutoSchedulePage({super.key, required this.repository});
  final StaffRecordsRepository repository;

  @override
  State<StaffAutoSchedulePage> createState() => _StaffAutoSchedulePageState();
}

class _RotaAssignment {
  const _RotaAssignment(this.day, this.person, this.role, this.attractionId);
  final DateTime day;
  final StaffProfile person;
  final StaffRole role;
  final String? attractionId;
}

class _StaffAutoSchedulePageState extends State<StaffAutoSchedulePage> {
  late DateTime weekStart = DateUtils.dateOnly(DateTime.now());
  final Set<StaffRole> enabledRoles = {
    StaffRole.operationsManager,
    StaffRole.admissionStaff,
    StaffRole.attractionOperator,
    StaffRole.photographer,
    StaffRole.photoCounterStaff,
    StaffRole.customerSupport,
    StaffRole.marketingStaff,
  };
  List<_RotaAssignment> assignments = [];
  List<String> gaps = [];
  bool busy = false;
  String? notice;
  String? error;

  String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _generate() async {
    if (busy) return;
    setState(() { busy = true; error = null; notice = null; });
    try {
      // Server-protected directory and qualification records. Do not
      // schedule inactive, unapproved or untrained frontline employees.
      final people = (await widget.repository.watchStaffDirectory().first)
          .where((p) => p.isActive).toList();
      final snapshot = await widget.repository.db
          .collection('staffQualifications').get();
      final training = <StaffQualification>[];
      for (final doc in snapshot.docs) {
        try {
          training.add(StaffQualification.fromMap(doc.id, doc.data()));
        } catch (_) {
          // A malformed training record must never grant eligibility.
        }
      }
      final result = <_RotaAssignment>[];
      final missing = <String>[];
      final weeklyCount = <String, int>{};
      final occupied = <String>{};
      final roles = StaffRole.values.where((r) =>
          r != StaffRole.superAdmin && enabledRoles.contains(r)).toList();
      for (var offset = 0; offset < 7; offset++) {
        final date = weekStart.add(Duration(days: offset));
        final at = DateTime(date.year, date.month, date.day, 9);
        for (final role in roles) {
          final options = <_RotaAssignment>[];
          for (final person in people) {
            if (!person.eligibleRoles.contains(role) ||
                (weeklyCount[person.uid] ?? 0) >= 5 ||
                occupied.contains('${_date(date)}:${person.uid}')) continue;
            String? ride;
            if (role == StaffRole.attractionOperator) {
              for (final qualification in training) {
                if (qualification.staffUid == person.uid &&
                    qualification.role == role &&
                    qualification.validAt(at) &&
                    qualification.attractionId != null &&
                    qualification.attractionId!.isNotEmpty) {
                  ride = qualification.attractionId;
                  break;
                }
              }
              if (ride == null) continue;
            } else if (!StaffTrainingPolicy.isEligible(
              staff: person, qualifications: training, role: role,
              at: at,
            )) {
              continue;
            }
            options.add(_RotaAssignment(date, person, role, ride));
          }
          options.sort((a, b) {
            final count = (weeklyCount[a.person.uid] ?? 0)
                .compareTo(weeklyCount[b.person.uid] ?? 0);
            if (count != 0) return count;
            return a.person.fullName.compareTo(b.person.fullName);
          });
          if (options.isEmpty) {
            missing.add('${_date(date)} — ${role.label}: no available qualified staff');
            continue;
          }
          final chosen = options.first;
          result.add(chosen);
          occupied.add('${_date(date)}:${chosen.person.uid}');
          weeklyCount[chosen.person.uid] =
              (weeklyCount[chosen.person.uid] ?? 0) + 1;
        }
      }
      if (!mounted) return;
      setState(() {
        assignments = result;
        gaps = missing;
        notice = 'Draft generated. Review coverage before saving.';
      });
    } catch (_) {
      if (mounted) setState(() => error =
          'Could not load staff or training records. Check your connection and Admin permissions.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _saveDraft() async {
    if (busy || assignments.isEmpty) return;
    setState(() { busy = true; error = null; notice = null; });
    try {
      final batch = widget.repository.db.batch();
      for (final shift in assignments) {
        final key = '${_date(shift.day)}_${shift.role.code}';
        final starts = DateTime(shift.day.year, shift.day.month,
            shift.day.day, 9);
        final ends = DateTime(shift.day.year, shift.day.month,
            shift.day.day, 17);
        batch.set(widget.repository.db.collection('staffShiftDrafts').doc(key), {
          'staffUid': shift.person.uid,
          'staffName': shift.person.fullName,
          'roleCode': shift.role.code,
          'startsAt': Timestamp.fromDate(starts.toUtc()),
          'endsAt': Timestamp.fromDate(ends.toUtc()),
          'attractionIds': shift.attractionId == null
              ? <String>[] : <String>[shift.attractionId!],
          'published': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      if (mounted) setState(() => notice =
          'Draft saved to Firebase. It is NOT published or active.');
    } on FirebaseException catch (e) {
      if (mounted) setState(() => error = e.code == 'permission-denied'
          ? 'Saving drafts is not permitted. Deploy the included Firestore Rules as an administrator.'
          : 'Could not save the draft. Check your connection and try again.');
    } catch (_) {
      if (mounted) setState(() => error = 'Could not save the schedule draft. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auto Staff Scheduling')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Generate a 7-day rota', style: TextStyle(
          fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 7),
        const Text('One 9:00 AM–5:00 PM shift per selected role per day. '
            'Maximum 5 shifts per employee; no overlapping shifts. '
            'Only active, trained staff are assigned. Review actual '
            'availability and leave manually before publishing.'),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: busy ? null : () async {
            final chosen = await showDatePicker(
              context: context, initialDate: weekStart,
              firstDate: DateTime(2024), lastDate: DateTime(2035),
            );
            if (chosen != null && mounted) setState(() {
              weekStart = chosen;
              assignments = [];
              gaps = [];
            });
          },
          icon: const Icon(Icons.event),
          label: Text('Start date: ${_date(weekStart)}'),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final role in StaffRole.values)
            if (role != StaffRole.superAdmin)
              FilterChip(
                label: Text(role.label),
                selected: enabledRoles.contains(role),
                onSelected: busy ? null : (selected) => setState(() {
                  if (selected) { enabledRoles.add(role); }
                  else { enabledRoles.remove(role); }
                  assignments = [];
                  gaps = [];
                }),
              ),
        ]),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy || enabledRoles.isEmpty ? null : _generate,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Generate Schedule'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(error!, style: const TextStyle(color: Colors.red)),
        ),
        if (notice != null) Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(notice!, style: const TextStyle(color: Color(0xFF27734F))),
        ),
        if (assignments.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('${assignments.length} assignments', style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          for (final shift in assignments)
            Card(child: ListTile(
              title: Text('${_date(shift.day)} · ${shift.role.label}'),
              subtitle: Text('${shift.person.fullName} · 09:00–17:00'
                  '${shift.attractionId == null ? '' : ' · Attraction: ${shift.attractionId}'}'),
            )),
        ],
        if (gaps.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Coverage gaps — resolve before saving', style:
              TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          for (final gap in gaps) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(gap),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: busy || assignments.isEmpty
              ? null : _saveDraft,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save Draft to Firebase'),
        ),
        const SizedBox(height: 8),
        const Text('Drafts do not activate employee access or replace published '
            'shifts. This feature does not yet account for leave requests, '
            'minimum rest periods, or staffing demand by attraction.'),
      ]),
    );
  }
}
