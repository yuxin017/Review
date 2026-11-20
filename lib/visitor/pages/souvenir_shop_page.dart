import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../commerce/stripe_commerce_client.dart';
import '../widgets/souvenir_product_image.dart';

class SouvenirShopPage extends StatefulWidget {
  const SouvenirShopPage({super.key, this.initialOrders = false, this.initialSearch = '', this.initialStoreId});
  final bool initialOrders;
  final String initialSearch;
  final String? initialStoreId;
  @override
  State<SouvenirShopPage> createState() => _SouvenirShopPageState();
}

class _SouvenirShopPageState extends State<SouvenirShopPage> with WidgetsBindingObserver {
  final _client = StripeCommerceClient();
  final Map<String,int> _cart = {};
  String? _shopId, _pendingPaymentId, _pendingRequestId, _notice;
  bool _busy = false, _orders = false;
  List<Map<String,dynamic>>? _failedCheckoutItems; // PARKSMART_V16_REFUND_CROWD_HISTORY
  bool _checkoutFailed = false;
  Timer? _paymentStatusTimer;
  bool _paymentCheckRunning = false;
  int _paymentAutoAttempts = 0;
  static const int _maxPaymentAutoAttempts = 12;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _pendingKey => 'souvenir_pending_$_uid';
  String _money(int cents) => 'RM ${(cents/100).toStringAsFixed(2)}';
  String _newId() => List.generate(24, (_) => Random.secure().nextInt(256)
      .toRadixString(16).padLeft(2,'0')).join();

