import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../attractions/models/attraction.dart';
import '../../attractions/data/slot_reader.dart';
import '../../attractions/widgets/attraction_widgets.dart';
import '../portal/admin_panel.dart';
import '../portal/admin_theme.dart';
import 'attraction_admin_guard.dart';
import 'attraction_editor_page.dart';
import 'park_category_widgets.dart';
import 'data/park_category_repository.dart';
import '../../attractions/widgets/attraction_cover.dart';
import 'data/admin_attraction_store.dart';

class AttractionsAdminPage extends StatefulWidget {
  const AttractionsAdminPage({
    super.key,
    required this.store,
    required this.adminAccess,
    this.slotReader,
  });
  final AdminAttractionStore store;
  final ValueListenable<bool> adminAccess;
  final SlotReader? slotReader;

  @override
  State<AttractionsAdminPage> createState() => _AttractionsAdminPageState();
}

class _AttractionsAdminPageState extends State<AttractionsAdminPage> {
  late Stream<List<Attraction>> _stream;
  final _search = TextEditingController();
  AttractionStatus? _status;
  String? _category;
  ParkPlaceKind? _kindFilter;
  bool _categoriesTab = false;
  ParkCategoryRepository? _categoryRepository;
  int _page = 0;
  static const _pageSize = 10;
  final _deleting = <String>{};
  final _confirmingDelete = <String>{};

  @override
  void initState() {
    super.initState();
    _subscribe();
    try {
      _categoryRepository = ParkCategoryRepository(
        FirebaseFirestore.instanceFor(app: Firebase.app('ThemeParkAdmin')),
      );
    } catch (_) {
      // UI tests can inject a store without Firebase initialization.
    }
    widget.adminAccess.addListener(_accessChanged);
  }

