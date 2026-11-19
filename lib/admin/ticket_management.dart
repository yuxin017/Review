import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../visitor/models/tickets.dart';
import '../visitor/services/ticket_receipt.dart';
import 'admin_models.dart';
import 'admin_store.dart';
import 'admin_widgets.dart';

class TicketManagement extends StatefulWidget {
  final AdminStore store;
  final ValueChanged<ParkTicket> onValidate;
  final bool embedded;
  const TicketManagement({
    super.key,
    required this.store,
    required this.onValidate,
    this.embedded = false,
  });
  @override
  State<TicketManagement> createState() => _TicketManagementState();
}

class _TicketManagementState extends State<TicketManagement> {
  String query = '', tab = 'Bookings', status = 'all';
  int bookingSort = 2, ticketSort = 3;
  bool bookingAsc = false, ticketAsc = false;
  void _sortBookings(int index, bool asc) => setState(() {
    bookingSort = index; bookingAsc = asc;
  });
  void _sortTickets(int index, bool asc) => setState(() {
    ticketSort = index; ticketAsc = asc;
  });

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final text = query.trim().toLowerCase();
    final orders = s.orders
        .where(
          (o) => '${o.reference} ${o.packageName} ${o.id}'
              .toLowerCase()
              .contains(text),
        )
        .toList();
    final tickets = s.tickets
        .where(
          (t) =>
              (status == 'all' ||
                  (status == 'valid'
                      ? t.filter == 'Upcoming'
                      : t.filter.toLowerCase() == status)) &&
              '${t.reference} ${t.guestName} ${t.guestEmail} ${t.id} ${t.packageName}'
                  .toLowerCase()
                  .contains(text),
        )
        .toList();
    // Sorting is display-only: source orders and tickets are not mutated.
    orders.sort((a, b) {
      final result = switch (bookingSort) {
        0 => a.reference.compareTo(b.reference),
        1 => a.packageName.compareTo(b.packageName),
        2 => a.visitDate.compareTo(b.visitDate),
        3 => a.quantity.compareTo(b.quantity),
        4 => a.totalMinor.compareTo(b.totalMinor),
        _ => a.reference.compareTo(b.reference),
      };
      return bookingAsc ? result : -result;
    });
    tickets.sort((a, b) {
      final result = switch (ticketSort) {
        0 => a.reference.compareTo(b.reference),
        1 => a.packageName.compareTo(b.packageName),
        2 => a.guestEmail.compareTo(b.guestEmail),
        3 => a.visitDate.compareTo(b.visitDate),
        4 => a.filter.compareTo(b.filter),
        _ => a.reference.compareTo(b.reference),
      };
      return ticketAsc ? result : -result;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.embedded) ...[
          const AdminHeading('Tickets & Orders',
              'Manage booking records and digital park tickets'),
          const SizedBox(height: 26),
        ],
        if (!widget.embedded) AdminStats(
          children: [
            AdminStat(
              'Total Bookings',
              '${s.orders.length}',
              'Confirmed park bookings',
              Icons.receipt_long_outlined,
            ),
            AdminStat(
              'Tickets Issued',
              '${s.tickets.length}',
              'All issued park tickets',
              Icons.confirmation_number_outlined,
            ),
            AdminStat(
              'Valid Tickets',
              '${s.tickets.where((t) => t.filter == 'Upcoming').length}',
              'Available park admissions',
              Icons.verified_outlined,
              color: const Color(0xFF278D52),
            ),
            AdminStat(
              'Booking Amount',
              money(s.orders.fold(0, (amount, o) => amount + o.totalMinor)),
              'Total confirmed booking value',
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
              for (final value in ['Bookings', 'Digital Tickets'])
                ChoiceChip(
                  label: Text(value),
                  selected: tab == value,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => tab = value),
                ),
              SizedBox(
                width: 320,
                child: TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: 'Search booking, ticket or guest',
                  ),
                ),
              ),
              if (tab == 'Digital Tickets')
                AdminSelect(
                  value: status,
                  options: const {
                    'all': 'All Status',
                    'valid': 'Valid',
                    'used': 'Used',
                    'expired': 'Expired',
                  },
                  onChanged: (v) => setState(() => status = v),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AdminCard(
          padding: EdgeInsets.zero,
          child: tab == 'Bookings'
              ? (orders.isEmpty
                    ? const AdminEmpty(
                        'No matching bookings',
                        'Confirmed visitor bookings will appear here.',
                      )
                    : AdminTable(
                        sortColumnIndex: bookingSort,
                        sortAscending: bookingAsc,
                        columns: [
                          DataColumn(label: const Text('Booking ID'), onSort: _sortBookings),
                          DataColumn(label: const Text('Pass'), onSort: _sortBookings),
                          DataColumn(label: const Text('Visit Date'), onSort: _sortBookings),
                          DataColumn(label: const Text('Guests'), numeric: true, onSort: _sortBookings),
                          DataColumn(label: const Text('Amount'), numeric: true, onSort: _sortBookings),
                          const DataColumn(label: Text('Status')),
                          const DataColumn(label: Text('Actions')),
                        ],
                        rows: [
                          for (final o in orders)
                            DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    o.reference,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 190,
                                    child: Text(o.packageName),
                                  ),
                                ),
                                DataCell(Text(displayParkDate(o.visitDate))),
                                DataCell(Text('${o.quantity}')),
                                DataCell(
                                  Text(
                                    money(o.totalMinor),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const DataCell(AdminBadge('Confirmed')),
                                DataCell(
                                  AdminButton(
                                    'View Receipt',
                                    outlined: true,
                                    onPressed: () =>
                                        downloadTicketReceipt(context, o),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ))
              : tickets.isEmpty
              ? const AdminEmpty(
                  'No matching tickets',
                  'Try another status or search for a ticket ID.',
                )
              : AdminTable(
                  sortColumnIndex: ticketSort,
                  sortAscending: ticketAsc,
                  columns: [
                    DataColumn(label: const Text('Ticket ID'), onSort: _sortTickets),
                    DataColumn(label: const Text('Pass / Guest'), onSort: _sortTickets),
                    DataColumn(label: const Text('Email'), onSort: _sortTickets),
                    DataColumn(label: const Text('Visit Date'), onSort: _sortTickets),
                    DataColumn(label: const Text('Status'), onSort: _sortTickets),
                    const DataColumn(label: Text('Actions')),
                  ],
                  rows: [
                    for (final t in tickets)
                      DataRow(
                        cells: [
                          DataCell(
                            Text(
                              t.reference,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 190,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.packageName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    t.guestName.isEmpty
                                        ? titleCase(t.ticketType)
                                        : t.guestName,
                                    style: const TextStyle(
                                      color: adminMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              t.guestEmail,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          DataCell(Text(displayParkDate(t.visitDate))),
                          DataCell(
                            AdminBadge(
                              t.filter == 'Upcoming' ? 'Valid' : t.filter,
                            ),
                          ),
                          DataCell(
                            AdminButton(
                              'View Ticket',
                              outlined: true,
                              onPressed: () => showAdminTicket(
                                context,
                                t,
                                widget.onValidate,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

Future<void> showAdminTicket(
  BuildContext context,
  ParkTicket ticket,
  ValueChanged<ParkTicket> onValidate,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    backgroundColor: const Color(0xFFF4EAE9),
    elevation: 20,
    shadowColor: const Color(0x550F151C),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    title: const Row(children: [
      Icon(Icons.confirmation_number_outlined, color: adminRose),
      SizedBox(width: 12),
      Text('Ticket Details', style: TextStyle(fontWeight: FontWeight.w700)),
    ]),
    content: SizedBox(
      width: 390,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ticket.packageName,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              'Guest: ${ticket.guestName.isEmpty ? 'Not assigned' : ticket.guestName}',
            ),
            const SizedBox(height: 7),
            Text(
              'Visit: ${displayParkDate(ticket.visitDate)}${ticket.endDate != ticket.visitDate ? ' – ${displayParkDate(ticket.endDate)}' : ''}',
            ),
            const SizedBox(height: 8),
            SelectableText(
              ticket.reference,
              style: const TextStyle(color: adminMuted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Center(
              child: QrImageView(
                data: ticket.qrData,
                size: 190,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: AdminBadge(
                ticket.filter == 'Upcoming' ? 'Valid' : ticket.filter,
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
      AdminButton(
        'Validate Ticket',
        onPressed: () {
          Navigator.pop(context);
          onValidate(ticket);
        },
      ),
    ],
  ),
);
