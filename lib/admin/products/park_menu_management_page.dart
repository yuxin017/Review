import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../visitor/models/tickets.dart';
import '../admin_widgets.dart';
import '../admin_catalog_image.dart';
import '../admin_models.dart';

/// Merchandise and dining catalogues link to an existing Park Facilities place
/// using its Firestore document ID (no duplicate store/restaurant records).
/// Admin catalogue only: no online food/retail ordering is implied.
class ParkMenuManagementPage extends StatefulWidget {
  const ParkMenuManagementPage({super.key, required this.db});
  final FirebaseFirestore db;

  @override
  State<ParkMenuManagementPage> createState() => _ParkMenuManagementPageState();
}

class _ParkMenuManagementPageState extends State<ParkMenuManagementPage> {
  static const foodCategories = ['Meals', 'Snacks', 'Dessert', 'Beverages', 'Other'];
  static const retailCategories = [
    'Souvenirs', 'Apparel', 'Toys', 'Accessories', 'Collectibles', 'Gifts', 'Other'
  ];

  String section = 'dining';
  String? storeId;
  String categoryFilter = 'All Categories';
  String search = '';
  bool busy = false;
  String? feedback;

  bool get dining => section == 'dining';
  List<String> get categories => dining ? foodCategories : retailCategories;
  String _label(Map<String, dynamic> item) =>
      (item['name'] ?? 'Untitled product').toString();

  bool _isStoreKind(Map<String, dynamic> data) {
    if (data['deletedAt'] != null) return false;
    final kind = (data['kind'] ?? '').toString().toLowerCase();
    if (kind.isNotEmpty) return kind == section;
    final category = (data['category'] ?? '').toString().toLowerCase();
    return dining
        ? category.contains('cafe') || category.contains('café') ||
            category.contains('restaurant') || category.contains('dining') ||
            category.contains('food')
        : category.contains('shop') || category.contains('retail') ||
            category.contains('souvenir') || category.contains('gift');
  }