  // SOUVENIR_PAYMENT_AUTO10: poll a bounded number of times, and again after app/tab resume.
  // A trusted Stripe API response, NOT a URL query parameter, determines Paid/Expired.
  @override
  void initState() {
    super.initState();
    _orders = widget.initialOrders;
    _search = widget.initialSearch;
    _shopId = widget.initialStoreId;
    WidgetsBinding.instance.addObserver(this);
    _loadPending();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _paymentStatusTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_pendingPaymentId != null) _startAutomaticPaymentCheck();
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _paymentStatusTimer?.cancel();
    }
  }

  Future<void> _loadPending() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_pendingKey);
    if (mounted && saved != null && saved.isNotEmpty) {
      setState(() => _pendingPaymentId = saved);
      _startAutomaticPaymentCheck();
    }
  }

  void _startAutomaticPaymentCheck() {
    if (!mounted || _pendingPaymentId == null) return;
    _paymentStatusTimer?.cancel();
    _paymentAutoAttempts = 0;
    _automaticPaymentAttempt();
    _paymentStatusTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || _pendingPaymentId == null ||
          _paymentAutoAttempts >= _maxPaymentAutoAttempts) {
        timer.cancel();
        return;
      }
      _automaticPaymentAttempt();
    });
  }

  void _automaticPaymentAttempt() {
    if (_paymentCheckRunning || _busy || _pendingPaymentId == null) return;
    _paymentAutoAttempts++;
    unawaited(_checkPayment(silent: true));
  }

  Future<void> _checkPayment({bool silent = false}) async {
    final id = _pendingPaymentId;
    if (id == null || (silent && _busy)) return;
    if (_paymentCheckRunning) {
      if (!silent && mounted) setState(() => _notice='Payment status is already being checked.');
      return;
    }
    _paymentCheckRunning = true;
    if (!silent) setState(() {_busy = true; _notice = null;});
    try {
      final result = await _client.status(id);
      if (!mounted || id != _pendingPaymentId) return;
      final status = result['status'];
      if (status == 'paid' || status == 'expired') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingKey);
        if (!mounted || id != _pendingPaymentId) return;
        _paymentStatusTimer?.cancel();
        setState(() {
          _pendingPaymentId = null;
          _pendingRequestId = null;
          if (status == 'paid') {
            _cart.clear();
            _orders = true;
            _notice = 'Payment confirmed. Your souvenir order is ready for staff processing.';
          } else {
            _notice = 'Checkout expired. Reserved stock was released. Try again.';
          }
        });
      } else if (status == 'manual_review') {
        _paymentStatusTimer?.cancel();
        setState(() => _notice =
            'Payment needs staff review. Please do not pay again.');
      } else if (!silent) {
        setState(() => _notice =
            'Payment is not confirmed yet. Return from Stripe Checkout or try again later.');
      }
    } catch (error) {
      if (mounted && !silent) setState(() => _notice = error.toString());
      // Silent checks can fail transiently while reconnecting. Keep the manual button.
    } finally {
      _paymentCheckRunning = false;
      if (mounted && !silent) setState(() => _busy = false);
    }
  }
  // PARKSMART_V15_PAYMENT_CROWD: cancellation requires Stripe's EXPIRED state.
  Future<void> _cancelPendingCheckout() async {
    final id = _pendingPaymentId;
    if (id == null || _busy) return;
    final agreed = await showDialog<bool>(context: context, builder: (ctx) =>
      AlertDialog(title: const Text('Cancel unpaid checkout?'),
        content: const Text('Stripe must confirm that the payment has not completed. Only then will reserved stock be released.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Checkout')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel Checkout')),
        ]));
    if (agreed != true || !mounted) return;
    setState(() { _busy = true; _notice = null; });
    try {
      final result = await _client.cancel(id);
      if (!mounted) return;
      final status = result['status'];
      if (status == 'expired') {
        await (await SharedPreferences.getInstance()).remove(_pendingKey);
        if (!mounted) return;
        _paymentStatusTimer?.cancel();
        setState(() {
          _pendingPaymentId = null;
          _pendingRequestId = null;
          _notice = 'Checkout cancelled. Stripe confirmed expiry and reserved stock was restored.';
        });
      } else if (status == 'paid') {
        setState(() => _notice = 'Payment already completed. Checking your order...');
      } else {
        setState(() => _notice = 'Payment is still processing. Stock remains reserved until Stripe confirms it has ended.');
      }
    } catch (error) {
      if (mounted) setState(() => _notice = 'Cancellation not confirmed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_pendingPaymentId != null) _startAutomaticPaymentCheck();
      }
    }
  }

  Future<void> _checkout(List<QueryDocumentSnapshot<Map<String,dynamic>>> products) async {
    if (_busy || _cart.isEmpty || _pendingPaymentId!=null) return;
    final selected = <Map<String,dynamic>>[];
    for (final p in products) {
      final count = _cart[p.id] ?? 0;
      if (count > 0) selected.add({'id':p.id,'quantity':count});
    }
    if (selected.isEmpty) return;
    setState(() {_busy=true;_notice=null;});
    try {
      final quote = await _client.shopQuote(selected);
      final agreed = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title: const Text('Confirm Souvenir Order'),
        content: Text('Total: ${_money((quote['totalMinor'] as num).toInt())}\n'
          'Payment will open Stripe secure checkout.\n'
          'Stock is reserved during checkout.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Pay Now'))],
      ));
      if (agreed != true || !mounted) return;
      final requestId = _pendingRequestId ?? _newId();
      _pendingRequestId = requestId;
      _failedCheckoutItems = selected;
      final response = await _client.checkout('souvenir',requestId,{'items':selected});
      _checkoutFailed=false;
      if (!mounted) return;
      _pendingPaymentId=response['orderId'] as String?;
      final id=_pendingPaymentId;
      if(id!=null) await (await SharedPreferences.getInstance()).setString(_pendingKey,id);
      if (response['status'] == 'paid') {
        if (mounted) setState(() => _notice='Confirming payment...');
      } else if (response['url'] is String) {
        await _client.openCheckout(response['url'] as String);
        if (mounted) setState(() => _notice='Stripe Checkout opened. Payment status will refresh automatically when you return.');
      } else {
        throw StateError('No checkout URL. Please check payment status.');
      }
    } catch(e) {
      if(mounted) setState(() { _checkoutFailed=true; _notice='Checkout could not open. Do not pay again until status is checked. $e'; });
      if (_pendingPaymentId == null && _pendingRequestId != null) {
        try {
          final recovered=await _client.recoverCheckout(_pendingRequestId!);
          if (mounted && recovered['orderId'] is String) {
            final id=recovered['orderId'] as String;
            await (await SharedPreferences.getInstance()).setString(_pendingKey,id);
            if (mounted) setState(() => _pendingPaymentId=id);
          }
        } catch (_) { /* Keep the same request reference for safe retry. */ }
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_pendingPaymentId != null) _startAutomaticPaymentCheck();
      }
    }
  }

  // PARKSMART_V16_REFUND_CROWD_HISTORY: retry exactly the same checkout reference.
  Future<void> _retryFailedCheckout() async {
    final id = _pendingRequestId;
    final items = _failedCheckoutItems;
    if (_busy || id == null || items == null) return;
    setState(() {_busy=true;_notice=null;});
    try {
      final res=await _client.checkout('souvenir',id,{'items':items});
      if (!mounted) return;
      final orderId=res['orderId'] as String?;
      if (orderId != null) {
        await (await SharedPreferences.getInstance()).setString(_pendingKey,orderId);
        if (mounted) setState(() => _pendingPaymentId=orderId);
      }
      if (res['url'] is String) {
        await _client.openCheckout(res['url'] as String);
        if (mounted) setState(() => _checkoutFailed=false);
      } else if (res['status']=='paid') {
        await _checkPayment(silent:true);
        if (mounted) setState(() => _checkoutFailed=false);
      } else if (mounted) {
        setState(() => _notice='Checkout is pending. Use Check Payment Status.');
      }
    } catch(e) {
      if (mounted) setState(() => _notice='Retry failed: $e');
    } finally {
      if (mounted) setState(() => _busy=false);
    }
  }

  // PARKSMART_REFUND_FORM_V18: do not close dialog before API confirmation.
  Future<void> _requestSouvenirRefund(String orderId) async {
    if (_busy || !mounted) return;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ParkSmartRefundRequestDialogV18(
        client: _client,
        orderId: orderId,
      ),
    );
    if (!mounted || result == null) return;
    final message = result == 'requested'
        ? 'Refund request submitted. Waiting for Admin approval.'
        : 'Your refund request is already being reviewed. Status: $result.';
    setState(() => _notice = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // SOUVENIR_UI_V8: owner-only order list and a responsive product catalogue.
  Widget _orderHistory() {
    if (_uid.isEmpty) {
      return _emptyState(Icons.lock_outline, 'Sign in to view purchases',
          'Your souvenir orders are linked to your visitor account.');
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('souvenirOrders')
          .where('ownerUid', isEqualTo: _uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final text = snapshot.error.toString();
          final accessDenied = text.contains('permission-denied') ||
              text.contains('PERMISSION_DENIED');
          return _emptyState(Icons.lock_outline, 'Orders unavailable',
              accessDenied
                  ? 'Firestore is blocking access to your orders. Ask the administrator to update the souvenirOrders read rule.'
                  : 'Could not load orders. Check your connection and try again.');
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = [...snapshot.data!.docs]..sort((a, b) {
          final aTime = a.data()['createdAt'] as Timestamp?;
          final bTime = b.data()['createdAt'] as Timestamp?;
          return (bTime?.millisecondsSinceEpoch ?? 0)
              .compareTo(aTime?.millisecondsSinceEpoch ?? 0);
        });
        if (orders.isEmpty) {
          return _emptyState(Icons.receipt_long_outlined,
              'No souvenir orders yet',
              'After your payment is verified, your order will appear here.');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
          itemCount: orders.length + 1,
          separatorBuilder: (_, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('My Orders', style: TextStyle(
                      fontSize: 23, fontWeight: FontWeight.w800, color: _ink)),
                  const SizedBox(height: 4),
                  Text('${orders.length} purchase${orders.length == 1 ? '' : 's'}',
                      style: const TextStyle(color: _muted)),
                ],
              );
            }
            final order = orders[index - 1];
            final data = order.data();
            final rows = data['items'] as List? ?? [];
            final refundStatus = (data['refundStatus'] ?? '').toString();
            final status = data['status'] == 'refunded' ? 'refunded'
                : refundStatus=='requested' ? 'refund requested'
                : refundStatus=='pending' ? 'refund processing'
                : refundStatus=='rejected' ? 'refund rejected'
                : (data['fulfillmentStatus'] ?? 'awaiting_collection')
                    .toString().replaceAll('_', ' ');
            final price = (data['totalMinor'] as num?)?.toInt() ?? 0;
            final paidAt = data['paidAt'] as Timestamp?;
            final date = paidAt?.toDate();
            final when = date == null ? '' :
                '${date.day.toString().padLeft(2, '0')}/'
                '${date.month.toString().padLeft(2, '0')}/${date.year}';
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: _panelDecoration(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.shopping_bag_outlined,
                        color: _rose, size: 21),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Order #${order.id.substring(0, 10).toUpperCase()}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                    Text(when, style: const TextStyle(fontSize: 11,
                        color: _muted)),
                  ]),
                  const Divider(height: 24),
                  for (final item in rows)
                    if (item is Map)
                      Padding(padding: const EdgeInsets.only(bottom: 7),
                        child: Row(children: [
                          Expanded(child: Text(
                              '${item['name'] ?? 'Souvenir'} × ${item['quantity'] ?? 1}',
                              maxLines: 2, overflow: TextOverflow.ellipsis)),
                          Text(_money((item['lineMinor'] as num?)?.toInt() ?? 0),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ])),
                  if (data['status']=='paid' &&
                      data['fulfillmentStatus']=='awaiting_collection' &&
                      !['requested','pending','succeeded','rejected'].contains(refundStatus))
                    Align(alignment:Alignment.centerRight,
                      child:TextButton.icon(
                        onPressed:_busy ? null : ()=>_requestSouvenirRefund(order.id),
                        icon:const Icon(Icons.currency_exchange_outlined,size:17),
                        label:const Text('Request Refund'))),
                  const SizedBox(height: 9),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F4E9),
                        borderRadius: BorderRadius.circular(9)),
                      child: Text(status,
                        style: const TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF307044))),
                    ),
                    const Spacer(),
                    Text(_money(price), style: const TextStyle(
                        color: _rose, fontWeight: FontWeight.w800, fontSize: 17)),
                  ]),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static const _rose = Color(0xFFA74F55);
  static const _ink = Color(0xFF302A2A);
  static const _muted = Color(0xFF827673);
  static const _cream = Color(0xFFFDF4EF);

  BoxDecoration _panelDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0xFFEFDEDA)),
  );

  Widget _emptyState(IconData icon, String heading, String detail) => Center(
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 70, height: 70,
          decoration: const BoxDecoration(color: Color(0xFFF8E7E3),
              shape: BoxShape.circle),
          child: Icon(icon, size: 32, color: _rose)),
        const SizedBox(height: 16),
        Text(heading, textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17,
                color: _ink)),
        const SizedBox(height: 7),
        Text(detail, textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, height: 1.5)),
      ])),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _cream,
    appBar: AppBar(
      backgroundColor: _cream,
      foregroundColor: _ink,
      surfaceTintColor: Colors.transparent,
      title: Text(_orders ? 'My Souvenir Orders' : 'Souvenir Shop',
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      actions: [
        IconButton(
          tooltip: _orders ? 'Back to Shop' : 'My Orders',
          onPressed: () => setState(() => _orders = !_orders),
          icon: Icon(_orders ? Icons.storefront_outlined : Icons.receipt_long_outlined,
              color: _rose),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: Column(children: [
      if (_pendingPaymentId != null)
        MaterialBanner(
          content: const Text('Payment verification pending. This page checks automatically; you can also check manually.'),
          actions: [TextButton(
            onPressed: _busy ? null : () => _checkPayment(),
            child: const Text('Check Payment Status'),
          ), TextButton(
            onPressed: _busy ? null : _cancelPendingCheckout,
            child: const Text('Cancel Checkout'),
          )],
        ),
      if (_checkoutFailed && _pendingRequestId != null && _failedCheckoutItems != null)
        MaterialBanner(
          content: const Text('Checkout was interrupted. Retry the same request to avoid duplicate stock reservations.'),
          actions: [TextButton(onPressed: _busy ? null : _retryFailedCheckout,
            child: const Text('Retry Checkout'))],
        ),
      if (_notice != null)
        Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Container(width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: const Color(0xFFF8E6E2),
                borderRadius: BorderRadius.circular(12)),
            child: Text(_notice!, style: const TextStyle(color: _rose))),
        ),
      if (_busy) const LinearProgressIndicator(color: _rose),
      Expanded(child: _orders ? _orderHistory() : _catalogue()),
    ]),
  );

  String _category = 'All';
  String _search = '';
  late final _searchController = TextEditingController(text: widget.initialSearch);

  Widget _productCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final p = doc.data();
    final name = (p['name'] ?? 'Souvenir').toString();
    final category = (p['category'] ?? 'Souvenirs').toString();
    final description = (p['description'] ?? '').toString();
    final image = (p['imageUrl'] ?? '').toString();
    final price = (p['priceMinor'] as num?)?.toInt() ?? 0;
    final stock = (p['stockQuantity'] as num?)?.toInt() ?? 0;
    final qty = _cart[doc.id] ?? 0;
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFEFDEDA)),
      ),
      child: InkWell(
        onTap: () => _showDetails(doc),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            SouvenirProductImage(url: image, width: double.infinity, height: 122),
            if (stock == 0)
              Positioned(right: 9, top: 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.white,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Text('Sold out', style: TextStyle(color: _rose,
                        fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                )),
          ]),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                      color: _ink)),
                const SizedBox(height: 4),
                Text(category, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: _muted)),
                const Spacer(),
                Text(_money(price), style: const TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w800, color: _rose)),
                const SizedBox(height: 3),
                Text(stock > 0 ? '$stock available' : 'Unavailable',
                  style: const TextStyle(fontSize: 10, color: _muted)),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (qty > 0) ...[
                    _quantityButton(Icons.remove, () => setState(() {
                      if (qty == 1) {
                        _cart.remove(doc.id);
                      } else {
                        _cart[doc.id] = qty - 1;
                      }
                    })),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 9),
                      child: Text('$qty', style: const TextStyle(
                          fontWeight: FontWeight.w800))),
                  ],
                  _quantityButton(Icons.add,
                    stock <= qty || _pendingPaymentId != null ? null :
                    () => setState(() => _cart[doc.id] = qty + 1),
                    filled: true),
                ]),
              ],
            ),
          )),
        ]),
      ),
    );
  }

  Widget _quantityButton(IconData icon, VoidCallback? onTap,
      {bool filled = false}) => SizedBox(
    width: 32, height: 32,
    child: Material(
      color: filled ? _rose : const Color(0xFFF8EAE6),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: _busy ? null : onTap,
        child: Icon(icon, size: 19,
          color: filled ? Colors.white : _rose),
      ),
    ),
  );

  Future<void> _showDetails(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final p = doc.data();
    final qty = _cart[doc.id] ?? 0;
    final stock = (p['stockQuantity'] as num?)?.toInt() ?? 0;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheet) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
        child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SouvenirProductImage(url: (p['imageUrl'] ?? '').toString(),
                height: 185, width: double.infinity, radius: 17),
            const SizedBox(height: 18),
            Text((p['name'] ?? 'Souvenir').toString(),
                style: const TextStyle(fontSize: 22,
                    color: _ink, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text((p['category'] ?? 'Souvenirs').toString(),
                style: const TextStyle(color: _muted)),
            const SizedBox(height: 12),
            Text(_money((p['priceMinor'] as num?)?.toInt() ?? 0),
                style: const TextStyle(color: _rose, fontSize: 21,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text((p['description'] ?? '').toString().trim().isEmpty
                ? 'Collect a special souvenir from the park.'
                : (p['description'] ?? '').toString(),
              style: const TextStyle(color: _muted, height: 1.5)),
            const SizedBox(height: 12),
            Text(stock > 0 ? '$stock available' : 'Currently unavailable',
                style: const TextStyle(color: _muted)),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _rose,
                  padding: const EdgeInsets.symmetric(vertical: 15)),
              onPressed: stock <= qty || _pendingPaymentId != null
                  ? null
                  : () {
                      setState(() => _cart[doc.id] = qty + 1);
                      Navigator.pop(sheet);
                    },
              icon: const Icon(Icons.add_shopping_cart_outlined),
              label: Text(stock <= qty ? 'Unavailable' : 'Add to Cart'),
            )),
          ],
        )),
      )),
    );
  }

  Widget _catalogue() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('attractions').snapshots(),
    builder: (context, shopsSnapshot) {
      if (shopsSnapshot.hasError) {
        return _emptyState(Icons.store_mall_directory_outlined,
            'Shops unavailable', 'Unable to load park shops.');
      }
      if (!shopsSnapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final shops = shopsSnapshot.data!.docs.where((doc) {
        final p = doc.data();
        final kind = (p['kind'] ?? p['category'] ?? '')
            .toString().toLowerCase();
        return p['deletedAt'] == null &&
            (kind.contains('shop') || kind.contains('retail') ||
                kind.contains('souvenir') || kind.contains('shopping') ||
                kind.contains('gift'));
      }).toList();
      final shopIds = shops.map((doc) => doc.id).toSet();
      final chosen = shopIds.contains(_shopId)
          ? _shopId : (shops.isEmpty ? null : shops.first.id);
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('parkMenuItems')
            .where('active', isEqualTo: true).snapshots(),
        builder: (context, productsSnapshot) {
          if (productsSnapshot.hasError) {
            return _emptyState(Icons.lock_outline,
                'Catalogue unavailable',
                'Your account cannot read the product catalogue. '
                'Check the published Firestore Rules.');
          }
          if (!productsSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = productsSnapshot.data!.docs
              .where((doc) => shopIds.contains(doc.data()['storeId']))
              .toList();
          final inShop = all.where((doc) => doc.data()['storeId'] == chosen)
              .toList();
          final categories = <String>{'All',
            ...inShop.map((doc) => (doc.data()['category'] ?? 'Other').toString())}
              .toList();
          final activeCategory = categories.contains(_category) ? _category : 'All';
          final term = _search.trim().toLowerCase();
          final filtered = inShop.where((doc) {
            final p = doc.data();
            final category = (p['category'] ?? 'Other').toString();
            final matchesCategory = activeCategory == 'All' || category == activeCategory;
            final matchesSearch = term.isEmpty ||
                (p['name'] ?? '').toString().toLowerCase().contains(term) ||
                (p['description'] ?? '').toString().toLowerCase().contains(term);
            return matchesCategory && matchesSearch;
          }).toList();
          final picked = all.where((doc) => (_cart[doc.id] ?? 0) > 0).toList();
          final amount = picked.fold<int>(0, (total, doc) => total +
              ((_cart[doc.id] ?? 0) *
                  ((doc.data()['priceMinor'] as num?)?.toInt() ?? 0)));
          final count = picked.fold<int>(0, (total, doc) => total + (_cart[doc.id] ?? 0));
          return Column(children: [
            Expanded(child: CustomScrollView(slivers: [
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.fromLTRB(17, 16, 17, 9),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(17),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [
                          Color(0xFFF5DED9), Color(0xFFFFF8F4),
                        ]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(children: [
                        Container(width: 44, height: 44,
                          decoration: BoxDecoration(color: Colors.white,
                            borderRadius: BorderRadius.circular(13)),
                          child: const Icon(Icons.card_giftcard_outlined,
                              color: _rose, size: 26)),
                        const SizedBox(width: 12),
                        const Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Park Collection',
                              style: TextStyle(fontSize: 19,
                                  fontWeight: FontWeight.w800, color: _ink)),
                            SizedBox(height: 4),
                            Text('A little magic to take home',
                              style: TextStyle(fontSize: 11, color: _muted)),
                          ],
                        )),
                      ]),
                    ),
                    const SizedBox(height: 17),
                    if (shops.isNotEmpty) ...[
                      const Text('Select store',
                        style: TextStyle(fontSize: 12, color: _muted,
                            fontWeight: FontWeight.w600)),
                      const SizedBox(height: 7),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 13),
                        decoration: _panelDecoration(),
                        child: DropdownButtonFormField<String>(
                          initialValue: chosen,
                          isExpanded: true,
                          decoration: const InputDecoration(border: InputBorder.none),
                          items: [for (final shop in shops)
                            DropdownMenuItem(value: shop.id,
                              child: Text((shop.data()['name'] ?? 'Souvenir Shop').toString(),
                                  maxLines: 1, overflow: TextOverflow.ellipsis))],
                          onChanged: (value) => setState(() {
                            _shopId = value;
                            _category = 'All';
                          }),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Container(decoration: _panelDecoration(),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _search = value),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Search souvenirs',
                          prefixIcon: Icon(Icons.search, color: _muted),
                          contentPadding: EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                    if (categories.length > 1) ...[
                      const SizedBox(height: 12),
                      SingleChildScrollView(scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (final category in categories)
                            Padding(padding: const EdgeInsets.only(right: 7),
                              child: ChoiceChip(label: Text(category),
                                selected: category == activeCategory,
                                selectedColor: const Color(0xFFF3D5D3),
                                onSelected: (_) => setState(() => _category = category))),
                        ])),
                    ],
                    const SizedBox(height: 15),
                    Row(children: [
                      const Expanded(child: Text('Available Souvenirs',
                        style: TextStyle(fontSize: 16,
                            color: _ink, fontWeight: FontWeight.w800))),
                      Text('${filtered.length} items',
                        style: const TextStyle(color: _muted, fontSize: 12)),
                    ]),
                  ],
                ),
              )),
              if (filtered.isEmpty)
                SliverFillRemaining(hasScrollBody: false,
                  child: _emptyState(Icons.inventory_2_outlined,
                      'Nothing to show',
                      'Try another shop, category or search.'))
              else SliverPadding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
                sliver: SliverLayoutBuilder(builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;
                  return SliverGrid.builder(
                    itemCount: filtered.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: width < 340 ? 1 : 2,
                      mainAxisExtent: 280,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                    itemBuilder: (context, index) => _productCard(filtered[index]),
                  );
                }),
              ),
            ])),
            if (count > 0)
              SafeArea(top: false, child: Container(
                decoration: const BoxDecoration(color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFF0E1DE)))),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                child: Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$count item${count == 1 ? '' : 's'} in cart',
                          style: const TextStyle(fontSize: 11, color: _muted)),
                      Text(_money(amount), style: const TextStyle(fontSize: 18,
                          fontWeight: FontWeight.w800, color: _ink)),
                    ]),
                  const SizedBox(width: 14),
                  Expanded(child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _rose,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                    onPressed: _busy || _pendingPaymentId != null
                        ? null : () => _checkout(all),
                    icon: const Icon(Icons.lock_outline, size: 18),
                    label: const Text('Checkout'),
                  )),
                ]),
              )),
          ]);
        },
      );
    },
  );
}


