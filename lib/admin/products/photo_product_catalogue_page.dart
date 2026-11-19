import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../park/venue_configuration.dart';
import '../../park/venue_map.dart';
import '../admin_widgets.dart';
import '../admin_catalog_image.dart';
import '../operations/park_admin_repository.dart';
import '../operations/park_management_page.dart';

const _pink = Color(0xFFBD7C80), _paper = Color(0xFFF5E9E8);
String _rm(int minor) => 'RM ${(minor / 100).toStringAsFixed(2)}';
int? _money(String raw) {
  final s = raw.trim();
  if (!RegExp(r'^\d{1,6}(\.\d{1,2})?$').hasMatch(s)) return null;
  final p = s.split('.');
  final minor = int.parse(p.first) * 100 +
      (p.length == 2 ? int.parse(p.last.padRight(2, '0')) : 0);
  return minor > 0 && minor <= 100000000 ? minor : null;
}

/// Admin catalogue, not a substitute for server-side photo checkout pricing.
/// Only writes photoProducts; purchases continue to use the existing verified
/// photo quote endpoint until that endpoint supports product identifiers.
class PhotoProductCataloguePage extends StatefulWidget {
  const PhotoProductCataloguePage({super.key, required this.db,
      required this.repository});
  final FirebaseFirestore db;
  final ParkAdminRepository repository;
  @override
  State<PhotoProductCataloguePage> createState() => _PhotoProductCataloguePageState();
}

class _PhotoProductCataloguePageState extends State<PhotoProductCataloguePage> {
  String filter = 'All', search = '', status = 'all';
  late final products = widget.db.collection('photoProducts').snapshots();
  late final settings = widget.repository.settings('photos');