  @override
  void didUpdateWidget(AttractionsAdminPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adminAccess != widget.adminAccess) {
      oldWidget.adminAccess.removeListener(_accessChanged);
      widget.adminAccess.addListener(_accessChanged);
      _subscribe();
    }
    if (oldWidget.store != widget.store) _subscribe();
  }

  @override
  void dispose() {
    widget.adminAccess.removeListener(_accessChanged);
    _search.dispose();
    super.dispose();
  }

  void _subscribe() => _stream = widget.store.watchAttractions();

  void _accessChanged() {
    if (mounted && widget.adminAccess.value) setState(_subscribe);
  }

  void _deleteMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addPlace() async {
    final kind = await showDialog<ParkPlaceKind>(
      context: context,
      useRootNavigator: false,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a facility type'),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        children: [
          for (final item in ParkPlaceKind.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(item),
              child: Row(
                children: [
                  Icon(parkPlaceIcon(item), color: AdminTheme.rose, size: 20),
                  const SizedBox(width: 12),
                  Text(facilityTypeLabel(item)),
                ],
              ),
            ),
        ],
      ),
    );
    if (mounted && kind != null) await _edit(kind: kind);
  }

  Future<void> _edit({
    Attraction? attraction,
    ParkPlaceKind kind = ParkPlaceKind.attractions,
  }) async {
    if (!widget.adminAccess.value ||
        _deleting.contains(attraction?.id) ||
        _confirmingDelete.contains(attraction?.id)) {
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AttractionEditorPage(
          store: widget.store,
          adminAccess: widget.adminAccess,
          attraction: attraction,
          kind: kind,
          slotReader: widget.slotReader,
          categoryRepository: _categoryRepository,
        ),
      ),
    );
    if (mounted && saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (attraction?.isRide ?? kind == ParkPlaceKind.attractions)
                ? 'Attraction saved successfully.'
                : 'Park place saved successfully.',
          ),
        ),
      );
    }
  }

  Future<void> _delete(Attraction attraction) async {
    if (!widget.adminAccess.value ||
        _deleting.contains(attraction.id) ||
        _confirmingDelete.contains(attraction.id)) {
      return;
    }
    _confirmingDelete.add(attraction.id);
    final itemName = attraction.placeKind.itemName;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => ValueListenableBuilder<bool>(
          valueListenable: widget.adminAccess,
          builder: (context, allowed, _) => AlertDialog(
            title: Text('Delete $itemName?'),
            content: Text(
              attraction.isRide
                  ? '“${attraction.name}” will be removed from the customer app and active admin list. Its Firebase record and linked sessions are kept for booking history. You cannot undo this from the portal.'
                  : '“${attraction.name}” will be removed from the park map and active admin list.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: allowed ? () => Navigator.pop(context, true) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB43B45),
                ),
                child: Text('Delete $itemName'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted || !widget.adminAccess.value) return;
      setState(() => _deleting.add(attraction.id));
      await widget.store.deleteAttraction(attraction);
      if (mounted && widget.adminAccess.value) {
        _deleteMessage(
          attraction.isRide ? 'Attraction deleted.' : 'Park place deleted.',
        );
      }
    } catch (error) {
      if (mounted && widget.adminAccess.value) {
        _deleteMessage(
          error is AttractionConflict
              ? error.message
              : 'Could not delete the $itemName. ${attractionErrorMessage(error)}',
        );
      }
    } finally {
      _confirmingDelete.remove(attraction.id);
      if (mounted) setState(() => _deleting.remove(attraction.id));
    }
  }

  Widget _stats(List<Attraction>? records) {
    final values = [
      records?.length,
      ...AttractionStatus.values.map(
        (status) => records?.where((item) => item.status == status).length,
      ),
    ];
    const labels = ['Total Park Places', 'Open', 'Closed', 'Maintenance'];
    const notes = [
      'All mapped places',
      'Available to visitors',
      'Currently unavailable',
      'Under maintenance',
    ];
    const icons = [
      Icons.attractions_outlined,
      Icons.check_circle_outline,
      Icons.pause_circle_outline,
      Icons.build_outlined,
    ];
    const colors = [
      AdminTheme.rose,
      Color(0xFF329253),
      Color(0xFFC84E55),
      Color(0xFFCE8A25),
    ];
    return AdminOverviewGrid(
      cards: [
        for (var index = 0; index < labels.length; index++)
          AdminOverviewCard(
            label: labels[index],
            note: notes[index],
            count: values[index],
            icon: icons[index],
            color: colors[index],
            countColor: index == 0 ? AdminTheme.ink : null,
          ),
      ],
    );
  }

  String _catalogueCategory(Attraction item) => item.category;

  Widget _filters(List<Attraction> all) {
    final categories = all.where((item) => _kindFilter == null || item.placeKind == _kindFilter).map(_catalogueCategory).toSet().toList()..sort();
    final category = categories.contains(_category) ? _category : null;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Search places by name',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
              onChanged: (_) => setState(() => _page = 0),
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<AttractionStatus>(
              key: ValueKey('filter-status-${_status?.name ?? 'all'}'),
              initialValue: _status,
              isExpanded: true,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              items: [
                const DropdownMenuItem(child: Text('All Statuses')),
                for (final status in AttractionStatus.values)
                  DropdownMenuItem(
                    value: status,
                    child: Text(attractionStatusLabel(status)),
                  ),
              ],
              onChanged: (value) => setState(() {
                _status = value;
                _page = 0;
              }),
            ),
          ),
          SizedBox(
            width: 185,
            child: DropdownButtonFormField<String>(
              key: ValueKey('filter-category-${category ?? 'all'}'),
              initialValue: category,
              isExpanded: true,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              items: [
                const DropdownMenuItem(child: Text('All Categories')),
                for (final value in categories)
                  DropdownMenuItem(value: value, child: Text(value)),
              ],
              onChanged: (value) => setState(() {
                _category = value;
                _page = 0;
              }),
            ),
          ),
          IconButton(
            tooltip: 'Refresh park places',
            onPressed: () => setState(_subscribe),
            icon: const Icon(Icons.refresh, color: AdminTheme.muted),
          ),
          if (_search.text.isNotEmpty || _status != null || category != null || _kindFilter != null)
            TextButton(
              onPressed: () => setState(() {
                _search.clear();
                _status = null;
                _category = null;
                _kindFilter = null;
                _page = 0;
              }),
              child: const Text('Clear filters'),
            ),
        ],
      ),
    );
  }

  Widget _table(List<Attraction> all) {
    final category = all.any((item) => _catalogueCategory(item) == _category)
        ? _category
        : null;
    final query = _search.text.trim().toLowerCase();
    final visible = all
        .where(
          (item) =>
              (item.name.toLowerCase().contains(query) ||
                  item.id.toLowerCase().contains(query)) &&
              (_kindFilter == null || item.placeKind == _kindFilter) &&
              (_status == null || item.status == _status) &&
              (category == null || _catalogueCategory(item) == category),
        )
        .toList();
    final pages = math.max(1, (visible.length / _pageSize).ceil());
    final page = math.min(_page, pages - 1);
    final start = page * _pageSize;
    final rows = visible.skip(start).take(_pageSize).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              label: const Text('All places'),
              selected: _kindFilter == null,
              onSelected: (_) => setState(() { _kindFilter = null; _category = null; _page = 0; }),
            ),
            for (final kind in ParkPlaceKind.values)
              ChoiceChip(
                label: Text(facilityTypeLabel(kind)),
                selected: _kindFilter == kind,
                onSelected: (_) => setState(() { _kindFilter = kind; _category = null; _page = 0; }),
              ),
          ]),
        ),
        _filters(all),
        const Divider(),
        if (all.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: AttractionMessage(
              icon: Icons.attractions_outlined,
              title: 'No park places yet',
              message: 'Add a park place to make it visible to visitors.',
            ),
          )
        else if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: AttractionMessage(
              icon: Icons.search_off,
              title: 'No matching park places',
              message: 'Change or clear the filters to see more places.',
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: math.max(850, constraints.maxWidth),
                ),
                child: DataTable(
                  columnSpacing: 24,
                  horizontalMargin: 20,
                  headingRowHeight: 48,
                  dataRowMinHeight: 72,
                  dataRowMaxHeight: 86,
                  dividerThickness: .5,
                  headingTextStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.ink,
                  ),
                  dataTextStyle: const TextStyle(
                    fontSize: 12,
                    color: AdminTheme.ink,
                  ),
                  columns: const [
                    DataColumn(label: Text('Place')),
                    DataColumn(label: Text('Type')),
                    DataColumn(label: Text('Category')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Ride capacity / duration')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: [
                    for (final item in rows)
                      DataRow(
                        key: ValueKey('admin-${item.id}'),
                        cells: [
                          DataCell(
                            SizedBox(
                              width: 220,
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: AttractionCover(
                                      encoded: item.coverImageBase64,
                                      width: 48,
                                      height: 48,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.name, maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 3),
                                        Text(item.isRide ? 'Ride attraction' : facilityTypeLabel(item.placeKind),
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11, color: AdminTheme.muted)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            onTap: () => _edit(attraction: item),
                          ),
                          DataCell(Text(facilityTypeLabel(item.placeKind))),
                          DataCell(Text(item.category)),
                          DataCell(AttractionStatusBadge(status: item.status)),
                          DataCell(Text(item.isRide
                              ? '${item.ridersPerCycle ?? '—'} riders • ${item.rideDurationMinutes ?? '—'} min'
                              : 'Not applicable')),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit ${item.name}',
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  onPressed: _deleting.contains(item.id)
                                      ? null
                                      : () => _edit(attraction: item),
                                ),
                                IconButton(
                                  tooltip: 'Delete ${item.name}',
                                  onPressed: _deleting.contains(item.id)
                                      ? null
                                      : () => _delete(item),
                                  icon: _deleting.contains(item.id)
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.delete_outline,
                                          color: Color(0xFFB43B45),
                                          size: 19,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                visible.isEmpty
                    ? 'Showing 0 results'
                    : 'Showing ${start + 1} to ${math.min(start + _pageSize, visible.length)} of ${visible.length} results',
                style: const TextStyle(fontSize: 12, color: AdminTheme.muted),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: page == 0
                        ? null
                        : () => setState(() => _page = page - 1),
                    icon: const Icon(Icons.chevron_left, size: 20),
                  ),
                  Text(
                    'Page ${page + 1} of $pages',
                    style: const TextStyle(fontSize: 12),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: page + 1 >= pages
                        ? null
                        : () => setState(() => _page = page + 1),
                    icon: const Icon(Icons.chevron_right, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '10 / page',
                    style: TextStyle(fontSize: 12, color: AdminTheme.muted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AttractionAdminGuard(
    access: widget.adminAccess,
    child: Scaffold(
      backgroundColor: AdminTheme.background,
      body: StreamBuilder<List<Attraction>>(
        stream: _stream,
        builder: (context, snapshot) {
          final records =
              snapshot.hasError ||
                  snapshot.connectionState == ConnectionState.waiting
              ? null
              : snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(28),
            children: [
              Wrap(
                spacing: 20,
                runSpacing: 16,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Park Facilities',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Manage rides, food, services and shops in one place.',
                        style: TextStyle(color: AdminTheme.muted, fontSize: 13),
                      ),
                    ],
                  ),
                  if (!_categoriesTab) FilledButton.icon(
                    onPressed: _addPlace,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Place'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(spacing: 10, runSpacing: 10, children: [
                ChoiceChip(
                  label: const Text('Places'),
                  selected: !_categoriesTab,
                  onSelected: (_) => setState(() => _categoriesTab = false),
                ),
                ChoiceChip(
                  label: const Text('Manage Categories'),
                  selected: _categoriesTab,
                  onSelected: (_) => setState(() => _categoriesTab = true),
                ),
              ]),
              const SizedBox(height: 18),
              if (!_categoriesTab) ...[
                _stats(records),
                const SizedBox(height: 20),
                AdminPanel(
                child: snapshot.hasError
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: AttractionMessage(
                          icon: Icons.cloud_off_outlined,
                          title: 'Could not load park places',
                          message: attractionErrorMessage(snapshot.error!),
                          action: 'Try again',
                          onAction: () => setState(_subscribe),
                        ),
                      )
                    : records == null
                    ? const Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _table(records),
                ),
              ] else if (_categoryRepository != null)
                ParkCategoryManagementTab(repository: _categoryRepository!)
              else
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Categories unavailable. Reopen the admin portal.'),
                ),
            ],
          );
        },
      ),
    ),
  );
}
