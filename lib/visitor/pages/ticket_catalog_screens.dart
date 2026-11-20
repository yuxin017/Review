import '../visitor_main_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../photos/photo_gallery_pages.dart';
import '../../photos/photo_repository.dart';
import 'souvenir_shop_page.dart';
import 'package:flutter/material.dart';
import '../models/tickets.dart';
import '../services/ticket_journey.dart';
import '../widgets/ticket_widgets.dart';
import 'tickets_page.dart';

class TicketHub extends StatefulWidget {
  final TicketJourney journey;
  final void Function([String category]) onBuy;
  final VoidCallback onTickets, onScan, onHistory;
  final ValueChanged<TicketPackage> onSelect;
  final bool showLiveShop;
  const TicketHub({
    super.key,
    required this.journey,
    required this.onBuy,
    required this.onTickets,
    required this.onScan,
    required this.onHistory,
    required this.onSelect,
    this.showLiveShop = false,
  });
  @override
  State<TicketHub> createState() => _TicketHubState();
}

class _TicketHubState extends State<TicketHub> {
  String category = 'Tickets';
  String query = '';
  static const departments = {
    'Tickets': Icons.confirmation_number_outlined,
    'Bundles': Icons.groups_outlined,
    'Food': Icons.restaurant_outlined,
    'Souvenirs': Icons.shopping_bag_outlined,
    'Photos': Icons.photo_camera_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final journey = widget.journey;
    final onBuy = widget.onBuy;
    final onTickets = widget.onTickets;
    final onSelect = widget.onSelect;
    final day = journey.packages.where((p) => p.category == 'day').firstOrNull;
    final annual = journey.packages
        .where((p) => p.category == 'annual')
        .firstOrNull;
    return TicketPageBody(
      padding: const EdgeInsets.fromLTRB(17, 0, 17, 16),
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF632932),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: TextField(
                key: ValueKey(category),
                onChanged: (value) => setState(() => query = value.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search ${category.toLowerCase()}',
                  prefixIcon: const Icon(Icons.search),
                  filled: true, fillColor: Colors.white,
                ),
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
              child: InkWell(
                onTap: () => onBuy(),
                child: Image.asset('assets/images/ticketing/hero.png',
                  height: 138, fit: BoxFit.cover, alignment: Alignment.center),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (widget.showLiveShop)
          Row(children: [
            for (final entry in departments.entries)
              Expanded(child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() { category = entry.key; query = ''; }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(children: [
                    CircleAvatar(
                      backgroundColor: category == entry.key ? ticketRose : const Color(0xFFF3E4DF),
                      foregroundColor: category == entry.key ? Colors.white : ticketRose,
                      child: Icon(entry.value, size: 20),
                    ),
                    const SizedBox(height: 6),
                    Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                ),
              )),
          ]),
        const SizedBox(height: 14),
        Row(children: [
          _shortcut(Icons.qr_code_scanner, 'Scan Ticket', widget.onScan),
          _shortcut(Icons.account_balance_wallet_outlined, 'My Tickets', onTickets),
          _shortcut(Icons.shopping_bag_outlined, 'My Orders', widget.onHistory),
        ]),
        const SizedBox(height: 22),
        if (category == 'Tickets') ...[
        _section('Day & Annual Passes', () => onBuy()),
        const SizedBox(height: 12),
        if (query.isNotEmpty)
          ...journey.packages.where((item) => item.name.toLowerCase().contains(query))
              .map((item) => Card(child: ListTile(
                title: Text(item.name),
                trailing: Text(ticketDisplayPrice(context, item.priceMinor)),
                onTap: () => onSelect(item),
              )))
        else if (journey.loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: CircularProgressIndicator(),
            ),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _passCard(
                  context,
                  'Theme Park Day Pass',
                  ticketCastleAsset,
                  day?.priceMinor,
                  () => day == null ? onBuy() : onSelect(day),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _passCard(
                  context,
                  'Annual Pass',
                  ticketAnnualAsset,
                  annual?.priceMinor,
                  () => annual == null ? onBuy('annual') : onSelect(annual),
                  annual: true,
                ),
              ),
            ],
          ),
        const SizedBox(height: 18),
        ] else ...[
          Text(category, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _LiveShopCatalogue(category: category, term: query),
          if (category == 'Photos') ...[
            const SizedBox(height: 8),
            const Text('Check available formats and final prices in My Photos.'),
            const SizedBox(height: 12),
            TicketButton('Find my photos', onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: 'photos-hub'),
                builder: (_) => PhotoHubPage(repository: FirebasePhotoRepository()),
              ),
            )),
          ],
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _section(String text, VoidCallback tap) => Row(
    children: [
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      InkWell(
        onTap: tap,
        child: const Row(
          children: [
            Text(
              'See All',
              style: TextStyle(
                color: ticketRose,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(Icons.chevron_right, color: ticketRose, size: 20),
          ],
        ),
      ),
    ],
  );
  Widget _shortcut(IconData icon, String label, VoidCallback tap) => Expanded(
    child: InkWell(
      onTap: tap,
      child: Column(
        children: [
          TicketSurface(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
            child: Icon(icon, color: ticketRose, size: 30),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    ),
  );
  Widget _passCard(
    BuildContext context,
    String name,
    String image,
    int? price,
    VoidCallback tap, {
    bool annual = false,
  }) => TicketSurface(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
          child: Image.asset(
            image,
            height: 126,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'From',
                style: TextStyle(fontSize: 11, color: ticketMuted),
              ),
              Text(
                price == null
                    ? 'View passes'
                    : '${ticketDisplayPrice(context, price)}${annual ? ' / year' : ''}',
                style: const TextStyle(
                  color: ticketRose,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              SizedBox(
                height: 31,
                child: TicketButton('Buy Now', onPressed: tap),
              ),
            ],
          ),
        ),
      ],
    ),
  );

}

class _LiveShopCatalogue extends StatelessWidget {
  const _LiveShopCatalogue({required this.category, required this.term});
  final String category, term;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    if (category != 'Food' && category != 'Souvenirs') {
      final bundles = category == 'Bundles';
      return _items(context, bundles
          ? db.collection('ticketBundles').where('status', isEqualTo: 'published')
          : db.collection('photoProducts').where('active', isEqualTo: true));
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('attractions').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Shop locations could not be loaded.');
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final venues = {
          for (final doc in snapshot.data!.docs)
            if (doc.data()['deletedAt'] == null && _matchesVenue(doc.data()))
              doc.id: (doc.data()['name'] ?? 'Park dining').toString(),
        };
        return _items(context,
          db.collection('parkMenuItems').where('active', isEqualTo: true),
          venues: venues);
      },
    );
  }

