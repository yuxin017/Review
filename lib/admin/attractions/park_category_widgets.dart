import 'package:flutter/material.dart';

import '../../attractions/models/attraction.dart';
import '../portal/admin_theme.dart';
import 'data/park_category_repository.dart';

String facilityTypeLabel(ParkPlaceKind kind) => switch (kind) {
  ParkPlaceKind.attractions => 'Attractions',
  ParkPlaceKind.dining => 'Food & Drink',
  ParkPlaceKind.facilities => 'Facilities',
  ParkPlaceKind.shops => 'Shops',
};

class ParkCategoryPicker extends StatelessWidget {
  const ParkCategoryPicker({
    super.key,
    required this.kind,
    required this.repository,
    required this.selectedId,
    required this.selectedName,
    required this.enabled,
    required this.onSelected,
  });
  final ParkPlaceKind kind;
  final ParkCategoryRepository? repository;
  final String? selectedId;
  final String? selectedName;
  final bool enabled;
  final ValueChanged<ParkCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    if (repository == null) {
      // Keep direct, repository-free editor widget tests usable. Production
      // passes the authenticated admin repository from Park Facilities.
      final names = kind == ParkPlaceKind.attractions
          ? ['Thrill rides', 'Family rides', 'Water rides', 'Shows']
          : [facilityTypeLabel(kind)];
      final selected = names.contains(selectedName) ? selectedName : null;
      return DropdownButtonFormField<String>(
        key: ValueKey('legacy-category-$selected'),
        initialValue: selected,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Category *'),
        items: [for (final name in names)
          DropdownMenuItem(value: name, child: Text(name))],
        onChanged: enabled ? (name) {
          if (name != null) {
            onSelected(ParkCategory(
              id: '', kind: kind, name: name, active: true));
          }
        } : null,
        validator: (_) => selectedName == null ? 'Select a category.' : null,
      );
    }
    return StreamBuilder<List<ParkCategory>>(
      stream: repository!.watchAll(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Could not load categories. Try again.',
              style: TextStyle(color: Colors.red));
        }
        final values = (snapshot.data ?? [])
            .where((category) => category.kind == kind &&
                (category.active || category.id == selectedId))
            .toList();
        final selected = values.any((c) => c.id == selectedId)
            ? selectedId : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('catalogue-category-${kind.name}-$selected-${values.length}'),
              initialValue: selected,
              isExpanded: true,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(labelText: 'Category *'),
              items: [for (final category in values)
                DropdownMenuItem(
                  value: category.id,
                  child: Text(category.active ? category.name :
                      '${category.name} (Archived)',
                      overflow: TextOverflow.ellipsis),
                )],
              onChanged: enabled && snapshot.hasData
                  ? (id) {
                    if (id == null) return;
                    final category = values.firstWhere((item) => item.id == id);
                    if (category.active) onSelected(category);
                  } : null,
              validator: (_) => selected == null ? 'Select a category.' : null,
            ),
            if (snapshot.hasData && values.where((c) => c.active).isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Add a category under Manage Categories first.',
                    style: TextStyle(color: AdminTheme.muted, fontSize: 12)),
              ),
          ],
        );
      },
    );
  }
}

class ParkCategoryManagementTab extends StatefulWidget {
  const ParkCategoryManagementTab({super.key, required this.repository});
  final ParkCategoryRepository repository;

  @override
  State<ParkCategoryManagementTab> createState() =>
      _ParkCategoryManagementTabState();
}

class _ParkCategoryManagementTabState extends State<ParkCategoryManagementTab> {
  ParkPlaceKind _kind = ParkPlaceKind.attractions;
  final _busyIds = <String>{};

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _error(Object error) {
    if (error is ArgumentError) return error.message?.toString() ?? 'Check the name.';
    if (error is StateError) return error.message;
    return 'Could not save changes. Try again.';
  }