  Widget _photoThumbnail(dynamic rawUrl) {
    final url = rawUrl is String ? rawUrl.trim() : '';
    Widget placeholder(String reason) => Tooltip(
      message: reason,
      child: Container(
        width: 52, height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFFF8F0EF),
          borderRadius: BorderRadius.circular(7)),
        child: const Icon(Icons.image_not_supported_outlined,
          color: _pink, size: 22),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: ParkCatalogNetworkImage(
        url: url,
        width: 52,
        height: 44,
        fallback: placeholder(url.isEmpty
            ? 'No photo. Open Edit to add one.'
            : 'Photo unavailable. Open Edit to replace it.'),
      ),
    );
  }

  Future<void> _edit(Map<String, dynamic>? value,
      List<Map<String, dynamic>> all) async {
    await showDialog<void>(context: context, barrierDismissible: false,
      builder: (_) => _PhotoProductEditor(db: widget.db, initial: value,
        products: all));
  }

  @override
  Widget build(BuildContext context) =>
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: products,
      builder: (context, snapshot) {
        final records = (snapshot.data?.docs ?? [])
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList()
          ..sort((a, b) => (a['name'] as String? ?? '')
            .toLowerCase().compareTo((b['name'] as String? ?? '').toLowerCase()));
        final shown = records.where((item) =>
          (filter == 'All' || item['type'] == filter) &&
          (status == 'all' || (item['active'] != false) == (status == 'active')) &&
          '${item['name']} ${item['description']} ${item['sizeLabel']}'
            .toLowerCase().contains(search.trim().toLowerCase())).toList();
        final enabled = records.where((p) => p['active'] != false).length;
        final average = records.isEmpty ? 0 :
          (records.fold<int>(0, (sum, p) => sum +
            ((p['priceMinor'] as num?)?.toInt() ?? 0)) / records.length).round();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminHeading('Photo Products', 'Sizes, prices and photo bundles',
              action: AdminButton('Add Photo Product', icon: Icons.add,
                onPressed: () => _edit(null, records))),
            const SizedBox(height: 24),
            if (snapshot.hasError)
              const AdminCard(child: Text(
                'Cannot load photo products. Verify admin rules.'))
            else if (!snapshot.hasData)
              const Center(child: CircularProgressIndicator())
            else ...[
              AdminStats(children: [
                AdminStat('Total Products', '${records.length}',
                  'Digital, prints and packages', Icons.photo_library_outlined),
                AdminStat('Enabled', '$enabled',
                  'Visible in admin catalogue', Icons.check_circle_outline,
                  color: const Color(0xFF278D52)),
                AdminStat('Hidden', '${records.length - enabled}',
                  'Not currently offered', Icons.pause_circle_outline,
                  color: const Color(0xFFC28A33)),
                AdminStat('Average Price',
                  records.isEmpty ? '—' : _rm(average),
                  'Across all photo products', Icons.payments_outlined,
                  color: const Color(0xFF3978D8)),
              ]),
              const SizedBox(height: 22),
              StreamBuilder<Map<String, dynamic>>(
                stream: settings,
                builder: (context, s) {
                  final d = s.data;
                  return AdminCard(child: Row(children: [
                    const Icon(Icons.place_outlined, color: _pink, size: 29),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Photo collection kiosk',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                        Text(d?['kioskName'] as String? ?? 'Not configured',
                          style: const TextStyle(color: adminMuted)),
                      ],
                    )),
                    AdminButton('Set location on map',
                      icon: Icons.map_outlined, outlined: true,
                      onPressed: d == null ? null : () => showDialog<void>(
                        context: context,
                        builder: (_) => _KioskMapEditor(
                          repository: widget.repository, original: d))),
                  ]));
                },
              ),
              const SizedBox(height: 12),
              StreamBuilder<Map<String, dynamic>>(
                stream: settings,
                builder: (context, s) {
                  final d = s.data;
                  return ExpansionTile(
                    title: const Text('Current checkout prices',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    subtitle: const Text(
                      'Existing visitor photo checkout uses these prices',
                      style: TextStyle(fontSize: 12, color: adminMuted)),
                    children: [Padding(padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Expanded(child: Text(d == null ? 'Unavailable' :
                          'Digital ${_rm((d['digitalPriceMinor'] as num?)?.toInt() ?? 0)}  ·  '
                          'Print ${_rm((d['printPriceMinor'] as num?)?.toInt() ?? 0)}  ·  '
                          'Bundle ${_rm((d['bundlePriceMinor'] as num?)?.toInt() ?? 0)}',
                          style: const TextStyle(fontSize: 12))),
                        AdminButton('Edit checkout prices', outlined: true,
                          onPressed: d == null ? null : () => showDialog<void>(
                            context: context,
                            builder: (_) => ParkPolicyEditor(
                              repository: widget.repository,
                              kind: 'photos', initial: d))),
                      ]),
                    )],
                  );
                },
              ),
              const SizedBox(height: 16),
              AdminCard(padding: const EdgeInsets.all(16), child: Wrap(
                spacing: 14, runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(width: 330, child: TextField(
                    onChanged: (v) => setState(() => search = v),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: 'Search photo products'),
                  )),
                  AdminSelect(value: status, width: 160,
                    options: const {'all': 'All Status',
                      'active': 'Enabled', 'inactive': 'Hidden'},
                    onChanged: (v) => setState(() => status = v)),
                  AdminSelect(value: filter, width: 175,
                    options: const {'All': 'All Categories',
                      'digital': 'Digital', 'print': 'Photo Prints',
                      'bundle': 'Packages'},
                    onChanged: (v) => setState(() => filter = v)),
                ],
              )),
              const SizedBox(height: 20),
              AdminCard(padding: EdgeInsets.zero, child: shown.isEmpty
                ? AdminEmpty(records.isEmpty ? 'No photo products yet' :
                    'No matching photo products',
                    records.isEmpty ? 'Add your first digital photo or print.' :
                      'Try changing your search or filters.')
                : AdminTable(minWidth: 720,
                    columns: const [
                      DataColumn(label: Text('Photo Product')),
                      DataColumn(label: Text('Type / Size')),
                      DataColumn(label: Text('Price')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: [for (final item in shown) DataRow(cells: [
                      DataCell(SizedBox(width: 235, child: Row(children: [
                        _photoThumbnail(item['imageUrl']),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['name'] as String? ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 3),
                            Text(item['description'] as String? ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: adminMuted, fontSize: 11)),
                          ],
                        )),
                      ]))),
                      DataCell(SizedBox(width: 112, child: Text(item['type'] == 'print'
                        ? 'Print · ${item['sizeLabel'] ?? ''}'
                        : item['type'] == 'bundle'
                          ? 'Package · ${(item['componentIds'] as List? ?? []).length} items'
                          : 'Digital', maxLines: 2, overflow: TextOverflow.ellipsis))),
                      DataCell(Text(_rm((item['priceMinor'] as num?)?.toInt() ?? 0),
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                      DataCell(AdminBadge(item['active'] != false
                        ? 'Enabled' : 'Hidden', tone: item['active'] != false
                          ? 'active' : 'inactive')),
                      DataCell(AdminButton('Edit', outlined: true,
                        icon: Icons.edit_outlined,
                        onPressed: () => _edit(item, records))),
                    ])],
                  )),
              const SizedBox(height: 10),
              const Text(
                'Visitor checkout uses the prices shown above.',
                style: TextStyle(fontSize: 12, color: adminMuted)),
            ],
          ],
        );
      },
    );
}

