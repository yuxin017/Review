import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tickets.dart';
import 'rewards_repository.dart';
import '../../services/application_api.dart';

abstract class TicketRepository {
  String? get userId;
  Stream<List<TicketPackage>> packages();
  Stream<List<ParkTicket>> tickets();
  Stream<List<TicketOrder>> orders();
  Future<void> checkout(TicketCheckout request);
  Future<String> startHostedPayment(TicketCheckout request) =>
      throw UnsupportedError('Hosted payment is unavailable.');
  Future<String> hostedPaymentStatus(String orderId) =>
      throw UnsupportedError('Hosted payment verification is unavailable.');
  Future<Map<String, dynamic>> promotionQuote(
    TicketCheckout request, {
    String paymentCurrency = 'MYR',
  }) => Future.value({'discountMinor': 0, 'allowPoints': true});
  Stream<BookingProfile> profile() => Stream.value(const BookingProfile());
  Future<ParkTicket> findTicket(String code) =>
      throw StateError('This ticket could not be found.');
  Future<bool> orderExists(String id) => Future.value(false);
}

class FirebaseTicketRepository implements TicketRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  @override
  String? get userId => FirebaseAuth.instance.currentUser?.uid;
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  // Enable only for LOCAL Stripe Sandbox demos (no Firebase Blaze required):
  // flutter run -d chrome --dart-define=LOCAL_STRIPE_API=http://127.0.0.1:8788
  static const _configuredLocalStripeApi = String.fromEnvironment('LOCAL_STRIPE_API');

  static String get _localStripeApi =>
      _configuredLocalStripeApi.isNotEmpty
          ? _configuredLocalStripeApi
          : (kIsWeb &&
                  (Uri.base.host == 'localhost' ||
                      Uri.base.host == '127.0.0.1')
              ? 'http://127.0.0.1:8788'
              : '');

  Future<Map<String, dynamic>> _callPayment(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    if (_localStripeApi.isEmpty) {
      final result = await _functions.httpsCallable(functionName).call(data);
      return Map<String, dynamic>.from(result.data as Map);
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Please sign in before checkout.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Your session has expired. Please sign in again.');
    }
    final response = await http.post(
      Uri.parse('$_localStripeApi/$functionName'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 35));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw StateError('Payment service returned an invalid response.');
    }
    final result = Map<String, dynamic>.from(decoded);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        result['error'] as String? ??
            'Unable to connect to payment service. Please try again.',
      );
    }
    return result;
  }
  @override
  Future<Map<String, dynamic>> promotionQuote(
    TicketCheckout request, {
    String paymentCurrency = 'MYR',
  }) async {
    if (paymentCurrency != 'MYR') {
      throw StateError('Online payment currently supports MYR only.');
    }
    return _callPayment('stripeTicketQuote', {
      ...request.toMap(),
      'paymentCurrency': 'MYR',
    });
  }
  @override
  Future<String> startHostedPayment(TicketCheckout request) async {
    const mobileReturn = String.fromEnvironment('PAYMENT_RETURN_URL');
    final returnUrl = kIsWeb ? Uri.base.origin : mobileReturn;
    if (returnUrl.isEmpty) {
      throw StateError('Set PAYMENT_RETURN_URL to your Firebase Hosting website.');
    }
    final data = await _callPayment('stripeTicketCheckout', {
      ...request.toMap(),
      'clientFingerprint': request.fingerprint,
      'expectedTotalMinor': request.total,
      'paymentCurrency': 'MYR',
      'returnUrl': returnUrl,
    });
    if (data['status'] == 'paid') return 'paid';
    return data['url'] as String? ?? '';
  }
  @override
  Future<String> hostedPaymentStatus(String orderId) async {
    final data = await _callPayment('stripeTicketStatus', {'orderId': orderId});
    return data['status'] as String? ?? 'pending';
  }
  @override
  Future<bool> orderExists(String id) async =>
      (await _db
              .collection('orders')
              .doc(id)
              .get(const GetOptions(source: Source.server)))
          .exists;
  @override
  Stream<BookingProfile> profile() =>
      _db.collection('visitors').doc(userId).snapshots().map((snapshot) {
        final data = snapshot.data() ?? {};
        return BookingProfile(
          uid: userId ?? '',
          fullName: data['fullName'] as String? ?? '',
          email:
              data['email'] as String? ??
              FirebaseAuth.instance.currentUser?.email ??
              '',
          points: (data['loyaltyPoints'] as num?)?.toInt() ?? 0,
        );
      });
  @override
  Future<ParkTicket> findTicket(String code) async {
    var id = code.trim();
    if (id.startsWith('TP1:')) id = id.substring(4);
    if (id.startsWith('TP-')) {
      final reference = await _db
          .collection('ticketReferences')
          .doc(id.toUpperCase())
          .get();
      id = reference.data()?['ticketId'] as String? ?? '';
    }
    if (!RegExp(r'^[a-f0-9]{48}_([1-9]|10)$').hasMatch(id)) {
      throw StateError(
        'This ticket could not be found. Check the ticket ID or scan its QR code again.',
      );
    }
    final snapshot = await _db.collection('tickets').doc(id).get();
    if (!snapshot.exists) throw StateError('This ticket could not be found.');
    final ticket = ParkTicket.fromMap(snapshot.id, snapshot.data()!);
    if (ticket.filter != 'Upcoming') {
      throw StateError('This ticket has already been used or has expired.');
    }
    return ticket;
  }

  @override
  Stream<List<TicketPackage>> packages() => _db
      .collection('ticketPackages')
      .where('active', isEqualTo: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => TicketPackage.fromMap(doc.id, doc.data()))
            .where((pack) => pack.currency == 'MYR')
            .toList(),
      );
  @override
  Stream<List<ParkTicket>> tickets() => _db
      .collection('tickets')
      .where(
        Filter.or(
          Filter('ownerUid', isEqualTo: userId),
          Filter(
            'guestEmail',
            isEqualTo:
                FirebaseAuth.instance.currentUser?.email?.toLowerCase() ?? '',
          ),
        ),
      )
      .snapshots()
      .map((snapshot) {
        final result = snapshot.docs
            .map((doc) => ParkTicket.fromMap(doc.id, doc.data()))
            .toList();
        result.sort(
          (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
            a.createdAt ?? DateTime(1970),
          ),
        );
        return result;
      });
  @override
  Stream<List<TicketOrder>> orders() => _db
      .collection('orders')
      .where('ownerUid', isEqualTo: userId)
      .snapshots()
      .map((snapshot) {
        final result = snapshot.docs
            .map((doc) => TicketOrder.fromMap(doc.id, doc.data()))
            .toList();
        result.sort(
          (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
            a.createdAt ?? DateTime(1970),
          ),
        );
        return result;
      });
  @override
  Future<void> checkout(TicketCheckout request) async {
    throw StateError('Use the secure Stripe payment page to purchase tickets.');
  }

  Future<void> _checkoutJourney(TicketCheckout request) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _fail('unauthenticated', 'Please sign in before checkout.');
    }
    if (!user.emailVerified) {
      _fail('permission-denied', 'Verify your email before checkout.');
    }
    if (!RegExp(r'^[a-f0-9]{48}$').hasMatch(request.requestId) ||
        request.quantity < 1 ||
        request.quantity > 10 ||
        request.lines.length > 5 ||
        request.guests.length != request.quantity ||
        !request.guests.every((g) => g.complete) ||
        ![
          'card',
          'fpx',
          'touch-go',
          'apple-pay',
          'nfc',
        ].contains(request.paymentMethod) ||
        request.pointsUsed < 0 ||
        request.pointsUsed % 100 != 0) {
      _fail(
        'invalid-argument',
        'Check the selected tickets and guest details.',
      );
    }
    final orderRef = _db.collection('orders').doc(request.requestId);
    await _db.runTransaction((transaction) async {
      final previous = await transaction.get(orderRef);
      if (previous.exists) {
        if (previous.data()!['ownerUid'] != user.uid ||
            previous.data()!['fingerprint'] != request.fingerprint) {
          _fail(
            'already-exists',
            'This checkout reference belongs to another booking.',
          );
        }
        return;
      }
      final packs = <String, TicketPackage>{};
      for (final id in request.lines.map((l) => l.packageId).toSet()) {
        if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(id)) {
          _fail('invalid-argument', 'Choose a valid pass.');
        }
        final doc = await transaction.get(
          _db.collection('ticketPackages').doc(id),
        );
        if (!doc.exists || doc.data()!['active'] != true) {
          _fail(
            'failed-precondition',
            'A selected pass is no longer available.',
          );
        }
        packs[id] = TicketPackage.fromMap(id, doc.data()!);
      }
      DocumentSnapshot<Map<String, dynamic>>? profileDoc;
      final earningRules = await transaction.get(
        _db.collection('parkSettings').doc('loyalty'),
      );
      final earningRate = earningRules.data()?['purchasePointsPerRinggit'] ?? 1;
      if (earningRate is! int || earningRate < 0 || earningRate > 100) {
        _fail(
          'failed-precondition',
          'The points earning rules need an administrator review.',
        );
      }
      if (request.pointsUsed > 0) {
        profileDoc = await transaction.get(
          _db.collection('visitors').doc(user.uid),
        );
        final balance =
            (profileDoc.data()?['loyaltyPoints'] as num?)?.toInt() ?? 0;
        if (request.pointsUsed > balance ||
            request.pointsUsed > request.subtotal) {
          _fail(
            'failed-precondition',
            'Your points balance has changed. Please review your order.',
          );
        }
      }
      final items = <Map<String, dynamic>>[];
      final seenGuests = <String>{};
      for (final line in request.lines) {
        final pack = packs[line.packageId]!;
        final date = DateTime.tryParse(line.visitDate);
        final today = parkToday();
        if (date == null ||
            visitDateString(date) != line.visitDate ||
            date.isBefore(today) ||
            date.isAfter(today.add(const Duration(days: 365))) ||
            line.adults < 0 ||
            line.children < 0 ||
            line.quantity < 1 ||
            pack.currency != 'MYR' ||
            line.adultPriceMinor != pack.priceMinor ||
            line.childPriceMinor != pack.childPrice ||
            line.durationDays != pack.durationDays ||
            line.packageName != pack.name) {
          _fail(
            'failed-precondition',
            'A selected pass or its price has changed. Please review your cart.',
          );
        }
        final guests = request.guests
            .where((g) => g.lineId == line.id)
            .toList();
        if (guests.length != line.quantity ||
            guests.where((g) => g.type == 'adult').length != line.adults ||
            guests.where((g) => g.type == 'child').length != line.children) {
          _fail('invalid-argument', 'Check the guest details for each pass.');
        }
        for (final guest in guests) {
          if (!seenGuests.add(guest.id)) {
            _fail('invalid-argument', 'Each guest needs their own ticket.');
          }
          items.add({
            'packageId': pack.id,
            'packageName': pack.name,
            'visitDate': line.visitDate,
            'validUntil': visitDateString(
              date.add(Duration(days: pack.durationDays - 1)),
            ),
            'durationDays': pack.durationDays,
            'ticketType': guest.type,
            'guestName': guest.fullName.trim(),
            'guestEmail': guest.email.trim().toLowerCase(),
            'unitPriceMinor': guest.type == 'child'
                ? pack.childPrice
                : pack.priceMinor,
          });
        }
      }
      final ids = List.generate(
        items.length,
        (i) => '${request.requestId}_${i + 1}',
      );
      transaction.set(orderRef, {
        'version': 2,
        'ownerUid': user.uid,
        'requestId': request.requestId,
        'fingerprint': request.fingerprint,
        'packageId': request.packageId,
        'packageName': request.lines.length == 1
            ? request.lines.first.packageName
            : 'Theme Park Tickets',
        'visitDate': request.visitDate,
        'quantity': request.quantity,
        'ticketIds': ids,
        'items': items,
        'lineItems': request.lines.map((l) => l.toMap()).toList(),
        'subtotalMinor': request.subtotal,
        'pointsUsed': request.pointsUsed,
        'loyaltyEarnRate': earningRate,
        'totalMinor': request.total,
        'paymentMethod': request.paymentMethod,
        'cardLast4': request.paymentMethod == 'card' ? request.cardLast4 : '',
        'currency': 'MYR',
        'status': 'completed',
        'displayCode': bookingReference(request.requestId, request.visitDate),
        'createdAt': FieldValue.serverTimestamp(),
      });
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final code =
            '${bookingReference(request.requestId, item['visitDate'] as String)}-${(i + 1).toString().padLeft(2, '0')}';
        transaction.set(_db.collection('tickets').doc(ids[i]), {
          ...item,
          'item': item,
          'version': 2,
          'index': i,
          'ownerUid': user.uid,
          'purchaserUid': user.uid,
          'orderId': request.requestId,
          'displayCode': code,
          'currency': 'MYR',
          'status': 'valid',
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.set(_db.collection('ticketReferences').doc(code), {
          'ticketId': ids[i],
          'ownerUid': user.uid,
          'guestEmail': item['guestEmail'],
        });
      }
      if (profileDoc != null) {
        transaction.update(profileDoc.reference, {
          'loyaltyPoints':
              (profileDoc.data()!['loyaltyPoints'] as int) - request.pointsUsed,
          'lastRedemptionOrderId': request.requestId,
        });
      }
    });
  }

  Never _fail(String code, String message) => throw FirebaseException(
    plugin: 'cloud_firestore',
    code: code,
    message: message,
  );
}

class PendingTicketCheckoutStore {
  String _key(String uid) => 'pending_ticket_checkout_$uid';
  Future<TicketCheckout?> load(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key(uid));
    if (value == null) return null;
    try {
      return TicketCheckout.fromMap(
        Map<String, dynamic>.from(jsonDecode(value) as Map),
      );
    } catch (_) {
      await prefs.remove(_key(uid));
      return null;
    }
  }

  Future<void> save(String uid, TicketCheckout request) async =>
      (await SharedPreferences.getInstance()).setString(
        _key(uid),
        jsonEncode(request.toMap()),
      );
  Future<void> clear(String uid) async =>
      (await SharedPreferences.getInstance()).remove(_key(uid));
}