  Future<String?> _nameDialog({ParkCategory? current}) async {
    final controller = TextEditingController(text: current?.name ?? '');
    final form = GlobalKey<FormState>();
    final answer = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFFFFFBFA),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(current == null ? 'Add Category' : 'Edit Category',
                      style: const TextStyle(fontSize: 23,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(facilityTypeLabel(current?.kind ?? _kind),
                      style: const TextStyle(color: AdminTheme.muted)),
                  const SizedBox(height: 22),
                  TextFormField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 60,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Category name *'),
                    validator: ParkCategoryRepository.validateName,
                    onFieldSubmitted: (_) {
                      if (form.currentState!.validate()) {
                        Navigator.of(context).pop(controller.text.trim());
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'))),
                    const SizedBox(width: 12),
                    Expanded(child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AdminTheme.rose),
                      onPressed: () {
                        if (form.currentState!.validate()) {
                          Navigator.pop(context, controller.text.trim());
                        }
                      },
                      child: Text(current == null ? 'Add Category' : 'Save Changes'))),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    return answer;
  }

  Future<void> _add() async {
    final name = await _nameDialog();
    if (name == null || !mounted) return;
    try {
      await widget.repository.add(_kind, name);
      _notice('Category added.');
    } catch (error) {
      _notice(_error(error));
    }
  }

  Future<void> _rename(ParkCategory item) async {
    final name = await _nameDialog(current: item);
    if (name == null || !mounted) return;
    setState(() => _busyIds.add(item.id));
    try {
      await widget.repository.rename(item, name);
      _notice('Category updated.');
    } catch (error) {
      _notice(_error(error));
    } finally {
      if (mounted) setState(() => _busyIds.remove(item.id));
    }
  }

  Future<void> _toggle(ParkCategory item) async {
    setState(() => _busyIds.add(item.id));
    try {
      await widget.repository.setActive(item, !item.active);
      _notice(item.active ? 'Category archived.' : 'Category restored.');
    } catch (error) {
      _notice(_error(error));
    } finally {
      if (mounted) setState(() => _busyIds.remove(item.id));
    }
  }

  Future<void> _delete(ParkCategory item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category?'),
        content: Text('Delete "${item.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busyIds.add(item.id));
    try {
      await widget.repository.remove(item);
      _notice('Category deleted.');
    } catch (error) {
      _notice(_error(error));
    } finally {
      if (mounted) setState(() => _busyIds.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<ParkCategory>>(
    stream: widget.repository.watchAll(),
    builder: (context, snapshot) {
      final records = (snapshot.data ?? []).where((c) => c.kind == _kind)
          .toList();
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBFA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE9DCD9)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12, runSpacing: 12,
                children: [
                  const Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Manage Categories', style: TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w700)),
                      SizedBox(height: 3),
                      Text('Organize the categories shown when adding places.',
                          style: TextStyle(color: AdminTheme.muted)),
                    ]),
                  FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Category'),
                    style: FilledButton.styleFrom(backgroundColor: AdminTheme.rose),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final kind in ParkPlaceKind.values)
                  ChoiceChip(
                    label: Text(facilityTypeLabel(kind)),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ]),
              const SizedBox(height: 16),
              if (snapshot.hasError)
                const Padding(padding: EdgeInsets.all(16),
                    child: Text('Could not load categories. Try again.'))
              else if (!snapshot.hasData)
                const Center(child: Padding(
                    padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else if (records.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 35),
                    child: Center(child: Text('No categories yet. Add one to begin.')))
              else
                for (final item in records)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFECE4E1)),
                      ),
                      child: ListTile(
                        title: Text(item.name, style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                        subtitle: Text(item.active ? 'Active' : 'Archived'),
                        trailing: _busyIds.contains(item.id)
                          ? const SizedBox(width: 30, height: 30,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Wrap(spacing: 1, children: [
                              IconButton(tooltip: 'Edit category',
                                onPressed: () => _rename(item),
                                icon: const Icon(Icons.edit_outlined)),
                              IconButton(tooltip: item.active ? 'Archive' : 'Restore',
                                onPressed: () => _toggle(item),
                                icon: Icon(item.active ? Icons.archive_outlined :
                                    Icons.unarchive_outlined)),
                              IconButton(tooltip: 'Delete category',
                                onPressed: () => _delete(item),
                                icon: const Icon(Icons.delete_outline,
                                    color: Color(0xFFB43B45))),
                            ]),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      );
    },
  );
}
