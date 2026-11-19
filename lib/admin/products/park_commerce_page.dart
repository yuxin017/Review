import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../admin_store.dart';
import '../admin_widgets.dart';
import '../package_management.dart';
import '../ticket_management.dart';
import '../operations/park_admin_repository.dart';
import '../operations/reports_page.dart';
import '../operations/park_management_page.dart';
import '../../visitor/models/tickets.dart';
import 'park_menu_management_page.dart';
import 'ticket_bundle_management_page.dart';
import 'photo_product_catalogue_page.dart';

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
    'Tickets', 'Group Bundles', 'Photo Products', 'Food & Retail', 'Bookings & Orders',
  ];
  static const icons = [
    Icons.confirmation_number_outlined, Icons.groups_2_outlined,
    Icons.photo_camera_outlined, Icons.storefront_outlined,
    Icons.receipt_long_outlined,
  ];

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
      if (selected == 0) PackageManagement(store: widget.store),
      if (selected == 1) widget.db == null
          ? const AdminCard(child: Text('Admin sign-in required.'))
          : TicketBundleManagementPage(db: widget.db!, store: widget.store),
      if (selected == 2) widget.reportsRepository == null || widget.db == null
          ? const AdminCard(child: Text('Admin sign-in required.'))
          : PhotoProductCataloguePage(db: widget.db!,
              repository: widget.reportsRepository!),
      if (selected == 3) widget.db == null
          ? const AdminCard(child: Text('Admin sign-in required.'))
          : ParkMenuManagementPage(db: widget.db!),
      if (selected == 4) ...[
        if (widget.reportsRepository == null)
          const AdminCard(child: Text('Reporting requires administrator access.'))
        else
          ParkReportsPage(repository: widget.reportsRepository!, embedded: true),
        const SizedBox(height: 18),
        TicketManagement(store: widget.store,
          onValidate: widget.onValidate, embedded: true),
      ],
    ],
  );
}

