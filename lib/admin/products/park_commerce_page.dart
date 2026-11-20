import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../admin_store.dart';
import '../admin_widgets.dart';
import '../package_management.dart';
import '../ticket_management.dart';
import '../operations/park_admin_repository.dart';
import '../operations/reports_page.dart';
import '../../visitor/models/tickets.dart';
import 'park_menu_management_page.dart';
import 'ticket_bundle_management_page.dart';
import 'photo_product_catalogue_page.dart';
import 'souvenir_admin_page.dart';

/// Business navigation: sales first; all admission products live together.
/// The report is backed by the existing verified admin reporting endpoint.
class ParkCommercePage extends StatefulWidget {
  const ParkCommercePage({super.key, required this.store,
    required this.onValidate, required this.db, required this.reportsRepository});
  final AdminStore store;
  final ValueChanged<ParkTicket> onValidate;
  final FirebaseFirestore? db;
  final ParkAdminRepository? reportsRepository;
  @override
  State<ParkCommercePage> createState() => _ParkCommercePageState();
}

class _ParkCommercePageState extends State<ParkCommercePage> {
  int selected = 0;
  static const labels = [
    'Overview', 'Tickets', 'Group Bundles', 'Photo Products', 'Food & Retail', 'Bookings & Orders',
  ];
  static const icons = [
    Icons.dashboard_outlined, Icons.confirmation_number_outlined, Icons.groups_2_outlined,
    Icons.photo_camera_outlined, Icons.storefront_outlined,
    Icons.receipt_long_outlined,
  ];

  Widget _count(String label, String collection, String field, Object value, IconData icon) =>
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.db!.collection(collection).where(field, isEqualTo: value).snapshots(),
      builder: (context, snapshot) => AdminStat(
        label, snapshot.hasData ? '${snapshot.data!.size}' : '—',
        snapshot.hasError ? 'Could not load' : 'Listed in the shop', icon),
    );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AdminHeading('Products & Sales',
        'Tickets, group offers, photos, retail and orders'),
      const SizedBox(height: 18),
      Wrap(spacing: 9, runSpacing: 9, children: [
        for (var i = 0; i < labels.length; i++) ChoiceChip(
          avatar: Icon(icons[i], size: 17),
          label: Text(labels[i]),
          selected: selected == i,
          onSelected: (_) => setState(() => selected = i),
        ),
      ]),
      const SizedBox(height: 24),
      if (selected == 0) ...[
        AdminStats(children: [
          AdminStat('Active passes', '${widget.store.packages.where((p) => p.active).length}',
            'Visitor ticket catalogue', Icons.confirmation_number_outlined),
          AdminStat('Completed ticket orders',
            '${widget.store.orders.where((o) => o.status == 'completed').length}',
            'Recorded bookings', Icons.receipt_long_outlined),
          if (widget.db != null) ...[
            _count('Published bundles', 'ticketBundles', 'status', 'published', Icons.groups_outlined),
            _count('Active photo products', 'photoProducts', 'active', true, Icons.photo_camera_outlined),
            _count('Active food & retail', 'parkMenuItems', 'active', true, Icons.storefront_outlined),
          ],
        ]),
        if (widget.reportsRepository != null) ...[
          const SizedBox(height: 20),
          ParkReportsPage(repository: widget.reportsRepository!, embedded: true, souvenirDb: widget.db),
        ],
      ],
      if (selected == 1) PackageManagement(store: widget.store),
      if (selected == 2) widget.db == null
          ? const AdminCard(child: Text('Admin sign-in required.'))
          : TicketBundleManagementPage(db: widget.db!, store: widget.store),
      if (selected == 3) widget.reportsRepository == null || widget.db == null
          ? const AdminCard(child: Text('Admin sign-in required.'))
          : PhotoProductCataloguePage(db: widget.db!,
              repository: widget.reportsRepository!),
      if (selected == 4) widget.db == null
          ? const AdminCard(child: Text('Admin sign-in required.'))
          : ParkMenuManagementPage(db: widget.db!),
      if (selected == 5) ...[
        // SOUVENIR_ADMIN_V11: paid orders and one-way collection.
        if (widget.db != null) ...[
          SouvenirOrdersAdminPage(
            db: widget.db!, adminUid: widget.store.repository.userId,
            visitors: widget.store.visitors),
          const SizedBox(height: 22),
        ],
        TicketManagement(store: widget.store,
          onValidate: widget.onValidate, embedded: true),
      ],
    ],
  );
}

