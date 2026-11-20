import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import '../../photos/photo_repository.dart';
import '../../photos/photo_widgets.dart';
import '../admin_widgets.dart';
import '../admin_models.dart';
import 'photo_admin_repository.dart';
import '../operations/park_admin_repository.dart';
import '../operations/park_management_page.dart';

class PhotoManagement extends StatefulWidget {
  final PhotoAdminRepository repository;
  final List<AdminVisitor> visitors;
  final bool staffMode;
  final ParkAdminRepository? parkSettingsRepository;
  const PhotoManagement({
    super.key,
    required this.repository,
    required this.visitors,
    this.staffMode = false,
    this.parkSettingsRepository,
  });
  @override
  State<PhotoManagement> createState() => _PhotoManagementState();
}

class _PhotoManagementState extends State<PhotoManagement> {
  late final photos = widget.repository.records('parkPhotos'),
      orders = widget.repository.records('photoOrders'),
      matches = widget.repository.records('photoMatches'),
      reviews = widget.repository.records('photoMatchReviews');
  late final uploaderNames = widget.staffMode
      ? Stream<Map<String, String>>.value(const {})
      : widget.repository is FirebasePhotoAdminRepository
          ? (widget.repository as FirebasePhotoAdminRepository)
              .db.collection('staffProfiles').snapshots().map((snapshot) => {
                for (final doc in snapshot.docs)
                  doc.id: (doc.data()['fullName'] as String? ?? '').trim(),
              })
          : Stream<Map<String, String>>.value(const {});
  String tab = 'Photos', query = '';
  int page = 0;
  bool awaitingDeliveryOnly = false;
  final busy = <String>{};
  String? error;
  String uploaderLabel(ParkPhoto photo, Map<String, String> names) {
    final uid = photo.data['photographerUid'] as String? ?? '';
    final found = names[uid] ?? '';
    if (found.isNotEmpty) return found;
    return uid.isEmpty ? 'Unknown' : 'Staff ID ${uid.substring(0, uid.length < 8 ? uid.length : 8)}';
  }
  String name(String uid) =>
      widget.visitors.where((v) => v.id == uid).firstOrNull?.name ??
      (uid.length > 12 ? '${uid.substring(0, 12)}…' : uid);
  Future<void> action(
    String operation,
    ParkPhoto photo,
    Map<String, dynamic> data,
  ) async {
    if (busy.contains(photo.id)) return;
    setState(() {
      busy.add(photo.id);
      error = null;
    });
    try {
      final result = await widget.repository.request(operation, data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              operation == 'recheck'
                  ? 'Matching completed: ${result['matched'] ?? 0} visitors.'
                  : 'Photo record updated.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = photoError(e));
    } finally {
      if (mounted) setState(() => busy.remove(photo.id));
    }
  }

  Future<void> original(ParkPhoto photo) async {
    try {
      final value = await widget.repository.request('adminOriginal', {
        'photoId': photo.id,
      });
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
        backgroundColor: const Color(0xFFF4E8E7),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850, maxHeight: 760),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      photo.title,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Flexible(
                      child: PhotoImage(
                        value['imageBase64'] as String,
                        width: double.infinity,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = photoError(e));
    }
  }

  Future<void> code(ParkPhoto photo) async {
    final value = photo.data['claimCode'] as String?;
    if (value == null || value.isEmpty) {
      setState(
        () => error =
            'This photo does not have a collection code. Upload it again with a new reference.',
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFF4E8E7),
        title: const Text('Photographer Photo Code'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: 'PP1:$value',
                size: 245,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 15),
              SelectableText(value, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text(
                'Share this code with the photographed visitor. Valid for 24 hours after upload.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: adminMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            child: const Text('Copy Code'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void orderDetails(ParkPhoto order) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFFF4E8E7),
      title: Text(photoOrderReference(order.id)),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Visitor: ${name(order.data['ownerUid'] as String)}'),
              const SizedBox(height: 12),
              Text('Delivery: ${order.data['deliveryEmail'] ?? '—'}'),
              Text('Email status: ${order.data['emailStatus'] ?? 'pending'}'),
              const Divider(height: 25),
              for (final item in (order.data['items'] as List).cast<Map>())
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['title'] as String),
                  subtitle: Text(
                    '${photoFormat(item['format'] as String)} • ${item['quantity'] ?? 1} copies',
                  ),
                  trailing: Text(photoMoney(item['priceMinor'] as num)),
                ),
              const Divider(),
              Text(
                'Total: ${photoMoney(order.data['totalMinor'] as num)}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: adminRose,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => StreamBuilder<List<ParkPhoto>>(
    stream: photos,
    builder: (context, p) => StreamBuilder<List<ParkPhoto>>(
      stream: orders,
      builder: (context, o) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 20,
            runSpacing: 14,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Smart Photos',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w700,
                      color: adminDark,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    widget.staffMode ? 'Manage your park photographs.' : 'Manage park photography, photo matches and purchases.',
                    style: TextStyle(color: adminMuted),
                  ),
                ],
              ),
              AdminButton(
                'Bulk Upload Photos',
                icon: Icons.add_photo_alternate_outlined,
                onPressed: () async {
                  await showDialog<void>(
                    context: context,
                    builder: (_) =>
                        PhotoUploadDialog(repository: widget.repository),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          const SizedBox(height: 24),
          if (p.hasError || o.hasError)
            const AdminCard(
              child: Text(
                'Unable to load photo records. Please refresh the portal.',
              ),
            ),
          StreamBuilder<List<ParkPhoto>>(
            stream: reviews,
            builder: (context, r) {
              final photoRows = p.data ?? <ParkPhoto>[];
              final ordersRows = o.data ?? <ParkPhoto>[];
              final pendingReviews = (r.data ?? <ParkPhoto>[])
                  .where((x) => x.data['status'] == 'open').length;
              final withoutMatch = photoRows.where((x) =>
                x.data['status'] == 'active' &&
                (x.data['matchedVisitorCount'] as num? ?? 0) == 0).length;
              final emailPending = ordersRows.where((x) =>
                x.data['status'] == 'confirmed' &&
                x.data['emailStatus'] != 'sent').length;
              final weekAgo = DateTime.now().subtract(const Duration(days: 7));
              final weeklyRevenue = ordersRows.where((x) =>
                x.data['status'] == 'confirmed' &&
                (adminDate(x.data['createdAt'])?.isAfter(weekAgo) ?? false))
                  .fold<int>(0, (v, x) => v +
                    (x.data['totalMinor'] as num? ?? 0).toInt());
              return Wrap(spacing: 16, runSpacing: 16, children: [
                _stat('Unmatched Photos', '$withoutMatch', Icons.image_search_outlined),
                if (!widget.staffMode) _stat('Open Match Reviews', '$pendingReviews',
                  Icons.report_outlined),
                if (!widget.staffMode) _stat('Pending Email Delivery', '$emailPending',
                  Icons.mark_email_unread_outlined),
                if (!widget.staffMode) _stat('Photo Sales · 7 Days',
                  photoMoney(weeklyRevenue), Icons.payments_outlined),
              ]);
            },
          ),
          const SizedBox(height: 25),
          AdminCard(
            child: Wrap(
              spacing: 14,
              runSpacing: 15,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final value in widget.staffMode
                    ? const ['Photos']
                    : const ['Photos', 'Matches', 'Review Requests', 'Orders'])
                  ChoiceChip(
                    label: Text(value),
                    selected: tab == value,
                    onSelected: (_) => setState(() {
                      tab = value;
                      page = 0;
                    }),
                  ),
                if (tab == 'Orders')
                  FilterChip(
                    label: const Text('Awaiting email delivery'),
                    selected: awaitingDeliveryOnly,
                    onSelected: (value) => setState(() {
                      awaitingDeliveryOnly = value;
                      page = 0;
                    }),
                  ),
                SizedBox(
                  width: 250,
                  child: TextField(
                    onChanged: (v) => setState(() {
                      query = v.trim().toLowerCase();
                      page = 0;
                    }),
                    decoration: const InputDecoration(
                      hintText: 'Search photo, visitor or order',
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          if (tab == 'Photos')
            StreamBuilder<Map<String, String>>(
              stream: uploaderNames,
              builder: (context, n) => _catalogue(p.data ?? [], n.data ?? const {}),
            )
          else if (tab == 'Orders')
            _orderTable(o.data ?? [])
          else
            StreamBuilder<List<ParkPhoto>>(
              stream: tab == 'Matches' ? matches : reviews,
              builder: (context, s) => s.hasError
                  ? const AdminCard(
                      child: Text('Unable to load matching records.'),
                    )
                  : _matchTable(s.data ?? []),
            ),
        ],
      ),
    ),
  );
  Widget _stat(String title, String value, IconData icon) => SizedBox(
    width: 230,
    child: AdminCard(
      child: Row(
        children: [
          Icon(icon, color: adminRose, size: 31),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: adminMuted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: adminDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _catalogue(List<ParkPhoto> all, Map<String, String> names) {
    final records =
        all
            .where(
              (p) =>
                  query.isEmpty ||
                  ('${p.title} ${p.place}').toLowerCase().contains(query),
            )
            .toList()
          ..sort(
            (a, b) =>
                ((b.data['createdAt'] as Timestamp?)?.toDate() ??
                        DateTime(1970))
                    .compareTo(
                      (a.data['createdAt'] as Timestamp?)?.toDate() ??
                          DateTime(1970),
                    ),
          );
    return Column(
      children: [
        if (records.isEmpty)
          const AdminCard(
            child: AdminEmpty(
              'No park photos found',
              'Upload a photographer photo to make it available for matching and photo-code access.',
            ),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              final columns = c.maxWidth >= 1100
                  ? 4
                  : c.maxWidth >= 800
                  ? 3
                  : c.maxWidth >= 530
                  ? 2
                  : 1;
              return GridView.builder(
                itemCount: records.skip(page * 12).take(12).length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 17,
                  mainAxisSpacing: 17,
                  childAspectRatio: .76,
                ),
                itemBuilder: (context, index) {
                  final photo = records[page * 12 + index],
                      archived = photo.data['status'] == 'archived';
                  return AdminCard(
                    padding: const EdgeInsets.all(13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: widget.staffMode ? null : () => original(photo),
                            child: PhotoImage(
                              photo.preview,
                              width: double.infinity,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          photo.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 5),
                        Text('Uploaded by ${uploaderLabel(photo, names)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: adminMuted)),
                        const SizedBox(height: 7),
                        Text(
                          '${photo.data['faceCount'] ?? 0} faces • ${photo.data['matchedVisitorCount'] ?? 0} matches',
                          style: const TextStyle(
                            fontSize: 11,
                            color: adminMuted,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            AdminBadge(
                              archived ? 'Archived' : 'Active',
                              tone: archived ? 'inactive' : 'active',
                            ),
                            const Spacer(),
                            PopupMenuButton<String>(
                              enabled: !busy.contains(photo.id),
                              onSelected: (value) {
                                if (value == 'code') code(photo);
                                if (value == 'original') original(photo);
                                if (value == 'recheck') {
                                  action('recheck', photo, {
                                    'photoId': photo.id,
                                  });
                                }
                                if (value == 'archive') {
                                  action('archive', photo, {
                                    'photoId': photo.id,
                                    'archived': !archived,
                                  });
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'code',
                                  child: Text('Show Photo Code'),
                                ),
                                if (!widget.staffMode) const PopupMenuItem(
                                  value: 'original',
                                  child: Text('View Original'),
                                ),
                                if (!widget.staffMode) const PopupMenuItem(
                                  value: 'recheck',
                                  child: Text('Recheck Matches'),
                                ),
                                if (!widget.staffMode) PopupMenuItem(
                                  value: 'archive',
                                  child: Text(
                                    archived
                                        ? 'Restore Photo'
                                        : 'Archive Photo',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        const SizedBox(height: 15),
        _pagination(records.length),
      ],
    );
  }

  Widget _orderTable(List<ParkPhoto> all) {
    final rows = all
        .where((order) => !awaitingDeliveryOnly ||
            order.data['emailStatus'] != 'sent')
        .where(
          (o) =>
              query.isEmpty ||
              ('${photoOrderReference(o.id)} ${name(o.data['ownerUid'] as String)} ${o.data['deliveryEmail']}')
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    return Column(
      children: [
        AdminCard(
          padding: EdgeInsets.zero,
          child: rows.isEmpty
              ? const AdminEmpty(
                  'No photo orders found',
                  'Confirmed customer photo purchases will appear here.',
                )
              : AdminTable(
                  minWidth: 900,
                  columns: const [
                    DataColumn(label: Text('Order')),
                    DataColumn(label: Text('Visitor')),
                    DataColumn(label: Text('Photos')),
                    DataColumn(label: Text('Total')),
                    DataColumn(label: Text('Delivery')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: [
                    for (final order in rows.skip(page * 12).take(12))
                      DataRow(
                        cells: [
                          DataCell(Text(photoOrderReference(order.id))),
                          DataCell(
                            Text(name(order.data['ownerUid'] as String)),
                          ),
                          DataCell(
                            Text('${(order.data['items'] as List).length}'),
                          ),
                          DataCell(
                            Text(photoMoney(order.data['totalMinor'] as num)),
                          ),
                          DataCell(
                            AdminBadge(
                              order.data['emailStatus'] == 'sent'
                                  ? 'Sent'
                                  : 'Pending',
                              tone: order.data['emailStatus'] == 'sent'
                                  ? 'active'
                                  : 'pending',
                            ),
                          ),
                          DataCell(
                            TextButton(
                              onPressed: () => orderDetails(order),
                              child: const Text('View Order'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 15),
        _pagination(rows.length),
      ],
    );
  }

  Widget _matchTable(List<ParkPhoto> all) {
    final rows = all
        .where(
          (r) =>
              query.isEmpty ||
              ('${r.data['photoId']} ${name(r.data['ownerUid'] as String)}')
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    return Column(
      children: [
        AdminCard(
          padding: EdgeInsets.zero,
          child: rows.isEmpty
              ? const AdminEmpty(
                  'No matching records found',
                  'Face matches, photo-code access and visitor review requests appear here.',
                )
              : AdminTable(
                  minWidth: 930,
                  columns: const [
                    DataColumn(label: Text('Photo')),
                    DataColumn(label: Text('Visitor')),
                    DataColumn(label: Text('Source')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: [
                    for (final record in rows.skip(page * 12).take(12))
                      DataRow(
                        cells: [
                          DataCell(
                            Text(
                              record.data['title'] as String? ??
                                  record.data['photoId'] as String,
                            ),
                          ),
                          DataCell(
                            Text(name(record.data['ownerUid'] as String)),
                          ),
                          DataCell(
                            Text(
                              record.data['source'] == 'photo-code'
                                  ? 'Photo code'
                                  : record.data['score'] is num
                                  ? 'Face match ${((record.data['score'] as num) * 100).round()}%'
                                  : 'Visitor report',
                            ),
                          ),
                          DataCell(
                            AdminBadge(
                              tab == 'Review Requests'
                                  ? (record.data['status'] as String? ?? 'open')
                                  : record.data['hidden'] == true
                                  ? 'Hidden'
                                  : 'Visible',
                              tone: record.data['hidden'] == true
                                  ? 'inactive'
                                  : 'active',
                            ),
                          ),
                          DataCell(
                            tab == 'Review Requests'
                                ? TextButton(
                                    onPressed:
                                        record.data['status'] == 'reviewed' ||
                                            busy.contains(record.id)
                                        ? null
                                        : () => action(
                                            'resolveReview',
                                            record,
                                            {'reviewId': record.id},
                                          ),
                                    child: const Text('Mark Reviewed'),
                                  )
                                : const Text('—'),
                          ),
                        ],
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 15),
        _pagination(rows.length),
      ],
    );
  }

  Widget _pagination(int count) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Text(
        '${count == 0 ? 0 : page * 12 + 1}–${(page * 12 + 12).clamp(0, count)} of $count',
        style: const TextStyle(color: adminMuted, fontSize: 12),
      ),
      const SizedBox(width: 15),
      IconButton(
        tooltip: 'Previous page',
        onPressed: page == 0 ? null : () => setState(() => page--),
        icon: const Icon(Icons.chevron_left),
      ),
      IconButton(
        tooltip: 'Next page',
        onPressed: (page + 1) * 12 >= count
            ? null
            : () => setState(() => page++),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}

class PhotoUploadDialog extends StatefulWidget {
  final PhotoAdminRepository repository;
  const PhotoUploadDialog({super.key, required this.repository});
  @override
  State<PhotoUploadDialog> createState() => _PhotoUploadDialogState();
}

class _PhotoUploadDialogState extends State<PhotoUploadDialog> {
  List<PlatformFile> selected = [];
  final uploaded = <int>{};
  final failed = <int, String>{};
  final references = <int, String>{};
  late final places = widget.repository.places();
  String? attractionId, error;
  bool busy = false, stopped = false;
  int completed = 0;

  Future<void> choose() async {
    if (busy) return;
    try {
      // file_picker v12: pickFiles() selects multiple, without allowMultiple.
      final files = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png']);
      if (files.isEmpty) return;
      if (files.length > 300) {
        throw StateError('Select up to 300 photos per batch.');
      }
      if (!mounted) return;
      setState(() {
        selected = files;
        uploaded.clear(); failed.clear(); references.clear();
        completed = 0; error = null; stopped = false;
      });
    } catch (e) {
      if (mounted) setState(() => error = e is StateError
        ? e.message.toString() : 'Could not select photos.');
    }
  }

  Future<void> upload() async {
    if (busy || selected.isEmpty) return;
    setState(() { busy = true; stopped = false; error = null; });
    final now = DateTime.now();
    for (var index = 0; index < selected.length; index++) {
      if (stopped) break;
      if (uploaded.contains(index)) continue;
      final file = selected[index];
      try {
        if (await file.length() > 12000000) {
          throw StateError('Larger than 12 MB');
        }
        final input = await file.readAsBytes();
        final decoded = img.decodeImage(input);
        if (decoded == null) throw StateError('Unreadable image');
        final oriented = img.bakeOrientation(decoded);
        final resized = img.copyResize(oriented,
          width: oriented.width > 2400 ? 2400 : oriented.width);
        final bytes = img.encodeJpg(resized, quality: 85);
        // Backend currently requires a title; generate it instead of asking
        // a photographer to type hundreds of individual names.
        final autoTitle = 'Park Photo ${now.year}${now.month.toString().padLeft(2,'0')}'
          '${now.day.toString().padLeft(2,'0')}-${index + 1}';
        final requestId = references.putIfAbsent(index,
          () => widget.repository.newRequestId());
        await widget.repository.request('upload', {
          'requestId': requestId,
          'title': autoTitle,
          'takenAt': now.toUtc().toIso8601String(),
          'attractionId': attractionId ?? '',
          'imageBase64': base64Encode(bytes),
        });
        uploaded.add(index);
        failed.remove(index);
      } catch (e) {
        failed[index] = photoError(e);
      }
      if (mounted) setState(() => completed = uploaded.length + failed.length);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Dialog(
      backgroundColor: const Color(0xFFF4E8E7),
      elevation: 16,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820,
        maxHeight: 790), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(25, 22, 18, 20),
          child: Row(children: [
            const Icon(Icons.photo_library_outlined, color: adminRose, size: 32),
            const SizedBox(width: 13),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text('Bulk Upload Photos', style: TextStyle(
                fontSize: 25, fontWeight: FontWeight.w800)),
                Text('Select photos once. No individual titles needed.',
                  style: TextStyle(color: adminMuted, fontSize: 13))])),
            IconButton(onPressed: busy ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close)),
          ])),
        const Divider(height: 1),
        Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(padding: const EdgeInsets.all(23),
              decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: const Color(0xFFE8D7D5))),
              child: Column(children: [
                const Icon(Icons.cloud_upload_outlined, size: 56, color: adminRose),
                const SizedBox(height: 10),
                Text(selected.isEmpty ? 'Choose JPG / PNG photos' :
                  '${selected.length} photos selected',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: busy ? null : choose,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(selected.isEmpty ? 'Choose Photos' : 'Choose Different Photos')),
                if (selected.isNotEmpty) ...[
                  const SizedBox(height: 11),
                  Text(selected.take(3).map((e) => e.name).join(' · '),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: adminMuted, fontSize: 12)),
                ],
              ])),
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: const Color(0xFFE8D7D5))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Upload details', style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 17)),
                  const SizedBox(height: 7),
                  const Row(children: [Icon(Icons.verified_user_outlined,
                    size: 17, color: adminRose), SizedBox(width: 8),
                    Expanded(child: Text('Photographer: current signed-in account (recorded automatically)',
                      style: TextStyle(fontSize: 12, color: adminMuted)))]),
                  const SizedBox(height: 17),
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: places,
                    builder: (context, s) {
                      final values = s.data ?? const <Map<String, dynamic>>[];
                      // A location is useful for searching, but never required.
                      return DropdownButtonFormField<String>(
                        value: attractionId ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Photo spot (optional)',
                          border: OutlineInputBorder()),
                        items: [const DropdownMenuItem(value: '',
                          child: Text('Not specified')),
                          for (final place in values)
                            DropdownMenuItem(value: place['id'] as String,
                              child: Text(place['name'] as String)),
                        ],
                        onChanged: busy ? null : (v) => setState(() => attractionId = v),
                      );
                    }),
                ])),
            if (selected.isNotEmpty) ...[
              const SizedBox(height: 22),
              LinearProgressIndicator(value: selected.isEmpty ? null :
                completed / selected.length, color: adminRose),
              const SizedBox(height: 10),
              Text('Uploaded ${uploaded.length} / ${selected.length}  ·  Failed ${failed.length}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
              if (failed.isNotEmpty) ...[
                const SizedBox(height: 7),
                for (final item in failed.entries.take(4))
                  Text('${selected[item.key].name}: ${item.value}',
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ],
            if (error != null) Padding(padding: const EdgeInsets.only(top: 15),
              child: Text(error!, style: const TextStyle(color: Colors.red))),
          ]))),
        const Divider(height: 1),
        Padding(padding: const EdgeInsets.all(19),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: busy ? () => setState(() => stopped = true) :
              () => Navigator.pop(context),
              child: Text(busy ? 'Stop after current photo' : 'Close')),
            const SizedBox(width: 11),
            FilledButton.icon(onPressed: busy || selected.isEmpty ||
              uploaded.length == selected.length ? null : upload,
              style: FilledButton.styleFrom(backgroundColor: adminRose),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(busy ? 'Uploading…' :
                failed.isNotEmpty ? 'Retry Remaining' : 'Upload All'),
            ),
          ])),
      ])),
    ),
  );
}