// PARKSMART_REFUND_FORM_V18: validated form keeps network errors visible in dialog.
class _ParkSmartRefundRequestDialogV18 extends StatefulWidget {
  const _ParkSmartRefundRequestDialogV18({
    required this.client,
    required this.orderId,
  });

  final StripeCommerceClient client;
  final String orderId;

  @override
  State<_ParkSmartRefundRequestDialogV18> createState() =>
      _ParkSmartRefundRequestDialogV18State();
}

class _ParkSmartRefundRequestDialogV18State
    extends State<_ParkSmartRefundRequestDialogV18> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  bool _submitting = false;
  String? _serverError;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _serverError = null;
    });
    try {
      final result = await widget.client.requestSouvenirRefund(
        widget.orderId,
        _reason.text.trim(),
      );
      if (!mounted) return;
      final status = (result['status'] ?? '').toString();
      if (['requested', 'processing', 'approved', 'needs_review']
          .contains(status)) {
        Navigator.of(context).pop(status);
      } else {
        setState(() => _serverError =
            'Unexpected refund response. Please check your order status.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _serverError =
            'Request could not be submitted: $error');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Request a Souvenir Refund'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tell us why you are requesting a refund. '
                'An administrator must approve your request before Stripe '
                'will process a refund.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reason,
                enabled: !_submitting,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reason *',
                  helperText: 'Required · 8–500 characters',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  final reason = (value ?? '').trim();
                  if (reason.isEmpty) return 'Reason is required.';
                  if (reason.length < 8) {
                    return 'Please provide at least 8 characters.';
                  }
                  if (reason.length > 500) {
                    return 'Reason must not exceed 500 characters.';
                  }
                  return null;
                },
              ),
              if (_serverError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _serverError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Back'),
      ),
      FilledButton(
        onPressed: _submitting ? null : _submit,
        child: _submitting
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Submitting...'),
                ],
              )
            : const Text('Submit Request'),
      ),
    ],
  );
}
