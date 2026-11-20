import 'dart:async'; // PARKSMART_V19_ANDROID_PAYMENT_RETURN
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'pages/tickets_page.dart';
import 'pages/map_page.dart';
import 'pages/queue_page.dart';
import 'pages/profile_page.dart';
import 'pages/souvenir_shop_page.dart'; // PARKSMART_V16_REFUND_CROWD_HISTORY
import '../photos/photo_checkout_pages.dart' show PhotoPaymentPage;
import '../photos/photo_repository.dart' show FirebasePhotoRepository;
import 'widgets/visitor_bottom_nav.dart';

class VisitorMainPage extends StatefulWidget {
  static void goTo(BuildContext context, int index) =>
      _VisitorMainPageState.goTo(context, index);
  static void openTickets(BuildContext context, String section) =>
      _VisitorMainPageState.openTickets(context, section);
  static void openTicketOrder(BuildContext context, String orderId) =>
      _VisitorMainPageState.openTicketOrder(orderId);
  const VisitorMainPage({super.key});

  @override
  State<VisitorMainPage> createState() => _VisitorMainPageState();
}

class _VisitorMainPageState extends State<VisitorMainPage> {
  static void openTicketOrder(String orderId) {
    final state = _active;
    if (state == null || !state.mounted) return;
    state._ticketsKey.currentState?.openOrder(orderId);
    state._onTabSelected(1, resetTickets: false);
  }

  // PARKSMART_V19_ANDROID_PAYMENT_RETURN: Android's callback is not a payment receipt.
  static const MethodChannel _androidPaymentChannel = MethodChannel('parksmart/payment-return');
  String? _lastMobileReturn;

  Future<void> _consumeAndroidPaymentReturn() async {
    try {
      final link = await _androidPaymentChannel.invokeMethod<String>('consumePending');
      if (mounted && link != null) _handleAndroidPaymentReturn(link);
    } on MissingPluginException {
      // This callback is only installed by Android native builds.
    } on PlatformException {
      // Manual order-status verification remains available.
    }
  }

  void _handleAndroidPaymentReturn(String link) {
    final uri = Uri.tryParse(link);
    if (!mounted || link == _lastMobileReturn || uri == null ||
        uri.scheme != 'parksmart-fyp' || uri.host != 'payment') return;
    final kind = uri.queryParameters['kind'];
    final orderId = uri.queryParameters['order'] ?? '';
    final validOrder = RegExp(kind == 'ticket' ? r'^[a-f0-9]{48}$' : r'^[a-f0-9]{64}$').hasMatch(orderId);
    if (!validOrder || !['ticket', 'souvenir', 'photo'].contains(kind)) return;
    _lastMobileReturn = link;
    // Native intent can arrive without a new Dart frame; ensure the navigation runs.
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (kind == 'ticket') {
        unawaited(_verifyReturnedTicket());
      } else if (kind == 'photo') {
        _openReturnedPhoto(orderId);
      } else {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
          const SouvenirShopPage(initialOrders: true)));
      }
    });
  }

  void _openReturnedPhoto(String orderId) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoPaymentPage(
      repository: FirebasePhotoRepository(),
      returningPaymentId: orderId,
    )));
  }

  Future<void> _verifyReturnedTicket() async {
    _onTabSelected(1, resetTickets: false);
    final tickets = _ticketsKey.currentState;
    if (tickets == null || !tickets.mounted) return;
    if (tickets.journey.pending == null) {
      tickets.showSection(tickets.journey.completed != null ? 'success' : 'hub');
      return;
    }
    tickets.showSection('payment');
    try {
      final confirmed = await tickets.journey.verifyHostedPayment();
      if (!mounted || !tickets.mounted) return;
      tickets.showSection(confirmed ? 'success' : 'payment');
    } catch (_) {
      // The payment screen retains its manual status-verification action.
    }
  }

  final _ticketsKey = GlobalKey<TicketsPageState>();
  static void openTickets(BuildContext context, String section) {
    final state = _active;
    if (state == null || !state.mounted) return;
    state._ticketsKey.currentState?.showSection(section);
    state._onTabSelected(1, resetTickets: false);
  }

  static _VisitorMainPageState? _active;
  static void goTo(BuildContext context, int index) {
    final state = _active;
    if (state != null && state.mounted) state._onTabSelected(index);
  }

  @override
  void initState() {
    super.initState();
    _active = this;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _androidPaymentChannel.setMethodCallHandler((call) async {
        if (call.method == 'paymentReturned' && call.arguments is String) {
          _handleAndroidPaymentReturn(call.arguments as String);
          unawaited(_consumeAndroidPaymentReturn());
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_consumeAndroidPaymentReturn());
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _commerceReturnOpened || !Uri.base.queryParameters.containsKey('commerce_payment')) return;
      _commerceReturnOpened = true;
      final query = Uri.base.queryParameters;
      if (query['purchase_type'] == 'photo') {
        final id = query['order'];
        if (id != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
          _openReturnedPhoto(id);
        }
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
        const SouvenirShopPage(initialOrders:true)));
    });
  }

  @override
  void dispose() {
    if (identical(_active, this)) _active = null;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _androidPaymentChannel.setMethodCallHandler(null);
    }
    _startPlace.dispose();
    super.dispose();
  }

  bool _commerceReturnOpened = false;
  int _selectedIndex = 0;
  final _startPlace = ValueNotifier<String?>(null);

  late final List<Widget> _pages = [
    HomePage(),
    TicketsPage(key: _ticketsKey),
    MapPage(startPlace: _startPlace),
    QueuePage(startPlace: _startPlace),
    ProfilePage(),
  ];

  void _onTabSelected(int index, {bool resetTickets = true}) {
    if (_ticketsKey.currentState?.journey.busy == true) return;
    if (index == 1 && resetTickets) {
      _ticketsKey.currentState?.showSection('hub');
    }
    if (index == _selectedIndex) return;

    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFDF4EF),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Scaffold(
            backgroundColor: const Color(0xFFFDF4EF),
            body: IndexedStack(index: _selectedIndex, children: _pages),
            bottomNavigationBar: VisitorBottomNav(
              selectedIndex: _selectedIndex,
              onTap: _onTabSelected,
            ),
          ),
        ),
      ),
    );
  }
}