class _PhotoProductEditor extends StatefulWidget {
  const _PhotoProductEditor({required this.db, required this.initial,
    required this.products});
  final FirebaseFirestore db;
  final Map<String, dynamic>? initial;
  final List<Map<String, dynamic>> products;
  @override
  State<_PhotoProductEditor> createState() => _PhotoProductEditorState();
}

class _PhotoProductEditorState extends State<_PhotoProductEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.initial?['name'] as String? ?? '');
  late final description = TextEditingController(text: widget.initial?['description'] as String? ?? '');
  late final price = TextEditingController(text: widget.initial?['priceMinor'] is num
      ? ((widget.initial!['priceMinor'] as num).toInt() / 100).toStringAsFixed(2) : '');
  late final customSize = TextEditingController(text: widget.initial?['sizeLabel'] as String? ?? '');
  late String type = widget.initial?['type'] as String? ?? 'digital';
  late bool active = widget.initial?['active'] != false;
  late Set<String> included = (widget.initial?['componentIds'] as List? ?? [])
      .whereType<String>().toSet();
  PlatformFile? selected;
  Uint8List? preview;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    name.dispose(); description.dispose(); price.dispose(); customSize.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp']);
      if (file == null) return;
      final data = await file.readAsBytes();
      if (data.length > 2 * 1024 * 1024 || data.isEmpty) {
        throw const FormatException('Use a JPG, PNG or WebP image under 2 MB.');
      }
      if (!mounted) return;
      setState(() { selected = file; preview = data; error = null; });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> save() async {
    if (!(form.currentState?.validate() ?? false)) return;
    if (type == 'bundle' && included.length < 2) {
      setState(() => error = 'Select at least two existing products.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      var url = widget.initial?['imageUrl'] as String? ?? '';
      if (selected != null) {
        final ext = (selected!.extension ?? 'jpg').toLowerCase();
        final mime = ext == 'png' ? 'image/png' :
                     ext == 'webp' ? 'image/webp' : 'image/jpeg';
        final app = Firebase.app('ThemeParkAdmin');
        final storage = FirebaseStorage.instanceFor(app: app);
        final ref = storage.ref('catalog-images/photos/${DateTime.now().microsecondsSinceEpoch}.$ext');
        await ref.putData(preview!, SettableMetadata(contentType: mime));
        url = await ref.getDownloadURL();
      }
      final data = <String, dynamic>{
        'name': name.text.trim(), 'description': description.text.trim(),
        'type': type, 'sizeLabel': type == 'print' ? customSize.text.trim() : '',
        'componentIds': type == 'bundle' ? included.toList() : <String>[],
        'priceMinor': _money(price.text)!, 'currency': 'MYR',
        'active': active, 'imageUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final id = widget.initial?['id'] as String?;
      if (id == null) {
        await widget.db.collection('photoProducts').add({
          ...data, 'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await widget.db.collection('photoProducts').doc(id).update(data);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => error = 'Could not save product: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(String label, TextEditingController controller, {
    String? hint, int maxLines = 1, String? Function(String?)? check,
  }) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 13,
      fontWeight: FontWeight.w700, color: adminDark)),
    const SizedBox(height: 8),
    TextFormField(controller: controller, maxLines: maxLines,
      enabled: !busy, validator: check,
      decoration: InputDecoration(hintText: hint,
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)))),
  ]);

  @override
  Widget build(BuildContext context) {
    final eligible = widget.products.where((p) =>
        p['id'] != widget.initial?['id'] &&
        p['type'] != 'bundle' && p['active'] == true).toList();
    final content = Form(key: form, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Product type', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [for (final t in const <MapEntry<String, String>>[
        MapEntry('digital', 'Digital'),
        MapEntry('print', 'Photo Print'),
        MapEntry('bundle', 'Package')])
        ChoiceChip(label: Text(t.value), selected: type == t.key,
          onSelected: busy ? null : (_) => setState(() => type = t.key))]),
      const SizedBox(height: 20),
      LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 690;
        final details = _card('Product details', Icons.photo_outlined,
          Column(children: [
            field('Product name *', name, hint: 'e.g. 4R Photo Print',
              check: (v) => (v?.trim().length ?? 0) < 2 || (v?.length ?? 0) > 100
                ? 'Enter 2–100 characters' : null),
            const SizedBox(height: 16),
            field('Short description', description,
              hint: 'What is included?', maxLines: 3,
              check: (v) => (v?.length ?? 0) > 300 ? 'Maximum 300 characters' : null),
            if (type == 'print') ...[
              const SizedBox(height: 16),
              field('Print size *', customSize, hint: '4R / 5R / 6R / 8R',
                check: (v) => (v?.trim().isEmpty ?? true) || (v!.length > 30)
                  ? 'Enter the print size' : null),
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [for (final s in ['4R','5R','6R','8R'])
                ActionChip(label: Text(s), onPressed: busy ? null :
                  () => setState(() => customSize.text = s))]),
            ],
          ]));
        final commercial = _card('Pricing & photo', Icons.sell_outlined,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            field('Price (RM) *', price, hint: 'e.g. 25.00',
              check: (v) => _money(v ?? '') == null ? 'Enter a valid price' : null),
            const SizedBox(height: 18),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(
              color: const Color(0xFFF8F0EF), borderRadius: BorderRadius.circular(12)),
              child: SwitchListTile.adaptive(value: active,
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled in admin catalogue'),
                onChanged: busy ? null : (v) => setState(() => active = v))),
            const SizedBox(height: 18),
            const Text('Product photo', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(height: 135, width: double.infinity, alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFF8F0EF),
                borderRadius: BorderRadius.circular(12)),
              child: preview != null ? ClipRRect(borderRadius: BorderRadius.circular(12),
                child: Image.memory(preview!, width: double.infinity,
                  height: 135, fit: BoxFit.cover)) :
                (widget.initial?['imageUrl'] as String? ?? '').isNotEmpty
                ? ParkCatalogNetworkImage(
                    url: widget.initial!['imageUrl'] as String,
                    width: double.infinity,
                    height: 130,
                    fit: BoxFit.contain,
                    fallback: const Icon(Icons.broken_image_outlined, color: _pink),
                  ) :
                const Icon(Icons.add_photo_alternate_outlined, color: _pink, size: 42)),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: busy ? null : pick,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Choose cover image')),
          ]));
        return narrow ? Column(children: [details, const SizedBox(height: 16), commercial])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: details), const SizedBox(width: 16),
            Expanded(child: commercial)]);
      }),
      if (type == 'bundle') ...[
        const SizedBox(height: 16),
        _card('Included products', Icons.inventory_2_outlined,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Select at least two existing digital or print products.'),
            const SizedBox(height: 8),
            if (eligible.isEmpty)
              const Text('Create individual photo products first.'),
            for (final p in eligible)
              CheckboxListTile(
                title: Text(p['name'] as String? ?? ''),
                subtitle: Text(_rm((p['priceMinor'] as num?)?.toInt() ?? 0)),
                value: included.contains(p['id']),
                onChanged: busy ? null : (v) => setState(() {
                  if (v == true) { included.add(p['id'] as String); }
                  else { included.remove(p['id']); }
                }),
              ),
          ])),
      ],
      if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
        child: Text(error!, style: const TextStyle(color: Colors.red))),
    ]));
    return Dialog(backgroundColor: _paper,
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 14,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980,
        maxHeight: 840), child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
          child: Row(children: [
            const Icon(Icons.photo_library_outlined, color: _pink, size: 31),
            const SizedBox(width: 14),
            Expanded(child: Text(widget.initial == null ? 'Add Photo Product' :
              'Edit Photo Product', style: const TextStyle(fontSize: 25,
              fontWeight: FontWeight.w800))),
            IconButton(onPressed: busy ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close)),
          ])),
        const Divider(height: 1),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(22),
          child: content)),
        const Divider(height: 1),
        Padding(padding: const EdgeInsets.all(20), child: Row(
          mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
          const SizedBox(width: 12),
          FilledButton.icon(onPressed: busy ? null : save,
            icon: busy ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2,
                color: Colors.white)) : const Icon(Icons.check),
            label: Text(busy ? 'Saving…' : 'Save Product'),
            style: FilledButton.styleFrom(backgroundColor: _pink)),
        ])),
      ])),
    );
  }

  Widget _card(String label, IconData icon, Widget child) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white,
      border: Border.all(color: const Color(0xFFE7D9D7)),
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 15,
        offset: Offset(0, 6))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, color: _pink), const SizedBox(width: 9),
        Text(label, style: const TextStyle(fontSize: 18,
          fontWeight: FontWeight.w800))]),
      const SizedBox(height: 18), child,
    ]));
}

