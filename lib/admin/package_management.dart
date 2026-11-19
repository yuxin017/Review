import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'admin_catalog_image.dart';
import 'package:flutter/services.dart';
import '../visitor/models/tickets.dart';
import 'admin_models.dart';
import 'admin_store.dart';
import 'admin_widgets.dart';

class PackageManagement extends StatefulWidget {
  final AdminStore store;
  const PackageManagement({super.key, required this.store});
  @override
  State<PackageManagement> createState() => _PackageManagementState();
}

class _PackageManagementState extends State<PackageManagement> {
  String query = '', status = 'all', category = 'all';
  @override
  Widget build(BuildContext context) {
    final list =
        widget.store.packages
            .where(
              (p) =>
                  (status == 'all' || p.active == (status == 'active')) &&
                  (category == 'all' || p.pass.category == category) &&
                  p.pass.name.toLowerCase().contains(
                    query.toLowerCase().trim(),
                  ),
            )
            .toList()
          ..sort((a, b) => a.pass.sortOrder.compareTo(b.pass.sortOrder));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminHeading(
          'Pass Packages',
          'Manage visitor pass availability and prices',
          action: AdminButton(
            'Add Pass Package',
            icon: Icons.add,
            onPressed: widget.store.busy
                ? null
                : () => editPackage(context, widget.store),
          ),
        ),
        const SizedBox(height: 26),
        AdminStats(
          children: [
            AdminStat(
              'Total Packages',
              '${widget.store.packages.length}',
              'Day, annual and add-on passes',
              Icons.local_activity_outlined,
            ),
            AdminStat(
              'Active',
              '${widget.store.packages.where((p) => p.active).length}',
              'Available in the visitor catalog',
              Icons.check_circle_outline,
              color: const Color(0xFF278D52),
            ),
            AdminStat(
              'Inactive',
              '${widget.store.packages.where((p) => !p.active).length}',
              'Hidden from new bookings',
              Icons.pause_circle_outline,
              color: Colors.orange,
            ),
            AdminStat(
              'Average Adult Fare',
              widget.store.packages.where((p) => p.active).isEmpty
                  ? '—'
                  : money((widget.store.packages.where((p) => p.active)
                      .fold<int>(0, (sum, p) => sum + p.pass.priceMinor) /
                      widget.store.packages.where((p) => p.active).length).round()),
              'Among active admission products',
              Icons.payments_outlined,
              color: const Color(0xFF3978D8),
            ),
          ],
        ),
        const SizedBox(height: 24),
        AdminCard(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 14,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 330,
                child: TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: 'Search pass packages',
                  ),
                ),
              ),
              AdminSelect(
                value: status,
                options: const {
                  'all': 'All Status',
                  'active': 'Active',
                  'inactive': 'Inactive',
                },
                onChanged: (v) => setState(() => status = v),
              ),
              AdminSelect(
                value: category,
                options: const {
                  'all': 'All Categories',
                  'day': 'Day Pass',
                  'annual': 'Annual Pass',
                  'addon': 'Add-ons',
                },
                onChanged: (v) => setState(() => category = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AdminCard(
          padding: EdgeInsets.zero,
          child: list.isEmpty
              ? const AdminEmpty(
                  'No matching pass packages',
                  'Add a pass or change the selected filters.',
                )
              : AdminTable(
                  minWidth: 1000,
                  columns: const [
                    DataColumn(label: Text('Pass Package')),
                    DataColumn(label: Text('Category')),
                    DataColumn(label: Text('Adult Fare')),
                    DataColumn(label: Text('Child Fare')),
                    DataColumn(label: Text('Validity')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: [
                    for (final p in list)
                      DataRow(
                        cells: [
                          DataCell(
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: (p.data['imageUrl'] is String &&
                                      (p.data['imageUrl'] as String).startsWith('https://'))
                                    ? Image.network(p.data['imageUrl'] as String,
                                        width: 65, height: 46, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Image.asset(
                                          p.pass.imageAsset,
                                          width: 65, height: 46, fit: BoxFit.cover))
                                    : Image.asset(p.pass.imageAsset,
                                        width: 65, height: 46, fit: BoxFit.cover),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 220,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.pass.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        p.pass.description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: adminMuted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(
                              p.pass.category == 'annual'
                                  ? 'Annual Pass'
                                  : p.pass.category == 'addon'
                                  ? 'Add-on'
                                  : 'Day Pass',
                            ),
                          ),
                          DataCell(Text(money(p.pass.priceMinor))),
                          DataCell(Text(money(p.pass.childPrice))),
                          DataCell(
                            Text(
                              '${p.pass.durationDays} ${p.pass.durationDays == 1 ? 'day' : 'days'}',
                            ),
                          ),
                          DataCell(
                            AdminBadge(p.active ? 'Active' : 'Inactive'),
                          ),
                          DataCell(
                            AdminButton(
                              'Edit Pass',
                              icon: Icons.edit_outlined,
                              outlined: true,
                              onPressed: widget.store.busy
                                  ? null
                                  : () => editPackage(
                                      context,
                                      widget.store,
                                      package: p,
                                    ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        const AdminCard(
          child: Row(
            children: [
              Icon(Icons.info_outline, color: adminRose, size: 21),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Changes apply to new bookings. Previously issued tickets retain their booked fare and admission dates.',
                  style: TextStyle(fontSize: 12, color: adminMuted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> editPackage(
  BuildContext context,
  AdminStore store, {
  AdminPackage? package,
  String? suggestedName,
}) async {
  final result = await showDialog<PackageDraft>(
    context: context,
    builder: (_) => PackageEditor(package: package, suggestedName: suggestedName),
  );
  if (result == null || !context.mounted) return;
  final done = await store.perform(
    () => store.repository.savePackage(package?.id, result),
  );
  if (done && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pass package saved. The visitor catalog is updated.'),
      ),
    );
  }
}

class PackageEditor extends StatefulWidget {
  final AdminPackage? package;
  final String? suggestedName;
  const PackageEditor({super.key, this.package, this.suggestedName});
  @override
  State<PackageEditor> createState() => _PackageEditorState();
}

class _PackageEditorState extends State<PackageEditor> {
  static const _termsDivider = '\n\nTerms & Conditions:\n';
  final form = GlobalKey<FormState>();

  String get _originalDescription => widget.package?.pass.description ?? '';
  String get _shortDescription => _originalDescription.contains(_termsDivider)
      ? _originalDescription.split(_termsDivider).first
      : _originalDescription;
  String get _previousTerms => _originalDescription.contains(_termsDivider)
      ? _originalDescription.split(_termsDivider).skip(1).join(_termsDivider)
      : '';

  late final name = TextEditingController(
        text: widget.package?.pass.name ?? widget.suggestedName ?? '',
      ),
      description = TextEditingController(text: _shortDescription),
      terms = TextEditingController(text: _previousTerms),
      inclusions = TextEditingController(
        text: widget.package?.pass.benefits.join('\n') ?? '',
      ),
      adult = TextEditingController(
        text: widget.package == null ? '' :
            (widget.package!.pass.priceMinor / 100).toStringAsFixed(2),
      ),
      child = TextEditingController(
        text: widget.package?.pass.childPriceMinor == null ? '' :
            (widget.package!.pass.childPriceMinor! / 100).toStringAsFixed(2),
      ),
      days = TextEditingController(text: '${widget.package?.pass.durationDays ?? 1}'),
      sort = TextEditingController(text: '${widget.package?.pass.sortOrder ?? 0}');

  late String category = widget.package?.pass.category ?? 'day';
  late bool active = widget.package?.active ?? true;
  PlatformFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  String? _imageUrl;
  bool _uploading = false;

  @override
  void dispose() {
    for (final c in [name, description, terms, inclusions, adult, child, days, sort]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.package?.data['imageUrl']?.toString();
  }

  List<String> get _benefits => inclusions.text.split('\n')
      .map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _save() async {
    if (form.currentState?.validate() != true) return;
    final resultDescription =
        '${description.text.trim()}$_termsDivider${terms.text.trim()}';
    if (resultDescription.length > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Public description and terms must stay within 2,000 characters.')),
      );
      return;
    }
    if (_uploading) return;
    if (_selectedImage != null) {
      setState(() => _uploading = true);
      try {
        _imageUrl = await uploadParkCatalogImage(_selectedImage!, 'tickets');
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo upload failed: $e')));
        if (mounted) setState(() => _uploading = false);
        return;
      }
      if (mounted) setState(() => _uploading = false);
      if (!mounted) return;
    }
    Navigator.pop(context, PackageDraft(
      imageUrl: _imageUrl,
      name: name.text.trim(),
      description: resultDescription,
      category: category,
      priceMinor: parseMoneyMinor(adult.text)!,
      childPriceMinor: child.text.trim().isEmpty ? null : parseMoneyMinor(child.text),
      durationDays: int.parse(days.text),
      sortOrder: int.parse(sort.text),
      active: active,
      benefits: _benefits,
    ));
  }

  // Polished editor presentation. The existing _save() and editPackage()
  // remain the only path to PackageDraft and Firebase persistence.
  static const _ink = Color(0xFF27313A);
  static const _muted = Color(0xFF798088);
  static const _rose = Color(0xFFBE7A80);
  static const _stroke = Color(0xFFE7D9D7);
  static const _pink = Color(0xFFF6ECEB);

  InputDecoration _input(String hint, {String? prefix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFAFABAF), fontSize: 13),
      prefixText: prefix,
      prefixStyle: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: _stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: _rose, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFD45454)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFD45454), width: 1.5),
      ),
    );
  }

  Widget _label(String text, {bool isRequired = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(children: [
      Text(text, style: const TextStyle(
        fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink)),
      if (isRequired) const Text('  *', style: TextStyle(color: _rose)),
    ]),
  );

  Widget _panel(String heading, IconData icon, Widget content) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFCFB),
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: _stroke),
      boxShadow: const [BoxShadow(color: Color(0x090F151C),
        blurRadius: 16, offset: Offset(0, 5))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(
          width: 33, height: 33,
          decoration: BoxDecoration(color: _pink,
            borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 17, color: _rose),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(heading,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
            letterSpacing: -.25, color: _ink))),
      ]),
      const SizedBox(height: 17),
      content,
    ]),
  );

  void _selectCategory(String next) {
    if (category == next) return;
    setState(() {
      category = next;
      if (next == 'annual') {
        days.text = '365';
      } else if (days.text == '365') {
        days.text = '1';
      }
    });
  }

  Widget _categoryChoice(String code, String label, IconData icon) {
    final chosen = category == code;
    return InkWell(
      onTap: () => _selectCategory(code),
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: chosen ? const Color(0xFFF4DDDC) : Colors.white,
          border: Border.all(color: chosen ? _rose : _stroke,
            width: chosen ? 1.4 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: chosen ? _rose : _muted),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
            fontSize: 13, fontWeight: chosen ? FontWeight.w700 : FontWeight.w500,
            color: _ink)),
          if (chosen) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check_circle, size: 16, color: _rose),
          ],
        ]),
      ),
    );
  }

  Widget _ticketType() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label('Ticket type', isRequired: true),
      Wrap(spacing: 9, runSpacing: 9, children: [
        _categoryChoice('day', 'Day ticket', Icons.confirmation_number_outlined),
        _categoryChoice('annual', 'Annual pass', Icons.date_range_outlined),
        _categoryChoice('addon', 'Add-on', Icons.add_circle_outline),
      ]),

    ],
  );

  Widget _ticketDetails() => _panel('Ticket details', Icons.local_activity_outlined,
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label('Ticket name', isRequired: true),
      TextFormField(
        controller: name, maxLength: 100,
        decoration: _input('e.g. VIP 1-Day Ticket').copyWith(counterText: ''),
        validator: (v) => (v ?? '').trim().length < 2
            ? 'Enter at least 2 characters.' : null,
      ),
      const SizedBox(height: 15),
      _label('Short description'),
      TextFormField(
        controller: description, minLines: 2, maxLines: 3, maxLength: 600,
        decoration: _input('Describe what guests receive').copyWith(counterText: ''),
      ),
      const SizedBox(height: 6),
      Text('Maximum 600 characters',
        style: TextStyle(fontSize: 11, color: _muted)),
    ]),
  );

  Widget _priceAndAvailability() => _panel(
    'Pricing & availability', Icons.payments_outlined,
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          _label('Adult price', isRequired: true),
          TextFormField(
            controller: adult,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _input('0.00', prefix: 'RM  '),
            validator: (v) => parseMoneyMinor(v ?? '') == null
              ? 'Enter a valid price.' : null,
          ),
        ])),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          _label('Child price'),
          TextFormField(
            controller: child,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _input('Same as adult', prefix: 'RM  '),
            validator: (v) {
              if ((v ?? '').trim().isEmpty) return null;
              final amount = parseMoneyMinor(v!);
              if (amount == null) return 'Enter a valid price.';
              final adultPrice = parseMoneyMinor(adult.text);
              if (adultPrice != null && amount > adultPrice) {
                return 'Cannot exceed adult price.';
              }
              return null;
            },
          ),
        ])),
      ]),
      const SizedBox(height: 15),
      _label('Validity', isRequired: true),
      Row(children: [
        SizedBox(width: 125, child: TextFormField(
          controller: days,
          readOnly: category == 'annual',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _input('Days'),
          validator: (v) {
            final n = int.tryParse(v ?? '');
            if (n == null || n < 1 || n > 365) return '1–365 days';
            if (category == 'annual' && n != 365) return 'Use 365';
            return null;
          },
        )),
        const SizedBox(width: 12),
        Expanded(child: Text(category == 'annual'
          ? 'Annual passes are valid for 365 days.'
          : 'Number of days the ticket remains valid.',
          style: const TextStyle(color: _muted, fontSize: 11.5))),
      ]),
      const SizedBox(height: 17),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(color: _pink,
          borderRadius: BorderRadius.circular(12)),
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          activeTrackColor: _rose,
          title: const Text('Available for purchase', style: TextStyle(
            color: _ink, fontSize: 13, fontWeight: FontWeight.w700)),
          subtitle: const Text('New bookings only', style: TextStyle(
            color: _muted, fontSize: 11)),
          value: active,
          onChanged: (v) => setState(() => active = v),
        ),
      ),
      const SizedBox(height: 6),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
        title: const Text('Advanced', style: TextStyle(fontSize: 12.5,
          color: _muted, fontWeight: FontWeight.w600)),
        children: [
          _label('Display order'),
          TextFormField(
            controller: sort,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _input('0'),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              return n != null && n >= 0 && n <= 999
                ? null : 'Enter a number from 0–999.';
            },
          ),
          const SizedBox(height: 6),
        ],
      ),
    ]),
  );

  Widget _guestTerms() => _panel('Included benefits & guest terms',
    Icons.description_outlined,
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label('What is included?'),
      TextFormField(
        controller: inclusions, minLines: 2, maxLines: 3,
        decoration: _input('One benefit per line, e.g. Park entry'),
        validator: (v) {
          final lines = _benefits;
          if (lines.length > 12) return 'Maximum 12 benefits.';
          if (lines.any((e) => e.length > 180)) {
            return 'Keep each benefit under 180 characters.';
          }
          return null;
        },
      ),
      const SizedBox(height: 15),
      _label('Terms & conditions', isRequired: true),
      TextFormField(
        controller: terms, minLines: 3, maxLines: 5,
        decoration: _input('e.g. Valid on selected visit date. State restrictions and refund policy.'),
        validator: (v) {
          if ((v ?? '').trim().length < 12) {
            return 'Enter clear public terms (at least 12 characters).';
          }
          if ('${description.text.trim()}$_termsDivider${v?.trim() ?? ''}'.length > 2000) {
            return 'Description and terms exceed 2,000 characters.';
          }
          return null;
        },
      ),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final editing = widget.package != null;
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: BoxConstraints(maxWidth: 950,
          maxHeight: screen.height * 0.91),
        decoration: BoxDecoration(
          color: _pink,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFE0CDCB)),
          boxShadow: const [
            BoxShadow(color: Color(0x4A211B1D), blurRadius: 42,
              offset: Offset(0, 20)),
            BoxShadow(color: Color(0x1A211B1D), blurRadius: 10,
              offset: Offset(0, 5)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 21, 20, 20),
            child: Row(children: [
              Container(width: 49, height: 49,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFCFB),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.confirmation_number_outlined,
                  color: _rose, size: 25)),
              const SizedBox(width: 15),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(editing ? 'Edit ticket' : 'Create a ticket',
                    style: const TextStyle(fontSize: 23,
                      fontWeight: FontWeight.w700, color: _ink,
                      letterSpacing: -.6)),
                  const SizedBox(height: 3),
                  Text(editing ? 'Update this ticket for future bookings'
                    : 'A few details, then you are ready to publish',
                    style: const TextStyle(fontSize: 12.5, color: _muted)),
                ],
              )),
              IconButton(onPressed: () => Navigator.pop(context),
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, color: _ink)),
            ]),
          ),
          const Divider(height: 1, color: _stroke),
          Flexible(child: Form(
            key: form,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 21, 24, 26),
              child: LayoutBuilder(builder: (context, limits) {
                final wide = limits.maxWidth >= 690;
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ticketType(),
                    const SizedBox(height: 19),
                    if (wide)
                      Row(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _ticketDetails()),
                          const SizedBox(width: 17),
                          Expanded(child: _priceAndAvailability()),
                        ])
                    else ...[
                      _ticketDetails(),
                      const SizedBox(height: 17),
                      _priceAndAvailability(),
                    ],
                    const SizedBox(height: 17),
                    _guestTerms(),
                    const SizedBox(height: 17),
                    _panel('Ticket cover photo', Icons.image_outlined,
                      ParkCatalogImagePicker(
                        label: 'Product image',
                        existingUrl: _imageUrl,
                        bytes: _selectedImageBytes,
                        onPick: () async {
                          try {
                            final file = await pickParkCatalogImage();
                            if (file != null) {
                              final imageBytes = await file.readAsBytes();
                              if (mounted) {
                                setState(() {
                                  _selectedImage = file;
                                  _selectedImageBytes = imageBytes;
                                });
                              }
                            }
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Image: $e')));
                          }
                        },
                      )),
                  ],
                );
              }),
            ),
          )),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF5E9E7),
              border: Border(top: BorderSide(color: _stroke)),
            ),
            child: Row(children: [
              if (screen.width >= 570)
                const Expanded(child: Row(children: [
                  Icon(Icons.shield_outlined, size: 17, color: _muted),
                  SizedBox(width: 7),
                  Flexible(child: Text('Existing tickets are not changed',
                    style: TextStyle(fontSize: 11, color: _muted))),
                ]))
              else const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(
                  color: _muted, fontWeight: FontWeight.w600))),
              const SizedBox(width: 11),
              FilledButton.icon(
                onPressed: _uploading ? null : _save,
                icon: const Icon(Icons.check_rounded, size: 19),
                label: Text(_uploading ? 'Uploading...' : editing ? 'Save changes' : 'Save ticket'),
                style: FilledButton.styleFrom(
                  backgroundColor: _rose,
                  foregroundColor: Colors.white,
                  elevation: 1,
                  padding: const EdgeInsets.symmetric(horizontal: 21,
                    vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13)),
                  textStyle: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
