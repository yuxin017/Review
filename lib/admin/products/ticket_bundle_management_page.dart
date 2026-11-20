import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../admin_catalog_image.dart';
import 'package:flutter/services.dart';
import '../../visitor/models/tickets.dart';
import '../admin_store.dart';
import '../admin_models.dart' show titleCase;
import '../admin_widgets.dart';

/// Manages the published visitor bundle catalogue and private drafts.
class TicketBundleManagementPage extends StatefulWidget {
  const TicketBundleManagementPage({super.key, required this.db, required this.store});
  final FirebaseFirestore db;
  final AdminStore store;

  @override
  State<TicketBundleManagementPage> createState() => _TicketBundleManagementPageState();
}

class _TicketBundleManagementPageState extends State<TicketBundleManagementPage> {
  bool busy = false;
  String? feedback;
  String query = '';
  String status = 'all';

  Future<void> _setStatus(String id, String status) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.db.collection('ticketBundles').doc(id).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => feedback = 'Bundle ${status == 'draft' ? 'unpublished' : status}.');
    } catch (_) {
      if (mounted) setState(() => feedback = 'Unable to update this bundle.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _bundlePanel(String title, IconData icon, List<Widget> children) =>
    Container(padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFFFFFCFB),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: const Color(0xFFE7D9D7)),
        boxShadow: const [BoxShadow(color: Color(0x100F151C),
          blurRadius: 18, offset: Offset(0, 5))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Icon(icon, color: adminRose, size: 20),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))]),
        const SizedBox(height: 20), ...children,
      ]));


  // Catalogue images are backed by Firestore imageUrl. Make missing/failed URLs
  // distinguishable instead of silently replacing every failure with an icon.
  Widget _bundleThumbnail(dynamic rawUrl) {
    final url = rawUrl is String ? rawUrl.trim() : '';
    Widget placeholder(String reason) => Tooltip(
      message: reason,
      child: Container(
        width: 52, height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF8F0EF),
          borderRadius: BorderRadius.circular(7)),
        child: const Icon(Icons.image_not_supported_outlined,
          color: adminRose, size: 22),
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

  Future<void> _edit({String? docId, Map<String, dynamic>? existing}) async {
    final packages = widget.store.packages
        .where((p) => p.active && p.pass.category != 'addon').toList();
    if (packages.isEmpty) {
      setState(() => feedback = 'Create an active admission pass under Tickets & Passes first.');
      return;
    }
    final name = TextEditingController(text: existing?['name']?.toString() ?? 'Family Adventure Bundle');
    final adults = TextEditingController(text: '${existing?['adults'] ?? 2}');
    final children = TextEditingController(text: '${existing?['children'] ?? 2}');
    final discount = TextEditingController(text: existing?['discountMinor'] is num
        ? ((existing!['discountMinor'] as num) / 100).toStringAsFixed(2) : '0.00');
    String discountMode = 'rm'; // UI input only; Firestore stores discountMinor.
    String packageId = existing?['basePackageId']?.toString() ?? packages.first.id;
    if (!packages.any((p) => p.id == packageId)) packageId = packages.first.id;
    final form = GlobalKey<FormState>();
    PlatformFile? selectedImage;
    Uint8List? selectedImageBytes;
    String? imageUrl = existing?['imageUrl']?.toString();
    bool uploading = false;
    String? imageUploadError;
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) {
        final pass = packages.firstWhere((p) => p.id == packageId).pass;
        final a = int.tryParse(adults.text) ?? 0;
        final c = int.tryParse(children.text) ?? 0;
        final baseMinor = a * pass.priceMinor + c * pass.childPrice;
        final discountMinor = discountMode == 'rm'
            ? _discountMinor(discount.text)
            : (RegExp(r'^\d{1,3}(\.\d{1,2})?$').hasMatch(discount.text.trim()) &&
                (double.tryParse(discount.text.trim()) ?? 101) <= 100)
              ? (baseMinor * (double.parse(discount.text.trim()) / 100)).round()
              : null;
        final finalMinor = baseMinor - (discountMinor ?? 0);
        final validGroup = a >= 1 && c >= 0 && a + c <= 12;
        final validPrice = discountMinor != null && discountMinor >= 0 &&
            discountMinor < baseMinor && finalMinor > 0;
        final savings = baseMinor > 0 && discountMinor != null
            ? (discountMinor / baseMinor * 100).toStringAsFixed(1) : '0.0';
        void setGroup(int adultCount, int childCount) {
          adults.text = '$adultCount';
          children.text = '$childCount';
          update(() {});
        }

        return AlertDialog(
          backgroundColor: const Color(0xFFF4E8E7),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          elevation: 22,
          shadowColor: const Color(0x770F151C),
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          titlePadding: const EdgeInsets.fromLTRB(26, 24, 26, 14),
          title: Row(children: [
            Container(width: 50, height: 50,
              decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(15)),
              child: const Icon(Icons.groups_2_outlined, color: adminRose)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(docId == null ? 'Create Group Bundle' : 'Edit Group Bundle',
                style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Guests · Admission · Offer', style: TextStyle(fontSize: 12, color: adminMuted)),
            ])),
            IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
          ]),
          contentPadding: const EdgeInsets.fromLTRB(26, 5, 26, 14),
          actionsPadding: const EdgeInsets.fromLTRB(26, 8, 26, 22),
          content: SizedBox(
            width: 900,
            height: MediaQuery.sizeOf(ctx).height * 0.67,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Form(
                key: form,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: LayoutBuilder(builder: (context, constraints) {
                  final left = _bundlePanel('Bundle details', Icons.groups_outlined, [
                    const Text('Bundle name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 7),
                    TextFormField(controller: name, maxLength: 80,
                      decoration: const InputDecoration(hintText: 'e.g. Family Adventure Bundle', counterText: ''),
                      validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a bundle name.' : null),
                    const SizedBox(height: 17),
                    const Text('Admission ticket', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 7),
                    DropdownButtonFormField<String>(
                      value: packageId, isExpanded: true,
                      decoration: const InputDecoration(),
                      items: packages.map((p) => DropdownMenuItem(
                        value: p.id, child: Text(p.pass.name, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) { if (v != null) update(() => packageId = v); }),
                    const SizedBox(height: 7),
                    Text('Adult ${money(pass.priceMinor)}  ·  Child ${money(pass.childPrice)}',
                      style: const TextStyle(fontSize: 12, color: adminMuted)),
                    const SizedBox(height: 18),
                    const Text('Guests', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      ActionChip(label: const Text('2 + 1'), tooltip: '2 adults + 1 child',
                        onPressed: () => setGroup(2, 1)),
                      ActionChip(label: const Text('2 + 2'), tooltip: '2 adults + 2 children',
                        onPressed: () => setGroup(2, 2)),
                      ActionChip(label: const Text('4 adults'),
                        onPressed: () => setGroup(4, 0)),
                    ]),
                    const SizedBox(height: 13),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: TextFormField(controller: adults,
                        onChanged: (_) => update(() {}),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Adults'),
                        validator: (v) { final n = int.tryParse(v ?? '');
                          return n == null || n < 1 || n > 12 ? 'Choose 1–12.' : null;
                        })),
                      const SizedBox(width: 12),
                      Expanded(child: TextFormField(controller: children,
                        onChanged: (_) => update(() {}),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Children'),
                        validator: (v) { final n = int.tryParse(v ?? '');
                          if (n == null || n < 0 || n > 11) return 'Choose 0–11.';
                          return (int.tryParse(adults.text) ?? 0) + n > 12
                              ? 'Maximum 12 guests.' : null;
                        })),
                    ]),
                    const SizedBox(height: 18),
                    ParkCatalogImagePicker(
                      label: 'Bundle cover photo',
                      bytes: selectedImageBytes,
                      existingUrl: imageUrl,
                      onPick: () async {
                        try {
                          final selected = await pickParkCatalogImage();
                          if (selected != null) {
                            final imageBytes = await selected.readAsBytes();
                            if (ctx.mounted) update(() {
                              selectedImage = selected;
                              selectedImageBytes = imageBytes;
                              imageUploadError = null;
                            });
                          }
                        } catch (e) {
                          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Image: $e')));
                        }
                      },
                    ),
                  ]);
                  final right = _bundlePanel('Offer & price', Icons.sell_outlined, [
                    const Text('Discount', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 9),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      ChoiceChip(label: const Text('RM amount'),
                        selected: discountMode == 'rm',
                        onSelected: (_) => update(() { discountMode = 'rm'; discount.text = '0.00'; })),
                      ChoiceChip(label: const Text('Percentage (%)'),
                        selected: discountMode == 'percent',
                        onSelected: (_) => update(() { discountMode = 'percent'; discount.text = '0'; })),
                    ]),
                    const SizedBox(height: 16),
                    TextFormField(controller: discount, onChanged: (_) => update(() {}),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: InputDecoration(labelText: discountMode == 'rm'
                          ? 'Discount amount (RM)' : 'Discount (%)',
                        hintText: discountMode == 'rm' ? '25.00' : '10'),
                      validator: (v) {
                        final m = discountMode == 'rm' ? _discountMinor(v ?? '')
                          : (RegExp(r'^\d{1,3}(\.\d{1,2})?$').hasMatch((v ?? '').trim()) &&
                              (double.tryParse((v ?? '').trim()) ?? 101) <= 100)
                            ? (baseMinor * double.parse((v ?? '').trim()) / 100).round() : null;
                        if (m == null) return 'Enter a valid discount.';
                        if (m >= baseMinor) return 'Discount must be below full price.';
                        return null;
                      }),
                    const SizedBox(height: 23),
                    Container(padding: const EdgeInsets.all(19),
                      decoration: BoxDecoration(color: const Color(0xFFF8F1F0),
                        borderRadius: BorderRadius.circular(15)),
                      child: Column(children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('Regular price'), Text(money(baseMinor))]),
                        const SizedBox(height: 12),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('You save'),
                          Text(discountMinor == null ? '—' : '${money(discountMinor)} ($savings%)',
                            style: const TextStyle(color: adminRose, fontWeight: FontWeight.w600))]),
                        const Divider(height: 28),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('Bundle price', style: TextStyle(fontWeight: FontWeight.w700)),
                          Text(validGroup && validPrice ? money(finalMinor) : '—',
                            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: adminRose))]),
                      ])),
                    if (imageUploadError != null) ...[
                      const SizedBox(height: 12),
                      SelectableText(
                        imageUploadError!,
                        style: const TextStyle(
                          color: Color(0xFFAD3E41), fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text('Draft · Not for checkout yet',
                      style: TextStyle(color: adminMuted, fontSize: 11)),
                  ]);
                  if (constraints.maxWidth < 720) return Column(children: [
                    left, const SizedBox(height: 16), right]);
                  return Row(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Expanded(child: left), const SizedBox(width: 16), Expanded(child: right)]);
                }),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: adminRose))),
            FilledButton(
              onPressed: uploading || !validGroup || !validPrice ? null : () async {
                if (form.currentState?.validate() != true) return;
                update(() { uploading = true; imageUploadError = null; });
                try {
                  if (selectedImage != null) {
                    imageUrl = await uploadParkCatalogImage(selectedImage!, 'bundles');
                  }
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx, <String, dynamic>{
                    'name': name.text.trim(), 'basePackageId': packageId,
                    'adults': a, 'children': c, 'basePriceMinor': baseMinor,
                    'discountMinor': discountMinor, 'priceMinor': finalMinor,
                    'currency': 'MYR', 'status': existing?['status'] ?? 'draft',
                    if (imageUrl != null) 'imageUrl': imageUrl,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                } catch (e) {
                  if (ctx.mounted) update(() => imageUploadError =
                    'Photo upload failed: $e');
                } finally {
                  if (ctx.mounted) update(() => uploading = false);
                }
              }, style: FilledButton.styleFrom(
                backgroundColor: adminRose,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              child: Text(uploading ? 'Uploading...' : 'Save Bundle', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      }),
    );
    name.dispose(); adults.dispose(); children.dispose(); discount.dispose();
    if (draft == null || !mounted) return;
    setState(() { busy = true; feedback = null; });
    try {
      final col = widget.db.collection('ticketBundles');
      if (docId == null) {
        await col.add({...draft, 'createdAt': FieldValue.serverTimestamp()});
      } else {
        await col.doc(docId).update(draft);
      }
      if (mounted) setState(() => feedback = 'Bundle saved.');
    } on FirebaseException catch (e) {
      if (mounted) setState(() => feedback =
          'Unable to save bundle (${e.code}). ${e.message ?? 'Check Firestore Rules and admin permissions.'}');
    } catch (e) {
      if (mounted) setState(() => feedback =
          'Unable to save bundle: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  int? _discountMinor(String input) {
    final raw = input.trim();
    if (!RegExp(r'^\d{1,6}(\.\d{1,2})?$').hasMatch(raw)) return null;
    final parts = raw.split('.');
    return int.parse(parts[0]) * 100 +
        (parts.length > 1 ? int.parse(parts[1].padRight(2, '0')) : 0);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AdminHeading(
        'Family & Group Bundles',
        'Manage group admission packages and calculated offers',
        action: AdminButton('Create Bundle', icon: Icons.add,
          onPressed: busy ? null : () => _edit()),
      ),
      const SizedBox(height: 10),
      const Text(
        'Bundle prices use your Tickets & Passes rates. Publish a bundle to list it in the visitor shop for purchase enquiries.',
        style: TextStyle(fontSize: 12, color: adminMuted),
      ),
      if (feedback != null) ...[
        const SizedBox(height: 10),
        Text(feedback!, style: const TextStyle(color: adminMuted)),
      ],
      const SizedBox(height: 22),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: widget.db.collection('ticketBundles').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const AdminCard(
            child: Text('Could not load bundles. Check Firestore permissions.'));
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final all = snapshot.data!.docs.toList()
            ..sort((a, b) => (a.data()['name'] ?? '').toString()
                .toLowerCase().compareTo(
                    (b.data()['name'] ?? '').toString().toLowerCase()));
          final drafts = all.where((d) =>
              (d.data()['status'] ?? 'draft') == 'draft').length;
          final averagePrice = all.isEmpty ? 0 :
              (all.fold<int>(0, (sum, d) => sum +
                  ((d.data()['priceMinor'] as num?)?.toInt() ?? 0)) /
                  all.length).round();
          final averageSavings = all.isEmpty ? 0 :
              (all.fold<int>(0, (sum, d) => sum +
                  ((d.data()['discountMinor'] as num?)?.toInt() ?? 0)) /
                  all.length).round();
          final shown = all.where((d) {
            final data = d.data();
            final text = '${data['name'] ?? ''} ${data['adults'] ?? ''} '
                '${data['children'] ?? ''}'.toLowerCase();
            return text.contains(query.trim().toLowerCase()) &&
                (status == 'all' || (data['status'] ?? 'draft') == status);
          }).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminStats(children: [
                AdminStat('Total Bundles', '${all.length}',
                  'Family and group offers', Icons.groups_2_outlined),
                AdminStat('Draft', '$drafts',
                  'Not yet available for purchase', Icons.edit_note_outlined,
                  color: const Color(0xFFC28A33)),
                AdminStat('Average Bundle Price',
                  all.isEmpty ? '—' : money(averagePrice),
                  'Based on saved bundles', Icons.payments_outlined,
                  color: const Color(0xFF3978D8)),
                AdminStat('Average Savings',
                  all.isEmpty ? '—' : money(averageSavings),
                  'Discount per bundle', Icons.local_offer_outlined,
                  color: const Color(0xFF278D52)),
              ]),
              const SizedBox(height: 24),
              AdminCard(padding: const EdgeInsets.all(16), child: Wrap(
                spacing: 14, runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(width: 330, child: TextField(
                    onChanged: (v) => setState(() => query = v),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: 'Search group bundles'),
                  )),
                  AdminSelect(value: status, width: 180,
                    options: const {'all': 'All Status',
                      'draft': 'Draft', 'published': 'Published', 'archived': 'Archived'},
                    onChanged: (v) => setState(() => status = v)),
                  Text('${shown.length} of ${all.length} bundles',
                    style: const TextStyle(color: adminMuted, fontSize: 12)),
                ],
              )),
              const SizedBox(height: 20),
              AdminCard(padding: EdgeInsets.zero,
                child: shown.isEmpty
                  ? AdminEmpty(all.isEmpty ? 'No group bundles yet' :
                      'No matching bundles',
                      all.isEmpty ? 'Create your first group bundle.' :
                      'Try another search or status.')
                  : AdminTable(minWidth: 800,
                      columns: const [
                        DataColumn(label: Text('Group Bundle')),
                        DataColumn(label: Text('Guests')),
                        DataColumn(label: Text('Regular / Save')),
                        DataColumn(label: Text('Bundle Price')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: [
                        for (final bundle in shown)
                          DataRow(cells: [
                            DataCell(SizedBox(width: 225, child: Row(children: [
                              _bundleThumbnail(bundle.data()['imageUrl']),
                              const SizedBox(width: 9),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(bundle.data()['name']?.toString() ?? 'Group Bundle',
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.store.packages.any((p) => p.id == bundle.data()['basePackageId'])
                                      ? widget.store.packages.firstWhere((p) =>
                                          p.id == bundle.data()['basePackageId']).pass.name
                                      : 'Admission pass',
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: adminMuted)),
                                ],
                              )),
                            ]))),
                            DataCell(SizedBox(width: 98, child: Text(
                              '${bundle.data()['adults'] ?? 0} adults\n${bundle.data()['children'] ?? 0} children',
                              style: const TextStyle(fontSize: 12)))),
                            DataCell(SizedBox(width: 112, child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(money((bundle.data()['basePriceMinor'] as num?)?.toInt() ?? 0),
                                  style: const TextStyle(fontSize: 12)),
                                Text('-${money((bundle.data()['discountMinor'] as num?)?.toInt() ?? 0)}',
                                  style: const TextStyle(fontSize: 11, color: adminRose)),
                              ]))),
                            DataCell(Text(money((bundle.data()['priceMinor'] as num?)?.toInt() ?? 0),
                              style: const TextStyle(fontWeight: FontWeight.w700))),
                            DataCell(AdminBadge(titleCase((bundle.data()['status'] ?? 'draft').toString()))),
                            DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                              AdminButton('Edit', outlined: true,
                                icon: Icons.edit_outlined,
                                onPressed: busy ? null : () => _edit(
                                  docId: bundle.id, existing: bundle.data())),
                              PopupMenuButton<String>(
                                enabled: !busy,
                                onSelected: (value) => _setStatus(bundle.id, value),
                                itemBuilder: (_) => [
                                  if (bundle.data()['status'] != 'published')
                                    const PopupMenuItem(value: 'published', child: Text('Publish to Shop')),
                                  if (bundle.data()['status'] == 'published')
                                    const PopupMenuItem(value: 'draft', child: Text('Unpublish')),
                                  if (bundle.data()['status'] != 'archived')
                                    const PopupMenuItem(value: 'archived', child: Text('Archive')),
                                ],
                              ),
                            ])),
                          ]),
                      ],
                    )),
            ],
          );
        },
      ),
    ],
  );
}
