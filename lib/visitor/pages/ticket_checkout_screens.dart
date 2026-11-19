import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/tickets.dart';
import '../services/ticket_journey.dart';
import '../services/ticket_receipt.dart';
import '../widgets/ticket_widgets.dart';
import 'tickets_page.dart';

class TicketCartScreen extends StatefulWidget {
  final TicketJourney journey;
  final VoidCallback onShop, onCheckout;
  const TicketCartScreen({
    super.key,
    required this.journey,
    required this.onShop,
    required this.onCheckout,
  });
  @override
  State<TicketCartScreen> createState() => _TicketCartScreenState();
}

class _TicketCartScreenState extends State<TicketCartScreen> {
  String? _swipedLineId;
  double _swipeDistance = 0;

  Future<void> _edit(TicketCartLine line) async {
    final j = widget.journey;
    if (j.busy || j.pending != null) return;
    setState(() => _swipedLineId = null);
    final today = parkToday();
    final last = today.add(const Duration(days: 365));
    var selected = DateTime.tryParse(line.visitDate) ?? today;
    if (selected.isBefore(today) || selected.isAfter(last)) selected = today;
    var adults = line.adults;
    var children = line.children;
    final otherGuests = j.quantity - line.quantity;
    String? validation;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: ticketBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final guests = adults + children;
          final canAdd = guests + otherGuests < 10;
          final subtotal = adults * line.adultPriceMinor +
              children * line.childPriceMinor;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20, 16, 20, 20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(width: 45, height: 4,
                      decoration: BoxDecoration(color: ticketBorder,
                        borderRadius: BorderRadius.circular(8))),
                  ),
                  const SizedBox(height: 18),
                  Row(children: [
                    const Expanded(child: Text('Edit Pass',
                      style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700))),
                    IconButton(tooltip: 'Close editor',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close)),
                  ]),
                  Text(line.packageName,
                    style: const TextStyle(color: ticketMuted, fontSize: 14)),
                  const SizedBox(height: 22),
                  const Text('Visit Date',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('cart-edit-date'),
                    onPressed: () async {
                      final value = await showDatePicker(
                        context: sheetContext,
                        initialDate: selected,
                        firstDate: today,
                        lastDate: last,
                      );
                      if (value != null && sheetContext.mounted) {
                        setSheetState(() { selected = value; validation = null; });
                      }
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(displayParkDate(visitDateString(selected))),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      alignment: Alignment.centerLeft,
                      foregroundColor: ticketInk,
                      side: const BorderSide(color: ticketBorder),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text('Guests',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('Up to 10 guests per order.',
                    style: TextStyle(color: ticketMuted, fontSize: 12)),
                  const SizedBox(height: 12),
                  _cartCounterRow(
                    title: 'Adults', subtitle: 'Age 12+', value: adults,
                    price: line.adultPriceMinor,
                    minus: adults > 0 && guests > 1
                        ? () => setSheetState(() => adults--) : null,
                    plus: canAdd ? () => setSheetState(() => adults++) : null,
                  ),
                  const SizedBox(height: 12),
                  _cartCounterRow(
                    title: 'Children', subtitle: 'Age 3–11', value: children,
                    price: line.childPriceMinor,
                    minus: children > 0 && guests > 1
                        ? () => setSheetState(() => children--) : null,
                    plus: canAdd ? () => setSheetState(() => children++) : null,
                  ),
                  const Divider(height: 28, color: ticketBorder),
                  Row(children: [
                    const Expanded(child: Text('Updated subtotal',
                      style: TextStyle(fontWeight: FontWeight.w600))),
                    Text(ticketDisplayPrice(sheetContext, subtotal),
                      style: const TextStyle(color: ticketRose,
                        fontSize: 20, fontWeight: FontWeight.w700)),
                  ]),
                  if (validation != null) ...[
                    const SizedBox(height: 10),
                    Text(validation!, style: const TextStyle(color: ticketRose)),
                  ],
                  const SizedBox(height: 22),
                  TicketButton('Save Changes', onPressed: () {
                    try {
                      j.updateCartLine(line.id, selected, adults, children);
                      Navigator.pop(sheetContext);
                    } catch (e) {
                      setSheetState(() => validation = bookingError(e));
                    }
                  }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cartCounterRow({
    required String title,
    required String subtitle,
    required int value,
    required int price,
    VoidCallback? minus,
    VoidCallback? plus,
  }) => TicketSurface(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 13),
    child: Row(children: [
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('$subtitle · ${priceLabel(price)}',
            style: const TextStyle(fontSize: 12, color: ticketMuted)),
        ],
      )),
      TicketCounter(label: title.toLowerCase(), value: value,
        minus: minus, plus: plus),
    ]),
  );

  Future<void> _delete(TicketCartLine line) async {
    final j = widget.journey;
    if (j.pending != null || j.busy) return;
    setState(() => _swipedLineId = null);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this pass?'),
        content: Text('Remove ${line.packageName} from your cart?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove')),
        ],
      ),
    );
    if (accepted == true && mounted && j.pending == null) {
      j.remove(line.id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pass removed from your cart.'),
      ));
    }
  }

  Widget _lineCard(TicketCartLine line) {
    final j = widget.journey;
    final enabled = !j.busy && j.pending == null;
    final opened = _swipedLineId == line.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(builder: (context, constraints) => Stack(children: [
          Positioned.fill(child: Align(
            alignment: Alignment.centerRight,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 76, child: Material(
                color: const Color(0xFFECE3EF),
                child: InkWell(
                  key: Key('swipe-edit-${line.id}'),
                  onTap: enabled ? () => _edit(line) : null,
                  child: const Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_outlined, color: Color(0xFF55446F)),
                      SizedBox(height: 4),
                      Text('Edit', style: TextStyle(color: Color(0xFF55446F))),
                    ],
                  )),
                ),
              )),
              SizedBox(width: 76, child: Material(
                color: const Color(0xFFF8E3E1),
                child: InkWell(
                  key: Key('swipe-delete-${line.id}'),
                  onTap: enabled ? () => _delete(line) : null,
                  child: const Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline, color: Color(0xFF9E4545)),
                      SizedBox(height: 4),
                      Text('Delete', style: TextStyle(color: Color(0xFF9E4545))),
                    ],
                  )),
                ),
              )),
            ]),
          )),
          AnimatedSlide(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            offset: Offset(opened ? -(152.0 / constraints.maxWidth) : 0.0, 0.0),
            child: GestureDetector(
              onHorizontalDragStart: enabled
                  ? (_) => _swipeDistance = 0 : null,
              onHorizontalDragUpdate: enabled
                  ? (details) => _swipeDistance += details.delta.dx : null,
              onHorizontalDragEnd: enabled ? (details) {
                if (_swipeDistance < -25) {
                  setState(() => _swipedLineId = line.id);
                } else if (_swipeDistance > 25) {
                  setState(() => _swipedLineId = null);
                }
                _swipeDistance = 0;
              } : null,
              child: TicketSurface(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset(line.imageAsset,
                          width: 76, height: 80, fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 76, height: 80,
                            color: const Color(0xFFF5E9E7),
                            child: const Icon(Icons.confirmation_number_outlined,
                              color: ticketRose),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(line.packageName,
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15,
                              fontWeight: FontWeight.w700)),
                          const SizedBox(height: 5),
                          Text(line.category == 'annual'
                              ? 'Annual admission' : '${line.durationDays}-Day Admission',
                            style: const TextStyle(color: ticketMuted,
                              fontSize: 12)),
                          const SizedBox(height: 7),
                          Text(ticketDisplayPrice(context, line.subtotal),
                            style: const TextStyle(color: ticketRose,
                              fontWeight: FontWeight.w700, fontSize: 18)),
                        ],
                      )),
                      PopupMenuButton<String>(
                        key: Key('cart-actions-${line.id}'),
                        tooltip: 'Pass actions',
                        enabled: enabled,
                        icon: const Icon(Icons.more_vert, color: ticketMuted),
                        onSelected: (action) => action == 'edit'
                            ? _edit(line) : _delete(line),
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'edit',
                            child: Text('Edit pass')),
                          PopupMenuItem(value: 'delete',
                            child: Text('Delete pass')),
                        ],
                      ),
                    ]),
                    const Divider(height: 24, color: ticketBorder),
                    InkWell(
                      key: Key('cart-date-${line.id}'),
                      onTap: enabled ? () => _edit(line) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          const Icon(Icons.calendar_month_outlined,
                            size: 18, color: ticketMutedRose),
                          const SizedBox(width: 8),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Visit date',
                                style: TextStyle(fontSize: 11,
                                  color: ticketMuted)),
                              Text(displayParkDate(line.visitDate),
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          )),
                          if (enabled) const Icon(Icons.edit_outlined,
                            size: 17, color: ticketRose),
                        ]),
                      ),
                    ),
                    InkWell(
                      key: Key('cart-guests-${line.id}'),
                      onTap: enabled ? () => _edit(line) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          const Icon(Icons.people_outline,
                            size: 18, color: ticketMutedRose),
                          const SizedBox(width: 8),
                          Expanded(child: Text(line.guestSummary,
                            style: const TextStyle(fontWeight: FontWeight.w500,
                              fontSize: 13))),
                          if (enabled) const Icon(Icons.edit_outlined,
                            size: 17, color: ticketRose),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.journey;
    return TicketPageBody(
      footer: j.cart.isEmpty ? null : TicketSurface(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${j.quantity} ${j.quantity == 1 ? 'ticket' : 'tickets'} · Total',
                style: const TextStyle(fontSize: 12, color: ticketMuted)),
              const SizedBox(height: 3),
              Text(ticketDisplayPrice(context, j.subtotal),
                key: const Key('cart-total'),
                style: const TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 22, color: ticketRose)),
            ],
          )),
          SizedBox(width: 158, child: TicketButton(
            j.pending == null ? 'Checkout' : 'Payment pending',
            onPressed: j.busy || j.pending != null || j.hasInvalidVisitDate
                ? null : widget.onCheckout,
          )),
        ]),
      ),
      children: [
        Row(children: [
          const Expanded(child: Text('Review your passes',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
          Text('${j.cart.length} items',
            style: const TextStyle(color: ticketMuted, fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        if (j.cart.isNotEmpty) const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Icon(Icons.swipe_left_alt_outlined,
              size: 18, color: ticketMutedRose),
            SizedBox(width: 7),
            Expanded(child: Text('Swipe left to Edit / Delete. You can also tap the pencil.',
              style: TextStyle(fontSize: 12, color: ticketMuted))),
          ]),
        ),
        if (j.cartNotice != null) Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TicketSurface(
            color: const Color(0xFFFFF2E8),
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Icon(Icons.info_outline, color: ticketRose, size: 20),
              const SizedBox(width: 9),
              Expanded(child: Text(j.cartNotice!,
                style: const TextStyle(fontSize: 13))),
            ]),
          ),
        ),
        if (j.pending != null) const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: TicketSurface(
            color: Color(0xFFFFF2E8),
            child: Text('A payment is in progress. Check its status before editing your cart.'),
          ),
        ),
        if (j.cart.isEmpty) ...[
          const SizedBox(height: 48),
          const Center(child: Icon(Icons.shopping_bag_outlined,
            size: 62, color: ticketMutedRose)),
          const SizedBox(height: 14),
          const Center(child: Text('Your cart is empty',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
          const SizedBox(height: 10),
          const Center(child: Text('Explore passes and plan your next adventure.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ticketMuted))),
          const SizedBox(height: 25),
          TicketButton('Browse Passes', onPressed: widget.onShop),
        ] else ...[
          for (final line in j.cart) _lineCard(line),
          TextButton.icon(onPressed: widget.onShop,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Add another pass')),
          const SizedBox(height: 6),
          const TicketSurface(child: Row(children: [
            Icon(Icons.lock_outline, color: ticketMutedRose, size: 19),
            SizedBox(width: 8),
            Expanded(child: Text('QR tickets are issued only after verified payment.',
              style: TextStyle(color: ticketMuted, fontSize: 12))),
          ])),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class TicketGuestsScreen extends StatelessWidget {
  final TicketJourney journey;
  final VoidCallback onContinue;
  const TicketGuestsScreen({
    super.key,
    required this.journey,
    required this.onContinue,
  });
  @override
  Widget build(BuildContext context) {
    final j = journey;
    var adult = 0, child = 0;
    return TicketPageBody(
      footer: TicketButton(
        'Continue to Review',
        onPressed: j.guestsComplete ? onContinue : null,
      ),
      children: [
        const TicketStepper(1),
        const SizedBox(height: 18),
        TicketSurface(
          color: const Color(0xFFF8F1EE),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.calendar_today_outlined, size: 20),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  '${j.quantity} guests  •  ${j.cart.isEmpty ? '' : displayParkDate(j.cart.first.visitDate)}',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < j.guests.length; i++) ...[
          _GuestForm(
            key: ValueKey(j.guests[i].id),
            guest: j.guests[i],
            label: j.guests[i].type == 'adult'
                ? 'Adult ${++adult}'
                : 'Child ${++child}',
            initiallyExpanded: i == 0,
            profile: j.profile,
            locked: j.pending != null,
            onChanged: j.updateGuest,
          ),
          const SizedBox(height: 14),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: TicketMeta(
            Icons.info_outline,
            'Names must match each guest’s identification.',
          ),
        ),
      ],
    );
  }
}

class _GuestForm extends StatefulWidget {
  final TicketGuest guest;
  final String label;
  final BookingProfile profile;
  final bool initiallyExpanded, locked;
  final ValueChanged<TicketGuest> onChanged;
  const _GuestForm({
    super.key,
    required this.guest,
    required this.label,
    required this.profile,
    required this.initiallyExpanded,
    required this.locked,
    required this.onChanged,
  });
  @override
  State<_GuestForm> createState() => _GuestFormState();
}

class _GuestFormState extends State<_GuestForm> {
  late bool expanded = widget.initiallyExpanded;
  late final name = TextEditingController(text: widget.guest.fullName),
      email = TextEditingController(text: widget.guest.email);
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    super.dispose();
  }

  void _update() => widget.onChanged(
    widget.guest.copyWith(
      fullName: name.text,
      email: email.text,
      assignedToMe: false,
    ),
  );
  @override
  Widget build(BuildContext context) => TicketSurface(
    padding: const EdgeInsets.all(15),
    color: const Color(0xFFFFFDFC),
    child: Column(
      children: [
        InkWell(
          onTap: () => setState(() => expanded = !expanded),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFF6ECEA),
                child: Icon(Icons.person_outline, color: ticketRose, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (!expanded)
                      Text(
                        widget.guest.complete
                            ? widget.guest.fullName
                            : 'Guest details required',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.guest.complete
                              ? ticketMuted
                              : ticketRose,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: ticketMuted,
              ),
            ],
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 17),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Full Name', style: TextStyle(color: ticketMuted)),
          ),
          const SizedBox(height: 7),
          TextFormField(
            key: Key('name-${widget.guest.id}'),
            controller: name,
            enabled: !widget.locked,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            textCapitalization: TextCapitalization.words,
            maxLength: 100,
            decoration: const InputDecoration(
              counterText: '',
              hintText: 'Enter guest’s full name',
            ),
            validator: (v) => (v ?? '').trim().length < 2
                ? 'Enter the guest’s full name'
                : null,
            onChanged: (_) => _update(),
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Email Address', style: TextStyle(color: ticketMuted)),
          ),
          const SizedBox(height: 7),
          TextFormField(
            key: Key('email-${widget.guest.id}'),
            controller: email,
            enabled: !widget.locked,
            keyboardType: TextInputType.emailAddress,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            maxLength: 254,
            decoration: const InputDecoration(
              counterText: '',
              hintText: 'Enter guest’s email',
            ),
            validator: (v) =>
                RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim())
                ? null
                : 'Enter a valid email address',
            onChanged: (_) => _update(),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Checkbox(
                value: widget.guest.assignedToMe,
                onChanged: widget.locked || widget.profile.email.isEmpty
                    ? null
                    : (value) {
                        if (value == true) {
                          name.text = widget.profile.fullName;
                          email.text = widget.profile.email;
                          widget.onChanged(
                            widget.guest.copyWith(
                              fullName: name.text,
                              email: email.text,
                              assignedToMe: true,
                            ),
                          );
                        } else {
                          widget.onChanged(
                            widget.guest.copyWith(assignedToMe: false),
                          );
                        }
                      },
              ),
              const Expanded(
                child: Text(
                  'Assign this ticket to me',
                  style: TextStyle(color: ticketMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class TicketReviewScreen extends StatelessWidget {
  final TicketJourney journey;
  final VoidCallback onContinue;
  const TicketReviewScreen({
    super.key,
    required this.journey,
    required this.onContinue,
  });
  @override
  Widget build(BuildContext context) {
    final j = journey;
    return TicketPageBody(
      footer: TicketButton(
        'Proceed to Payment',
        onPressed: j.guestsComplete && j.termsAccepted ? onContinue : null,
      ),
      children: [
        const TicketStepper(2),
        const SizedBox(height: 14),
        for (final line in j.cart) ...[
          TicketLineSummary(line),
          const SizedBox(height: 14),
        ],
        const Text(
          'Order Details',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        for (final line in j.cart)
          for (final type in ['adult', 'child'])
            if ((type == 'adult' ? line.adults : line.children) > 0) ...[
              TicketSurface(
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFF8F1EF),
                      child: Icon(Icons.person_outline, color: ticketRose),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type == 'adult'
                                ? 'Adult Day Pass'
                                : 'Child Day Pass',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            type == 'adult' ? 'Age 12+' : 'Age 3–11',
                            style: const TextStyle(
                              color: ticketMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${priceLabel(type == 'adult' ? line.adultPriceMinor : line.childPriceMinor)} × ${type == 'adult' ? line.adults : line.children}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      priceLabel(
                        (type == 'adult'
                            ? line.adults * line.adultPriceMinor
                            : line.children * line.childPriceMinor),
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
        TicketSurface(
          child: Column(
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: ticketRose,
                    child: Icon(Icons.star_outline, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Use Loyalty Points',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${j.profile.points} points available',
                          style: const TextStyle(
                            color: ticketMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: j.pointsUsed > 0,
                    onChanged: j.maxPoints < 100 || j.pending != null
                        ? null
                        : (value) => j.setPoints(value ? j.maxPoints : 0),
                  ),
                ],
              ),
              if (j.pointsUsed > 0) ...[
                const SizedBox(height: 12),
                TicketSurface(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Expanded(child: Text('${j.pointsUsed} points')),
                      TicketCounter(
                        label: 'loyalty points',
                        value: j.pointsUsed ~/ 100,
                        minus: () => j.setPoints(j.pointsUsed - 100),
                        plus: j.pointsUsed < j.maxPoints
                            ? () => j.setPoints(j.pointsUsed + 100)
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'You save ${priceLabel(j.pointsUsed)}',
                    style: const TextStyle(
                      color: ticketRose,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        TicketPromotionField(journey: j),
        const SizedBox(height: 14),
        TicketSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Order Summary',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              _amount('Subtotal', j.subtotal),
              if (j.discountMinor > 0) ...[
                const SizedBox(height: 12),
                _amount('Promotion discount', -j.discountMinor),
              ],
              const SizedBox(height: 12),
              _amount('Points discount', -j.pointsUsed),
              const Divider(height: 24, color: ticketBorder),
              _amount('Total', j.total, bold: true),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Checkbox(
              key: const Key('ticket-terms'),
              value: j.termsAccepted,
              onChanged: j.pending != null
                  ? null
                  : (v) => j.acceptTerms(v ?? false),
            ),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('I agree to the ', style: TextStyle(fontSize: 13)),
                  InkWell(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Ticket Terms & Conditions'),
                        content: const Text(
                          'Tickets are non-refundable and valid for their selected admission dates. Adult tickets are for ages 12 and above; child tickets are for ages 3–11. Guest names must match identification. Each QR code admits one guest and can be used only once. Keep ticket codes private. Multi-day passes cover consecutive days from the selected start date.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text(
                      'Ticket Terms & Conditions.',
                      style: TextStyle(color: ticketRose, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _amount(String label, int amount, {bool bold = false}) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontSize: bold ? 17 : 14,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
      Text(
        '${amount < 0 ? '− ' : ''}${priceLabel(amount.abs())}',
        style: TextStyle(
          fontSize: bold ? 23 : 14,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          color: bold || amount < 0 ? ticketRose : ticketInk,
        ),
      ),
    ],
  );
}

class TicketPromotionField extends StatefulWidget {
  final TicketJourney journey;
  const TicketPromotionField({super.key, required this.journey});
  @override
  State<TicketPromotionField> createState() => _TicketPromotionFieldState();
}

class _TicketPromotionFieldState extends State<TicketPromotionField> {
  late final code = TextEditingController(text: widget.journey.promoCode);
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.journey;
    return TicketSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Promotion Code',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('ticket-promotion'),
                  controller: code,
                  enabled: !j.busy && j.pending == null,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 32,
                  decoration: const InputDecoration(
                    hintText: 'Enter code',
                    counterText: '',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: j.busy || j.pending != null
                    ? null
                    : () => j.applyPromotion(code.text),
                child: const Text('Apply'),
              ),
            ],
          ),
          if (j.promoCode.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: Colors.green,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${j.promoCode} • Save ${money(j.discountMinor)}',
                    style: const TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove promotion',
                  onPressed: j.busy || j.pending != null
                      ? null
                      : () {
                          code.clear();
                          j.applyPromotion('');
                        },
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class TicketPaymentScreen extends StatelessWidget {
  final TicketJourney journey;
  final Future<void> Function(String method, {String cardLast4}) onPay;
  const TicketPaymentScreen({
    super.key,
    required this.journey,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final j = journey;
    return TicketPageBody(
      footer: TicketButton(
        j.busy ? 'Checking payment…' :
          j.pending != null ? 'Continue to Stripe Checkout' :
          'Pay securely ${j.paymentLabel}',
        onPressed: j.busy ? null : () => onPay('card'),
      ),
      children: [
        const TicketStepper(3),
        const SizedBox(height: 24),
        const Text('Secure Payment',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 18),
        TicketSurface(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Total to Pay', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 8),
            Text(j.paymentLabel,
              style: const TextStyle(fontSize: 28, color: ticketRose,
                fontWeight: FontWeight.w700)),
            const SizedBox(height: 15),
            const TicketMeta(Icons.lock_outline,
              'You will pay on the secure Stripe Checkout page. '
              'Available payment methods depend on the Stripe account. '
              'Card information is never collected by this app.'),
          ],
        )),
        const SizedBox(height: 18),
        if (j.pending != null) ...[
          TicketSurface(child: const Text(
            'Already returned from Stripe? Verify your payment before retrying. '
            'Tickets are issued only after payment is confirmed.')),
          const SizedBox(height: 12),
          TicketButton('Check Payment Status',
            onPressed: j.busy ? null : () async {
              final paid = await j.verifyHostedPayment();
              if (paid && context.mounted) {
                context.findAncestorStateOfType<TicketsPageState>()
                    ?.showSection('success');
              }
            }),
          const SizedBox(height: 10),
        ],
        if (j.error?.contains('Choose a valid visit date') == true ||
            j.error == 'This payment is not linked to your account.') ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: j.busy ? null : () async {
              if (await j.recoverRejectedVisitDate() && context.mounted) {
                context.findAncestorStateOfType<TicketsPageState>()
                    ?.showSection('cart');
              }
            },
            icon: const Icon(Icons.edit_calendar_outlined),
            label: const Text('Change Visit Date'),
          ),
        ],
      ],
    );
  }
}

class TicketSuccessScreen extends StatelessWidget {
  final TicketJourney journey;
  final VoidCallback onDigital, onBack;
  const TicketSuccessScreen({
    super.key,
    required this.journey,
    required this.onDigital,
    required this.onBack,
  });
  @override
  Widget build(BuildContext context) {
    final request = journey.completed;
    final order = journey.orders
        .where((o) => o.id == request?.requestId)
        .firstOrNull;
    return TicketPageBody(
      children: [
        Image.asset(
          'assets/images/ticketing/success.png',
          height: 205,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 5),
        const Text(
          'Your adventure is confirmed!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          'Payment of ${request?.paymentLabel ?? order?.paymentLabel ?? priceLabel(0)} was successful.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: ticketMuted),
        ),
        const SizedBox(height: 22),
        if (request != null)
          for (final line in request.lines) ...[
            TicketLineSummary(line),
            const SizedBox(height: 8),
          ],
        TicketSurface(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Booking ID: ${order?.reference ?? (request == null ? '' : bookingReference(request.requestId, request.visitDate))}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const TicketBadge('Confirmed', green: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const TicketSurface(
          color: Color(0xFFFBF2EF),
          child: Row(
            children: [
              Icon(Icons.qr_code, size: 37, color: ticketRose),
              SizedBox(width: 14),
              Icon(Icons.contactless_outlined, size: 32, color: ticketRose),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Your digital ticket is ready. Use the QR code at the park entrance.',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 17),
        TicketButton(
          'View Digital Tickets',
          icon: Icons.confirmation_number_outlined,
          onPressed: onDigital,
        ),
        const SizedBox(height: 12),
        TicketButton(
          'Download Receipt',
          icon: Icons.download_outlined,
          outlined: true,
          onPressed: order == null
              ? null
              : () => downloadTicketReceipt(context, order),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: onBack,
          child: const Text(
            'Back to Tickets',
            style: TextStyle(color: ticketRose, fontSize: 16),
          ),
        ),
      ],
    );
  }
}
