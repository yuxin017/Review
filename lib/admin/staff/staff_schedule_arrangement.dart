import 'staff_access.dart';
import 'staff_records.dart';
import 'staff_schedule_utils.dart';

typedef ScheduleDraft = ({List<StaffShiftPlan> assignments, List<String> gaps});

/// Assigns the most shifts possible under the eligibility, daily and weekly
/// limits. Existing assignments may be rearranged to fill a harder shift.
ScheduleDraft arrangeStaffWeek({
  required DateTime monday,
  required Set<StaffRole> roles,
  required Iterable<StaffProfile> directory,
  required Map<String, Set<String>> availability,
  required Iterable<Map<String, dynamic>> leaves,
  required List<StaffQualification> qualifications,
  Map<String, String>? attractions,
}) {
  final people =
      directory
          .where(
            (person) =>
                person.isActive &&
                !person.eligibleRoles.any(fixedDutyRoles.contains),
          )
          .toList()
        ..sort((a, b) {
          final name = a.fullName.compareTo(b.fullName);
          return name == 0 ? a.uid.compareTo(b.uid) : name;
        });
  final graph = <List<_Edge>>[[], []];
  int node() {
    graph.add([]);
    return graph.length - 1;
  }

  _Edge connect(int from, int to, int capacity) {
    final edge = _Edge(to, graph[to].length, capacity);
    graph[to].add(_Edge(from, graph[from].length, 0));
    graph[from].add(edge);
    return edge;
  }

  final staffNodes = {for (final person in people) person.uid: node()};
  for (final staffNode in staffNodes.values) {
    connect(staffNode, 1, 7);
  }
  final optionalEdges = <_Edge>[];
  final otherRequiredEdges = <_Edge>[];
  final slots =
      <
        ({String label, bool required, List<(_Edge, StaffShiftPlan)> options})
      >[];
  for (var offset = 0; offset < 7; offset++) {
    final date = StaffWeek.day(monday, offset);
    final key = StaffWeek.key(date);
    final start = StaffWeek.parkTime(date, 9);
    final beforeEnd = StaffWeek.parkTime(
      date,
      17,
    ).subtract(const Duration(microseconds: 1));
    final available = people.where(
      (person) =>
          availability[person.uid]?.contains(key) == true &&
          !leaves.any(
            (leave) =>
                leave['staffUid'] == person.uid &&
                staffLeaveIncludes(leave, key),
          ),
    );
    final personDays = {for (final person in available) person.uid: node()};
    for (final entry in personDays.entries) {
      connect(entry.value, staffNodes[entry.key]!, 1);
    }
    for (final role in StaffRole.values) {
      if (role == StaffRole.superAdmin ||
          fixedDutyRoles.contains(role) ||
          !roles.contains(role))
        continue;
      final List<String?> targets = switch (role) {
        StaffRole.attractionOperator =>
          attractions == null ? [null] : attractions.keys.toList(),
        StaffRole.admissionStaff => [null, if (attractions != null) null],
        StaffRole.photographer => [
          null,
          if (attractions != null) ...[null, null],
        ],
        _ => [null],
      };
      for (final (index, target) in targets.indexed) {
        final isRequired = index == 0 || role == StaffRole.attractionOperator;
        final slotNode = node();
        final priorityPost = isRequired &&
            (role == StaffRole.admissionStaff || role == StaffRole.attractionOperator);
        final demand = connect(0, slotNode, priorityPost ? 1 : 0);
        if (!isRequired) {
          optionalEdges.add(demand);
        } else if (!priorityPost) {
          otherRequiredEdges.add(demand);
        }
        final options = <(_Edge, StaffShiftPlan)>[];
        for (final person in available) {
          final valid = qualifications.where(
            (qualification) =>
                qualification.staffUid == person.uid &&
                qualification.role == role &&
                qualification.validAt(start) &&
                qualification.validAt(beforeEnd),
          );
          final attraction = role == StaffRole.attractionOperator
              ? target ??
                    (valid
                            .map((qualification) => qualification.attractionId)
                            .whereType<String>()
                            .where((id) => id.isNotEmpty)
                            .toList()
                          ..sort())
                        .firstOrNull
              : null;
          if (!StaffTrainingPolicy.isEligible(
            staff: person,
            qualifications: valid,
            role: role,
            at: start,
            attractionId: attraction,
          )) {
            continue;
          }
          options.add((
            connect(slotNode, personDays[person.uid]!, 1),
            StaffShiftPlan(
              date: date,
              staffUid: person.uid,
              staffName: person.fullName,
              roleCode: role.code,
              attractionId: attraction,
              slot: index,
              attractionName: attractions?[attraction],
            ),
          ));
        }
        slots.add((
          label:
              '$key · ${role.label}${target == null ? '' : ' · ${attractions?[target] ?? target}'}',
          required: isRequired,
          options: options,
        ));
      }
    }
  }

  // Use residual capacity to move earlier choices when they block another role.
  bool assign(int from, Set<int> visited) {
    if (from == 1) return true;
    if (!visited.add(from)) return false;
    for (final edge in graph[from]) {
      if (edge.remaining == 0 || !assign(edge.to, visited)) continue;
      edge.remaining--;
      graph[edge.to][edge.reverse].remaining++;
      return true;
    }
    return false;
  }

  while (assign(0, <int>{})) {
    // Cover the entrance and individual attractions first.
  }
  for (final edge in otherRequiredEdges) {
    edge.remaining = 1;
  }
  while (assign(0, <int>{})) {
    // Fill other required posts while retaining entrance and ride coverage.
  }
  for (final edge in optionalEdges) {
    edge.remaining = 1;
  }
  while (assign(0, <int>{})) {
    // Add extra entrance and photography coverage after required posts.
  }
  final assignments = <StaffShiftPlan>[];
  final gaps = <String>[];
  for (final slot in slots) {
    final selected = slot.options
        .where((option) => option.$1.remaining == 0)
        .firstOrNull;
    if (selected == null) {
      if (slot.required)
        gaps.add('${slot.label} — no available qualified staff');
    } else {
      assignments.add(selected.$2);
    }
  }
  return (assignments: assignments, gaps: gaps);
}

class _Edge {
  _Edge(this.to, this.reverse, this.remaining);

  final int to, reverse;
  int remaining;
}