class _KioskMapEditor extends StatefulWidget {
  const _KioskMapEditor({required this.repository, required this.original});
  final ParkAdminRepository repository;
  final Map<String, dynamic> original;
  @override
  State<_KioskMapEditor> createState() => _KioskMapEditorState();
}

class _KioskMapEditorState extends State<_KioskMapEditor> {
  late final name = TextEditingController(
    text: widget.original['kioskName'] as String? ?? 'Photo Collection Kiosk');
  late LatLng selected = LatLng(
    (widget.original['kioskLatitude'] as num?)?.toDouble() ?? VenueConfiguration.latitude,
    (widget.original['kioskLongitude'] as num?)?.toDouble() ?? VenueConfiguration.longitude);
  bool saving = false;
  String? error;
  @override
  void dispose() { name.dispose(); super.dispose(); }

  Future<void> save() async {
    if (name.text.trim().length < 2) {
      setState(() => error = 'Enter a kiosk name.'); return;
    }
    setState(() { saving = true; error = null; });
    try {
      await widget.repository.request('savePhotoKioskLocation', {
        'kioskName': name.text.trim(),
        'kioskLatitude': selected.latitude,
        'kioskLongitude': selected.longitude,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => saving = false); }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: _paper, elevation: 14,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680,
      maxHeight: 750), child: Padding(padding: const EdgeInsets.all(22),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Photo Kiosk Location', style: TextStyle(
            fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          TextField(controller: name, decoration: const InputDecoration(
            labelText: 'Kiosk name', border: OutlineInputBorder())),
          const SizedBox(height: 15),
          const Text('Tap a spot on the park map'),
          const SizedBox(height: 9),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12),
            child: VenueConfiguration.boundsReady
              ? FlutterMap(options: MapOptions(
                  initialCenter: selected, initialZoom: 18,
                  onTap: (_, point) {
                    if (point.latitude >= VenueConfiguration.south! &&
                        point.latitude <= VenueConfiguration.north! &&
                        point.longitude >= VenueConfiguration.west! &&
                        point.longitude <= VenueConfiguration.east!) {
                      setState(() {
                        selected = point;
                        error = null;
                      });
                    } else { setState(() => error = 'Choose a point inside the park.'); }
                  }), children: [
                    const ProviderTileLayer(),
                    MarkerLayer(markers: [Marker(point: selected,
                      width: 45, height: 50,
                      child: const Icon(Icons.location_pin, color: _pink, size: 45))]),
                  ])
              : const Center(child: Text('Map bounds are not configured.')))),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(onPressed: saving ? null : save,
              style: FilledButton.styleFrom(backgroundColor: _pink),
              child: Text(saving ? 'Saving…' : 'Save Location')),
          ]),
        ]))));
}