  bool _matchesVenue(Map<String, dynamic> data) {
    final food = category == 'Food';
    final kind = (data['kind'] ?? '').toString().toLowerCase();
    if (kind.isNotEmpty) return kind == (food ? 'dining' : 'shops');
    final label = (data['category'] ?? '').toString().toLowerCase();
    return (food
        ? ['dining', 'food', 'cafe', 'café', 'restaurant']
        : ['shop', 'retail', 'souvenir', 'gift']).any(label.contains);
  }

  Widget _image(Map<String, dynamic> item, {double height = 126}) {
    final url = item['imageUrl'];
    final fallback = ColoredBox(
      color: const Color(0xFFF3E4DF),
      child: Center(child: Icon(_TicketHubState.departments[category], color: ticketRose, size: 36)),
    );
    return SizedBox(height: height, width: double.infinity, child:
      url is String && url.isNotEmpty
        ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)
        : fallback,
    );
  }

  void _detail(BuildContext context, Map<String, dynamic> item, String? venue) {
    final name = (item['name'] ?? category).toString();
    final price = ticketDisplayPrice(context, (item['priceMinor'] as num?)?.toInt() ?? 0);
    showModalBottomSheet<void>(
      context: context, useSafeArea: true, isScrollControlled: true,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: _image(item, height: 175)),
          const SizedBox(height: 14),
          Text(name, style: Theme.of(sheet).textTheme.titleLarge),
          Text(price, style: const TextStyle(color: ticketRose, fontSize: 21, fontWeight: FontWeight.w700)),
          if (item['description'] case final String description)
            if (description.isNotEmpty) Padding(
              padding: const EdgeInsets.symmetric(vertical: 8), child: Text(description)),
          if (category == 'Bundles') ...[
            Text("${item['adults']} adults · ${item['children']} children"),
            const SizedBox(height: 8),
            const Text('Ask at park admissions to purchase this bundle.'),
          ],
          if (venue != null) Text('Available at $venue'),
          const SizedBox(height: 16),
          if (category == 'Souvenirs')
            TicketButton('Open in souvenir shop', onPressed: () {
              Navigator.pop(sheet);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => SouvenirShopPage(
                initialSearch: name, initialStoreId: item['storeId'] as String?,
              )));
            })
          else if (category == 'Food' || category == 'Bundles')
            TicketButton('Open Park Map', onPressed: () {
              Navigator.pop(sheet);
              VisitorMainPage.goTo(context, 2);
            })
          else if (category == 'Photos')
            TicketButton('Find my photos', onPressed: () {
              Navigator.pop(sheet);
              Navigator.of(context).push(MaterialPageRoute(
                settings: const RouteSettings(name: 'photos-hub'),
                builder: (_) => PhotoHubPage(repository: FirebasePhotoRepository()),
              ));
            }),
        ]),
      ),
    );
  }

  Widget _items(BuildContext context, Query<Map<String, dynamic>> query,
      {Map<String, String>? venues}) =>
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text('$category catalogue could not be loaded.');
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final items = snapshot.data!.docs.map((doc) => doc.data())
            .where((item) => venues == null || venues.containsKey(item['storeId']))
            .where((item) => (item['name'] ?? '').toString().toLowerCase().contains(term))
            .toList()
          ..sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
        if (items.isEmpty) return TicketSurface(
          child: Text(term.isNotEmpty ? 'No matching products.' :
            category == 'Bundles' ? 'No group bundles are published yet.' : 'No ${category.toLowerCase()} available.'),
        );
        return LayoutBuilder(builder: (context, bounds) {
          final columns = bounds.maxWidth >= 680 ? 3 : 2;
          final cardWidth = (bounds.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final item in items)
              SizedBox(width: cardWidth, child: TicketSurface(
                padding: EdgeInsets.zero,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                    child: InkWell(onTap: () => _detail(context, item, venues?[item['storeId']]), child: _image(item))),
                  Padding(padding: const EdgeInsets.all(10), child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text((item['name'] ?? category).toString(), maxLines: 2,
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 5),
                      Text(ticketDisplayPrice(context, (item['priceMinor'] as num?)?.toInt() ?? 0),
                        style: const TextStyle(color: ticketRose, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      TicketButton('View Product', onPressed: () => _detail(context, item, venues?[item['storeId']])),
                    ],
                  )),
                ]),
              )),
          ]);
        });
      },
    );
}

