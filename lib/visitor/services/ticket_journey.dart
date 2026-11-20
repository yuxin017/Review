import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/tickets.dart';
import 'ticket_repository.dart';
import 'rewards_repository.dart';
import '../../services/application_api.dart';

/// State shared by the separate Figma booking screens. Card credentials never enter it.
class TicketJourney extends ChangeNotifier {
  final TicketRepository repository;
  final PendingTicketCheckoutStore pendingStore;
  TicketJourney(this.repository, this.pendingStore);
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  List<TicketPackage> packages = [];
  List<ParkTicket> tickets = [];
  List<TicketOrder> orders = [];
  List<TicketCartLine> cart = [];
  List<TicketGuest> guests = [];
  BookingProfile profile = const BookingProfile();
  Set<String> wallet = {};
  TicketCheckout? pending, completed;
  String? error;
  bool loading = true, busy = false;
  bool _catalogLoaded = false, _cartRestored = false;
  String? cartNotice;
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  int pointsUsed = 0;
  String promoCode = '';
  int discountMinor = 0;
  bool promotionAllowsPoints = true;
  bool termsAccepted = false;
  TicketCurrencyQuote? currencyQuote;
  String paymentCurrency = 'MYR';
  String get paymentLabel =>
      pending?.paymentLabel ?? currencyQuote?.label ?? priceLabel(total);
  int get quantity => cart.fold(0, (sum, line) => sum + line.quantity);
  int get subtotal => cart.fold(0, (sum, line) => sum + line.subtotal);
  int get total => subtotal - pointsUsed - discountMinor;
  int get maxPoints => promotionAllowsPoints
      ? min(profile.points, subtotal - discountMinor) ~/ 100 * 100
      : 0;
  bool get guestsComplete =>
      guests.length == quantity && guests.every((g) => g.complete);
  String get _key => 'ticket_cart_v2_${repository.userId}';
  static String newId() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> start() async {
    void failed(Object e) {
      error = bookingError(e);
      loading = false;
      notifyListeners();
    }

    _subscriptions.add(
      repository.packages().listen((value) {
        packages = [...value]
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        _catalogLoaded = true;
        if (_cartRestored) pruneUnavailableCartLines();
        loading = false;
        notifyListeners();
      }, onError: failed),
    );
    _subscriptions.add(
      repository.tickets().listen((value) {
        tickets = value;
        notifyListeners();
      }, onError: failed),
    );
    _subscriptions.add(
      repository.orders().listen((value) {
        orders = value;
        notifyListeners();
      }, onError: failed),
    );
    _subscriptions.add(
      repository.profile().listen((value) {
        profile = value;
        if (pointsUsed > maxPoints && !busy) pointsUsed = maxPoints;
        notifyListeners();
      }, onError: failed),
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      wallet = (prefs.getStringList('ticket_wallet_${repository.userId}') ?? [])
          .toSet();
      final saved = prefs.getString(_key);
      if (saved != null) {
        final data = jsonDecode(saved) as Map;
        cart = (data['cart'] as List)
            .map((e) => TicketCartLine.fromMap(Map<String, dynamic>.from(e)))
            .toList();
        guests = (data['guests'] as List)
            .map((e) => TicketGuest.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      }
      final uid = repository.userId;
      pending = uid == null ? null : await pendingStore.load(uid);
      if (pending?.isJourney == true) {
        cart = [...pending!.lines];
        guests = [...pending!.guests];
        pointsUsed = pending!.pointsUsed;
        promoCode = pending!.promoCode;
        discountMinor = pending!.discountMinor;
        termsAccepted = true;
        if (repository is FirebaseTicketRepository) {
          await verifyHostedPayment();
        }
      }
      _cartRestored = true;
      pruneUnavailableCartLines();
    } catch (_) {
      _cartRestored = true;
      error =
          'Your saved cart could not be restored. Please choose your tickets again.';
    }
    notifyListeners();
  }

  void add(TicketCartLine line) {
    if (!validVisitDate(line.visitDate)) {
      throw StateError('Select a valid visit date before adding this pass.');
    }
    if (pending != null) {
      throw StateError(
        'Finish the pending checkout before changing your cart.',
      );
    }
    if (quantity + line.quantity > 10) {
      throw StateError('You can book up to 10 tickets in one order.');
    }
    if (cart.length >= 5) {
      throw StateError('You can add up to five passes in one order.');
    }
    cart = [...cart, line];
    cartNotice = null;
    _syncGuests();
    _changed();
  }

  void remove(String id) {
    if (pending != null || busy) return;
    cartNotice = null;
    cart = cart.where((line) => line.id != id).toList();
    _syncGuests();
    _changed();
  }

  void changeCount(String id, int adults, int children) {
    if (pending != null) return;
    final old = cart.firstWhere((line) => line.id == id);
    if (adults < 0 ||
        children < 0 ||
        adults + children < 1 ||
        quantity - old.quantity + adults + children > 10) {
      return;
    }
    cart = cart
        .map((line) => line.id == id ? line.withCounts(adults, children) : line)
        .toList();
    _syncGuests();
    _changed();
  }


  /// Mirror the server's Malaysia-time 365-day booking window.
  static bool validVisitDate(String value, {DateTime? today}) {
    final date = DateTime.tryParse(value);
    final start = today ?? parkToday();
    if (date == null || visitDateString(date) != value) return false;
    return !date.isBefore(start) &&
        !date.isAfter(start.add(const Duration(days: 365)));
  }

  bool get hasInvalidVisitDate =>
      cart.any((line) => !validVisitDate(line.visitDate));

  /// Only cart entries are removed. A Stripe payment already in progress is
  /// intentionally untouched so there is no chance of losing a paid ticket.
  int pruneUnavailableCartLines({DateTime? today}) {
    if (pending != null || busy || cart.isEmpty) return 0;
    final start = today ?? parkToday();
    final availableIds = _catalogLoaded
        ? packages.map((pack) => pack.id).toSet()
        : null;
    final kept = <TicketCartLine>[];
    var expired = 0;
    var unavailable = 0;
    for (final line in cart) {
      if (!validVisitDate(line.visitDate, today: start)) {
        expired++;
      } else if (availableIds != null &&
          !availableIds.contains(line.packageId)) {
        unavailable++;
      } else {
        kept.add(line);
      }
    }
    if (expired + unavailable == 0) return 0;
    cart = kept;
    _syncGuests();
    cartNotice = [
      if (expired > 0)
        '$expired expired ${expired == 1 ? 'pass was' : 'passes were'} removed',
      if (unavailable > 0)
        '$unavailable unavailable ${unavailable == 1 ? 'pass was' : 'passes were'} removed',
    ].join('. ') + ' from your cart.';
    _changed();
    return expired + unavailable;
  }

  /// Update date and guest counts together, keeping one consistent cart state.
  void updateCartLine(String lineId, DateTime visitDate, int adults, int children) {
    if (pending != null || busy) {
      throw StateError('Please finish or verify your pending payment first.');
    }
    final index = cart.indexWhere((line) => line.id == lineId);
    if (index < 0) throw StateError('This pass is no longer in your cart.');
    final old = cart[index];
    if (!validVisitDate(visitDateString(visitDate))) {
      throw StateError('Choose a visit date within the next 365 days.');
    }
    if (adults < 0 || children < 0 || adults + children < 1 ||
        quantity - old.quantity + adults + children > 10) {
      throw StateError('Select 1 to 10 guests per order.');
    }
    final updated = TicketCartLine(
      id: old.id,
      packageId: old.packageId,
      packageName: old.packageName,
      visitDate: visitDateString(visitDate),
      adults: adults,
      children: children,
      adultPriceMinor: old.adultPriceMinor,
      childPriceMinor: old.childPriceMinor,
      durationDays: old.durationDays,
      imageAsset: old.imageAsset,
      category: old.category,
    );
    final updatedCart = [...cart];
    updatedCart[index] = updated;
    cart = updatedCart;
    currencyQuote = null;
    _syncGuests();
    cartNotice = null;
    _changed();
  }

  void updateVisitDate(String lineId, DateTime date) {
    final old = cart.where((line) => line.id == lineId).firstOrNull;
    if (old == null) return;
    try {
      updateCartLine(lineId, date, old.adults, old.children);
    } catch (e) {
      error = bookingError(e);
      notifyListeners();
    }
  }

  /// A failed date validation occurs before a Stripe Checkout session is
  /// created. Do not discard a checkout that the server still recognises.
  Future<bool> recoverRejectedVisitDate() async {
    if (busy) return false;
    final request = pending;
    if (request == null) {
      error = null;
      notifyListeners();
      return true;
    }
    busy = true;
    notifyListeners();
    try {
      final status = await repository.hostedPaymentStatus(request.requestId);
      error = status == 'paid'
          ? 'Payment has already succeeded. Check payment status first.'
          : 'A payment session may already exist. Check payment status before changing your booking.';
      return false;
    } catch (e) {
      // The server returns this exact message when no payment record exists.
      // A transient/network/permission error must NOT erase pending checkout.
      if (bookingError(e) != 'This payment is not linked to your account.') {
        error = bookingError(e);
        return false;
      }
      final uid = repository.userId;
      if (uid == null) {
        error = 'Please sign in again to change your booking.';
        return false;
      }
      await pendingStore.clear(uid);
      pending = null;
      error = null;
      return true;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _syncGuests() {
    promoCode = '';
    discountMinor = 0;
    promotionAllowsPoints = true;
    final old = {for (final guest in guests) guest.id: guest};
    guests = [
      for (final line in cart)
        for (final type in ['adult', 'child'])
          for (
            var i = 0;
            i < (type == 'adult' ? line.adults : line.children);
            i++
          )
            old['${line.id}_${type}_$i'] ??
                TicketGuest(
                  id: '${line.id}_${type}_$i',
                  lineId: line.id,
                  type: type,
                ),
    ];
    pointsUsed = min(pointsUsed, maxPoints);
    termsAccepted = false;
  }

  void updateGuest(TicketGuest guest) {
    if (pending != null) return;
    guests = guests.map((g) => g.id == guest.id ? guest : g).toList();
    _changed();
  }

  void setPoints(int value) {
    pointsUsed = value.clamp(0, maxPoints) ~/ 100 * 100;
    notifyListeners();
  }

  Future<void> applyPromotion(String code) async {
    if (busy || pending != null) return;
    if (code.trim().isEmpty) {
      promoCode = '';
      discountMinor = 0;
      promotionAllowsPoints = true;
      notifyListeners();
      return;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final normalized = code.trim().toUpperCase(),
          quote = await repository.promotionQuote(
            TicketCheckout.journey(
              requestId: newId(),
              lines: cart,
              guests: guests,
              promoCode: normalized,
            ),
          );
      promoCode = normalized;
      discountMinor = (quote['discountMinor'] as num).toInt();
      promotionAllowsPoints = quote['allowPoints'] != false;
      pointsUsed = min(pointsUsed, maxPoints);
      termsAccepted = false;
    } catch (e) {
      error = bookingError(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void acceptTerms(bool value) {
    termsAccepted = value;
    notifyListeners();
  }

  void _changed() {
    error = null;
    unawaited(_saveCart());
    notifyListeners();
  }

  Future<void> _saveCart() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'cart': cart.map((l) => l.toMap()).toList(),
        'guests': guests.map((g) => g.toMap()).toList(),
      }),
    );
  }

  Future<bool> prepareCurrency(String code) async {
    if (busy || pending != null) return false;
    paymentCurrency = code;
    currencyQuote = null;
    if (code == 'MYR') {
      notifyListeners();
      return true;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.promotionQuote(
        TicketCheckout.journey(
          requestId: newId(),
          lines: cart,
          guests: guests,
          pointsUsed: pointsUsed,
          promoCode: promoCode,
          discountMinor: discountMinor,
        ),
        paymentCurrency: code,
      );
      if (result['totalMinor'] != total ||
          result['discountMinor'] != discountMinor) {
        error =
            'The booking total changed. Review your promotion and points before continuing.';
        termsAccepted = false;
        return false;
      }
      currencyQuote = TicketCurrencyQuote.fromMap(result, total);
      return true;
    } catch (e) {
      error = bookingError(e);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> verifyHostedPayment() async {
    final request = pending;
    if (busy || request == null) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final status = await repository.hostedPaymentStatus(request.requestId);
      if (status == 'paid') {
        final uid = repository.userId;
        completed = request;
        if (uid != null) await pendingStore.clear(uid);
        pending = null;
        cart = [];
        guests = [];
        pointsUsed = 0;
        promoCode = '';
        discountMinor = 0;
        promotionAllowsPoints = true;
        termsAccepted = false;
        await _saveCart();
        try {
          await FirebaseRewardsRepository().collectOrder(request.requestId);
        } catch (_) {
          // Ticket payment is already verified; rewards can be collected later.
        }
        return true;
      }
      error = status == 'manual_review'
          ? 'Your payment was received but needs staff review. Please contact support; do not pay again.'
          : 'Payment has not been confirmed yet. Complete Stripe Checkout or check again.';
      return false;
    } catch (e) {
      error = bookingError(e);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> pay(String method, {String cardLast4 = ''}) async {
    if (busy) return false;
    if (pending != null) {
      if (await verifyHostedPayment()) return true;
      if (error?.contains('staff review') == true) return false;
    }
    if (pending == null && hasInvalidVisitDate) {
      error = 'Choose a valid visit date within the next year.';
      notifyListeners();
      return false;
    }
    if (pending == null && (!guestsComplete || !termsAccepted)) {
      error = 'Complete the guest details and accept the ticket terms first.';
      notifyListeners();
      return false;
    }
    if (pending == null && paymentCurrency != 'MYR') {
      error = 'Stripe Checkout currently accepts MYR. Select MYR before paying.';
      notifyListeners();
      return false;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final request = pending ?? TicketCheckout.journey(
        requestId: newId(),
        lines: cart,
        guests: guests,
        pointsUsed: pointsUsed,
        paymentMethod: 'card',
        promoCode: promoCode,
        discountMinor: discountMinor,
      );
      final uid = repository.userId;
      if (uid == null) throw StateError('Please sign in before payment.');
      await pendingStore.save(uid, request);
      pending = request;
      final url = await repository.startHostedPayment(request);
      if (url == 'paid') {
        busy = false;
        return await verifyHostedPayment();
      }
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https' ||
          uri.host != 'checkout.stripe.com') {
        throw StateError('The secure payment page is unavailable. Please retry.');
      }
      if (!await launchUrl(uri, webOnlyWindowName: '_self')) {
        throw StateError('Could not open Stripe Checkout. Please retry.');
      }
      return false; // Success is confirmed only by the verified server response.
    } catch (e) {
      error = bookingError(e);
      // Date validation rejects the request before any Stripe session/record.
      // Release the locally saved pending checkout so the date can be edited.
      if (error == 'Choose a valid visit date within the next year.' &&
          pending != null) {
        final uid = repository.userId;
        if (uid != null) {
          await pendingStore.clear(uid);
          pending = null;
        }
      }
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> addToWallet(ParkTicket ticket) async {
    wallet.add(ticket.id);
    await (await SharedPreferences.getInstance()).setStringList(
      'ticket_wallet_${repository.userId}',
      wallet.toList(),
    );
    notifyListeners();
  }

  Future<bool> cancelPendingPayment() async {
    final request = pending;
    final uid = repository.userId;
    if (busy || request == null || uid == null) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.cancelHostedPayment(request.requestId);
      if (result == 'paid') {
        busy = false;
        return await verifyHostedPayment();
      }
      if (result == 'expired' && repository.userId == uid) {
        await pendingStore.clear(uid);
        pending = null;
        termsAccepted = false;
        cartNotice = 'Checkout cancelled. You can edit your cart.';
      } else {
        error = result == 'manual_review'
            ? 'Payment needs staff review. Contact support.'
            : 'Payment is still processing. Check its status before changing your cart.';
      }
      return false;
    } catch (e) {
      error = bookingError(e);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Resolve the server state before allowing an uncertain request to be replaced.
  Future<bool> reviewPending() async {
    if (busy || pending == null) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (repository is FirebaseTicketRepository) {
        error = 'This payment may still be processing. Verify its status before starting a new booking. Contact support if Stripe Checkout has expired.';
        return false;
      }
      if (await repository.orderExists(pending!.requestId)) {
        error =
            'This booking is already confirmed. Retry checkout to open your tickets.';
        return false;
      }
      await pendingStore.clear(repository.userId!);
      pending = null;
      termsAccepted = false;
      return true;
    } catch (e) {
      error = bookingError(e);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    super.dispose();
  }
}

String bookingError(Object error) {
  if (error is ApplicationApiException) return error.message;
  if (error is FirebaseFunctionsException) {
    if (error.code == 'unauthenticated') {
      return 'Please sign in with your verified email and try again.';
    }
    if (error.message?.isNotEmpty == true) return error.message!;
    return 'Unable to complete the payment request. Please try again.';
  }
  final text = error.toString();
  if (text.contains('permission-denied')) {
    return 'This action could not be authorised. Check that your email is verified, then try again.';
  }
  if (text.contains('unavailable') || text.contains('network')) {
    return 'Unable to connect. Your checkout is saved; retry when you are online.';
  }
  if (error is StateError) return error.message;
  if (text.contains('failed-precondition')) {
    return text.replaceFirst(RegExp(r'^.*?\] '), '');
  }
  return 'We could not complete this action. Please try again.';
}