  Widget _editorPanel(String title, IconData icon, List<Widget> fields) =>
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCFB),
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: const Color(0xFFE7D9D7)),
          boxShadow: const [BoxShadow(
            color: Color(0x100F151C), blurRadius: 18,
            offset: Offset(0, 5))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7EBE9),
                  borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: adminRose, size: 20)),
              const SizedBox(width: 11),
              Expanded(child: Text(title,
                style: const TextStyle(fontSize: 17,
                  fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 21),
            ...fields,
          ],
        ),
      );

  Future<void> _edit({required String shopId,
      String? id, Map<String, dynamic>? item}) async {
    final name = TextEditingController(text: item?['name']?.toString() ?? '');
    final description = TextEditingController(
        text: item?['description']?.toString() ?? '');
    final price = TextEditingController(text: item?['priceMinor'] is num
        ? ((item!['priceMinor'] as num) / 100).toStringAsFixed(2) : '');
    final stock = TextEditingController(text: (item?['stockQuantity'] as num?)?.toInt().toString() ?? '0');
    final isDining = dining;
    final choices = isDining ? foodCategories : retailCategories;
    String category = choices.contains(item?['category'])
        ? item!['category'] as String : choices.first;
    bool active = item?['active'] != false;
    final form = GlobalKey<FormState>();
    Uint8List? photoBytes;
    String photoExtension = 'jpg';
    String? error;
    bool saving = false;
    final originalImageUrl = item?['imageUrl']?.toString() ?? '';

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) {
        final productLabel = isDining ? 'Food & Drink' : 'Souvenir & Shop';
        final detailsPanel = _editorPanel('Product details',
          isDining ? Icons.restaurant_menu_outlined : Icons.shopping_bag_outlined, [
          const Text('Product name *',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          TextFormField(controller: name, maxLength: 90, enabled: !saving,
            decoration: InputDecoration(counterText: '',
              hintText: isDining ? 'e.g. Strawberry Cheesecake' : 'e.g. Theme Park Keychain'),
            validator: (v) => (v ?? '').trim().length < 2
              ? 'Enter at least 2 characters.' : null),
          const SizedBox(height: 19),
          const Text('Short description',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          TextFormField(controller: description, maxLength: 250, maxLines: 3,
            enabled: !saving,
            decoration: const InputDecoration(
              hintText: 'Describe what guests will receive',
              alignLabelWithHint: true)),
          const SizedBox(height: 15),
          const Text('Product category *',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: category, isExpanded: true,
            decoration: const InputDecoration(),
            items: choices.map((v) => DropdownMenuItem(
              value: v, child: Text(v))).toList(),
            onChanged: saving ? null : (v) {
              if (v != null) update(() => category = v);
            },
          ),
        ]);

        final photoPreview = photoBytes != null
          ? Image.memory(photoBytes!, width: double.infinity,
              height: 165, fit: BoxFit.cover)
          : originalImageUrl.isNotEmpty
            ? ParkCatalogNetworkImage(
                url: originalImageUrl,
                width: double.infinity,
                height: 165,
                fallback: const Center(
                  child: Icon(Icons.broken_image_outlined, size: 42, color: adminRose),
                ),
              )
            : const Center(child: Icon(Icons.add_photo_alternate_outlined,
                size: 48, color: adminRose));

        final commercialPanel = _editorPanel('Pricing & photo',
          Icons.sell_outlined, [
          const Text('Price (RM) *',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          TextFormField(controller: price, enabled: !saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(hintText: 'e.g. 18.90'),
            validator: (v) => parseMoneyMinor(v ?? '') == null
              ? 'Enter a price from RM0.01 to RM100,000.' : null),
           const SizedBox(height: 14),
           if (!isDining) ...[
             const Text('Inventory quantity *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
             const SizedBox(height: 8),
             TextFormField(controller: stock, enabled: !saving,
               keyboardType: TextInputType.number,
               inputFormatters: [FilteringTextInputFormatter.digitsOnly],
               decoration: const InputDecoration(hintText: 'e.g. 50'),
               validator: (v) { final n = int.tryParse(v ?? '');
                 return n == null || n < 0 || n > 1000000 ? 'Enter stock from 0 to 1,000,000.' : null;
               }),
             const SizedBox(height: 16),
           ],
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8F1F0),
              borderRadius: BorderRadius.circular(15)),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
              title: const Text('Available for sale',
                style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Turn off to hide unavailable products.',
                style: TextStyle(fontSize: 12)),
              value: active,
              onChanged: saving ? null : (v) => update(() => active = v),
            ),
          ),
          const SizedBox(height: 22),
          const Text('Product photo *',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              color: const Color(0xFFF8F1F0),
              width: double.infinity,
              height: 165,
              child: photoPreview,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: saving ? null : () async {
              try {
                final file = await FilePicker.pickFile(
                  type: FileType.custom,
                  allowedExtensions: ['jpg', 'jpeg', 'png', 'webp']);
                if (file == null) return;
                final bytes = await file.readAsBytes();
                if (bytes.isEmpty || bytes.length >= 2 * 1024 * 1024) {
                  throw const FormatException(
                    'Choose a JPG, PNG or WebP photo smaller than 2 MB.');
                }
                if (!ctx.mounted) return;
                update(() {
                  photoBytes = bytes;
                  photoExtension = (file.extension ?? 'jpg').toLowerCase();
                  error = null;
                });
              } catch (e) {
                if (ctx.mounted) update(() => error = 'Photo selection failed: $e');
              }
            },
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(photoBytes != null || originalImageUrl.isNotEmpty
              ? 'Change photo' : 'Choose product photo'),
          ),
          const SizedBox(height: 6),
          const Text('JPG / PNG / WebP · under 2 MB',
            style: TextStyle(fontSize: 12, color: adminMuted)),
          const SizedBox(height: 15),
          const Text('Products are linked to the selected Park Facilities location. '
              'Online checkout and stock tracking are not connected yet.',
            style: TextStyle(color: adminMuted, fontSize: 12, height: 1.5)),
        ]);

        return AlertDialog(
          backgroundColor: const Color(0xFFF4E8E7),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28)),
          elevation: 20,
          shadowColor: const Color(0x550F151C),
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          titlePadding: const EdgeInsets.fromLTRB(26, 23, 26, 15),
          contentPadding: const EdgeInsets.fromLTRB(26, 3, 26, 12),
          actionsPadding: const EdgeInsets.fromLTRB(26, 10, 26, 20),
          title: Row(children: [
            Container(width: 50, height: 50,
              decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(15)),
              child: Icon(isDining ? Icons.restaurant_menu_outlined :
                Icons.shopping_bag_outlined, color: adminRose)),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${id == null ? 'Add' : 'Edit'} $productLabel Product',
                  style: const TextStyle(fontSize: 23,
                    fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Product details · Pricing · Photo · Availability',
                  style: TextStyle(color: adminMuted, fontSize: 12)),
              ],
            )),
            IconButton(icon: const Icon(Icons.close_rounded),
              onPressed: saving ? null : () => Navigator.pop(ctx)),
          ]),
          content: SizedBox(
            width: 920,
            height: MediaQuery.sizeOf(ctx).height * 0.64,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(3, 8, 3, 8),
              child: Form(key: form,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: LayoutBuilder(builder: (context, c) {
                  final panels = c.maxWidth < 720
                    ? Column(children: [detailsPanel,
                        const SizedBox(height: 16), commercialPanel])
                    : Row(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [Expanded(child: detailsPanel),
                          const SizedBox(width: 16),
                          Expanded(child: commercialPanel)]);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      panels,
                      if (error != null) Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(error!, style: const TextStyle(
                          color: Colors.red, fontSize: 13))),
                    ],
                  );
                }),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: adminRose))),
            FilledButton.icon(
              onPressed: saving ? null : () async {
                if (form.currentState?.validate() != true) return;
                if (photoBytes == null && originalImageUrl.isEmpty) {
                  update(() => error = 'Please choose a product photo.');
                  return;
                }
                update(() { saving = true; error = null; });
                try {
                  String imageUrl = originalImageUrl;
                  if (photoBytes != null) {
                    final mime = photoExtension == 'png' ? 'image/png' :
                      photoExtension == 'webp' ? 'image/webp' : 'image/jpeg';
                    final app = Firebase.app('ThemeParkAdmin');
                    final storage = FirebaseStorage.instanceFor(app: app);
                    final fileName = '${DateTime.now().microsecondsSinceEpoch}.$photoExtension';
                    final fileRef = storage.ref('catalog-images/'
                      '${isDining ? 'dining' : 'shops'}/$fileName');
                    final upload = fileRef.putData(photoBytes!,
                      SettableMetadata(contentType: mime));
                    await upload.timeout(const Duration(seconds: 35));
                    imageUrl = await fileRef.getDownloadURL()
                      .timeout(const Duration(seconds: 15));
                  }
                  final data = <String, dynamic>{
                    'storeId': shopId,
                    'name': name.text.trim(),
                    'description': description.text.trim(),
                    'category': category,
                    'priceMinor': parseMoneyMinor(price.text)!,
                    if (!isDining) 'stockQuantity': int.parse(stock.text),
                    'currency': 'MYR',
                    'active': active,
                    'imageUrl': imageUrl,
                    'updatedAt': FieldValue.serverTimestamp(),
                  };
                  final collection = widget.db.collection('parkMenuItems');
                  if (id == null) {
                    await collection.add({
                      ...data, 'createdAt': FieldValue.serverTimestamp(),
                    });
                  } else {
                    await collection.doc(id).update(data);
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) update(() {
                    error = 'Could not save product: $e';
                    saving = false;
                  });
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: adminRose,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15))),
              icon: saving ? const SizedBox(width: 17, height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2,
                    color: Colors.white)) : const Icon(Icons.check_rounded),
              label: Text(saving ? 'Uploading & saving...' : 'Save Product',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      }),
    );
    name.dispose(); description.dispose(); price.dispose();
    if (saved == true && mounted) {
      setState(() => feedback = 'Product and photo saved successfully.');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AdminHeading('Food & Retail',
          'Manage menus and souvenir products by actual park location'),
      const SizedBox(height: 12),
      Wrap(spacing: 9, runSpacing: 8, children: [
        ChoiceChip(label: const Text('Food & Drink'),
          avatar: const Icon(Icons.restaurant_menu_outlined, size: 17),
          selected: dining,
          onSelected: (_) => setState(() {
            section = 'dining'; storeId = null;
            categoryFilter = 'All Categories'; search = ''; feedback = null;
          })),
        ChoiceChip(label: const Text('Souvenirs & Shops'),
          avatar: const Icon(Icons.shopping_bag_outlined, size: 17),
          selected: !dining,
          onSelected: (_) => setState(() {
            section = 'shops'; storeId = null;
            categoryFilter = 'All Categories'; search = ''; feedback = null;
          })),
      ]),
      const SizedBox(height: 11),
      Text('Select a ${dining ? 'restaurant or café' : 'shop'} from Park Facilities. '
          'Products are grouped under that location, not stored as duplicate park places. '
          + (dining
            ? 'Food catalogue only. Online food checkout is not enabled.'
            : 'Souvenir inventory is reserved during Stripe checkout. Process paid purchases in Products & Sales > Bookings & Orders.'),
          style: const TextStyle(color: adminMuted, fontSize: 12)),
      const SizedBox(height: 15),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: widget.db.collection('attractions').snapshots(),
        builder: (context, placesSnap) {
          if (placesSnap.hasError) return const AdminCard(child: Text(
            'Unable to load Park Facilities. Check admin permissions.'));
          if (!placesSnap.hasData) return const LinearProgressIndicator();
          final stores = placesSnap.data!.docs
              .where((d) => _isStoreKind(d.data())).toList()
            ..sort((a, b) => _label(a.data())
                .toLowerCase().compareTo(_label(b.data()).toLowerCase()));
          if (stores.isEmpty) return AdminCard(child: Text(
            dining
              ? 'No Food & Drink location. Create a dining place under Park Facilities first.'
              : 'No Shops location. Create a souvenir or retail shop under Park Facilities first.'));
          final current = stores.any((d) => d.id == storeId)
              ? storeId! : stores.first.id;
          final selectedStore = stores.firstWhere((d) => d.id == current);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AdminCard(child: Wrap(spacing: 14, runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(width: 350, child: DropdownButtonFormField<String>(
                  value: current,
                  decoration: InputDecoration(labelText: dining
                      ? 'Restaurant / Café' : 'Souvenir / Retail Shop'),
                  isExpanded: true,
                  items: stores.map((e) => DropdownMenuItem(value: e.id,
                    child: Text(_label(e.data()),
                        overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setState(() {
                    storeId = v; categoryFilter = 'All Categories';
                    search = ''; feedback = null;
                  }),
                )),
                FilledButton.icon(
                  onPressed: busy ? null : () => _edit(shopId: current),
                  icon: const Icon(Icons.add), label: const Text('Add Product')),
              ])),
            const SizedBox(height: 14),
            if (feedback != null) Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(feedback!, style: const TextStyle(color: adminMuted))),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: widget.db.collection('parkMenuItems').snapshots(),
              builder: (context, itemsSnap) {
                if (itemsSnap.hasError) return const AdminCard(child: Text(
                  'Cannot load catalogue. Check Firestore rules.'));
                if (!itemsSnap.hasData) return const LinearProgressIndicator();
                final all = itemsSnap.data!.docs
                    .where((d) => d.data()['storeId'] == current).toList();
                final entries = all.where((d) {
                  final data = d.data();
                  final matchesCategory = categoryFilter == 'All Categories' ||
                      data['category'] == categoryFilter;
                  final q = search.trim().toLowerCase();
                  final matchesText = q.isEmpty ||
                      '${data['name']} ${data['description']}'
                          .toLowerCase().contains(q);
                  return matchesCategory && matchesText;
                }).toList()..sort((a, b) => _label(a.data())
                    .toLowerCase().compareTo(_label(b.data()).toLowerCase()));
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AdminCard(child: Wrap(spacing: 12, runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center, children: [
                        SizedBox(width: 300, child: TextField(
                          key: ValueKey('catalogue-search-$section-$current'),
                          onChanged: (v) => setState(() => search = v),
                          decoration: const InputDecoration(
                            labelText: 'Search products',
                            prefixIcon: Icon(Icons.search, size: 20)),
                        )),
                        SizedBox(width: 220, child: DropdownButtonFormField<String>(
                          value: categoryFilter,
                          decoration: const InputDecoration(labelText: 'Category'),
                          items: ['All Categories', ...categories]
                              .map((v) => DropdownMenuItem(value: v,
                                  child: Text(v))).toList(),
                          onChanged: (v) => setState(
                              () => categoryFilter = v ?? 'All Categories'),
                        )),
                        Text('${all.length} products in ${_label(selectedStore.data())}',
                            style: const TextStyle(color: adminMuted)),
                      ])),
                    const SizedBox(height: 10),
                    if (entries.isEmpty) AdminCard(child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(all.isEmpty
                        ? 'No products in ${_label(selectedStore.data())}. Add one above.'
                        : 'No products match these filters.'),
                    )) else AdminCard(padding: EdgeInsets.zero,
                      child: Column(children: [
                        for (final entry in entries) ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: SizedBox(width: 48, height: 48,
                              child: ParkCatalogNetworkImage(
                                url: entry.data()['imageUrl']?.toString() ?? '',
                                width: 48,
                                height: 48,
                                fallback: Container(
                                  color: const Color(0xFFF5E9E5),
                                  child: Icon(
                                    dining ? Icons.restaurant_menu_outlined
                                        : Icons.shopping_bag_outlined,
                                    color: adminRose,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          title: Text(_label(entry.data())),
                          subtitle: Text('${entry.data()['category'] ?? 'Other'} · '
                            '${entry.data()['active'] == true ? 'Available' : 'Unavailable'}'
                             '${!dining ? ' · Stock: ${(entry.data()['stockQuantity'] as num?)?.toInt() ?? 0}' : ''}'),
                          trailing: Wrap(spacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(money((entry.data()['priceMinor'] as num?)?.toInt() ?? 0),
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                              OutlinedButton(
                                onPressed: busy ? null : () => _edit(
                                  shopId: current, id: entry.id, item: entry.data()),
                                child: const Text('Edit')),
                            ],
                          ),
                        ),
                      ])),
                  ],
                );
              },
            ),
          ]);
        },
      ),
    ],
  );
}