class PassCatalog extends StatelessWidget {
  final List<TicketPackage> packages;
  final String category;
  final bool loading;
  final ValueChanged<String> onCategory;
  final ValueChanged<TicketPackage> onSelect;
  const PassCatalog({
    super.key,
    required this.packages,
    required this.category,
    required this.onCategory,
    required this.onSelect,
    required this.loading,
  });
  @override
  Widget build(BuildContext context) {
    final filtered = packages.where((p) => p.category == category).toList();
    return TicketPageBody(
      children: [
        TicketSurface(
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              for (final item in [
                ('day', 'Day Pass'),
                ('annual', 'Annual Pass'),
                ('addon', 'Add-ons'),
              ])
                Expanded(
                  child: InkWell(
                    onTap: () => onCategory(item.$1),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: category == item.$1
                            ? ticketRose
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.$2,
                        style: TextStyle(
                          color: category == item.$1 ? Colors.white : ticketInk,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          category == 'day'
              ? 'Choose Your Day Pass'
              : category == 'annual'
              ? 'Enjoy a Year of Magic'
              : 'Make Your Visit Extra Special',
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (filtered.isEmpty)
          TicketSurface(
            child: Text(
              category == 'addon'
                  ? 'There are no add-ons available for your visit right now.'
                  : 'Passes are currently unavailable. Please check again shortly.',
            ),
          ),
        for (final pack in filtered) ...[
          TicketSurface(
            padding: const EdgeInsets.all(5),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset(
                    pack.imageAsset,
                    width: 98,
                    height: 116,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 10, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pack.shortName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          pack.description,
                          style: const TextStyle(
                            color: ticketMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'From',
                                    style: TextStyle(
                                      color: ticketMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    ticketDisplayPrice(
                                      context,
                                      pack.priceMinor,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 21,
                                      color: ticketRose,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 74,
                              height: 36,
                              child: TicketButton(
                                'Select',
                                key: Key('select-${pack.id}'),
                                onPressed: () => onSelect(pack),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        const TicketSurface(
          color: Color(0xFFF8EAEC),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Important Information',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              TicketMeta(Icons.paid_outlined, 'Tickets are non-refundable.'),
              SizedBox(height: 8),
              TicketMeta(
                Icons.calendar_today_outlined,
                'Valid only on selected admission dates.',
              ),
              SizedBox(height: 8),
              TicketMeta(Icons.child_care, 'Child ticket for ages 3–11.'),
              SizedBox(height: 8),
              TicketMeta(Icons.qr_code, 'Scan QR code at park entrance.'),
            ],
          ),
        ),
      ],
    );
  }
}

class PassDetail extends StatefulWidget {
  final TicketPackage package;
  final int remaining;
  final ValueChanged<TicketCartLine> onAdd;
  const PassDetail({
    super.key,
    required this.package,
    required this.remaining,
    required this.onAdd,
  });
  @override
  State<PassDetail> createState() => _PassDetailState();
}

class _PassDetailState extends State<PassDetail> {
  int adults = 1, children = 0;
  DateTime date = parkToday();
  @override
  Widget build(BuildContext context) {
    final pack = widget.package;
    final total = adults * pack.priceMinor + children * pack.childPrice;
    return TicketPageBody(
      footer: TicketSurface(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(color: ticketMuted, fontSize: 12),
                  ),
                  Text(
                    ticketDisplayPrice(context, total),
                    key: const Key('pass-total'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TicketButton(
                'Add to Cart',
                onPressed:
                    adults + children < 1 ||
                        adults + children > widget.remaining
                    ? null
                    : () => widget.onAdd(
                        TicketCartLine(
                          id: TicketJourney.newId(),
                          packageId: pack.id,
                          packageName: pack.name,
                          visitDate: visitDateString(date),
                          adults: adults,
                          children: children,
                          adultPriceMinor: pack.priceMinor,
                          childPriceMinor: pack.childPrice,
                          durationDays: pack.durationDays,
                          imageAsset: pack.imageAsset,
                          category: pack.category,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Image.asset(
            pack.imageAsset,
            height: 235,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          pack.name,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          pack.category == 'annual'
              ? 'A whole year of unforgettable rides, shows and attractions.'
              : 'Access to all rides, shows and attractions for ${pack.durationDays == 1 ? '1 day' : '${pack.durationDays} consecutive days'}.',
          style: const TextStyle(fontSize: 16, color: ticketMuted, height: 1.5),
        ),
        const SizedBox(height: 10),
        Text(
          ticketDisplayPrice(context, pack.priceMinor),
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: ticketRose,
          ),
        ),
        const Divider(height: 28, color: ticketBorder),
        const Text(
          'Select Date',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        InkWell(
          key: const Key('select-visit-date'),
          onTap: () async {
            final value = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: parkToday(),
              lastDate: parkToday().add(const Duration(days: 365)),
            );
            if (value != null && mounted) setState(() => date = value);
          },
          child: TicketSurface(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 22),
                const SizedBox(width: 12),
                Expanded(child: Text(displayParkDate(visitDateString(date)))),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Select Quantity',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _quantity(
          'Adult (12+)',
          'adults',
          adults,
          pack.priceMinor,
          () => setState(() => adults--),
          () => setState(() => adults++),
        ),
        const SizedBox(height: 5),
        _quantity(
          'Child (3–11)',
          'children',
          children,
          pack.childPrice,
          () => setState(() => children--),
          () => setState(() => children++),
        ),
        const SizedBox(height: 14),
        const Text(
          'You’ll Get',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        for (final benefit in pack.benefits)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              children: [
                const Icon(Icons.check, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    benefit,
                    style: const TextStyle(fontSize: 13, color: ticketMuted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _quantity(
    String title,
    String label,
    int value,
    int price,
    VoidCallback minus,
    VoidCallback plus,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F0EE),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              Text(
                ticketDisplayPrice(context, price),
                style: const TextStyle(color: ticketMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        TicketCounter(
          label: label,
          value: value,
          minus: value > 0 ? minus : null,
          plus: adults + children < widget.remaining ? plus : null,
        ),
      ],
    ),
  );
}
