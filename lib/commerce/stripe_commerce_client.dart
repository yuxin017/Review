import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Calls the authenticated local Stripe TEST server on the presentation PC.
/// Android devices require a separately configured reachable HTTPS endpoint.
/// No card credentials are handled or stored by the app.
class StripeCommerceClient {
  StripeCommerceClient({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth _auth;
  static const configuredBase = String.fromEnvironment('LOCAL_STRIPE_API');
  static const mobileReturnUrl = String.fromEnvironment('PAYMENT_RETURN_URL');

  String get base {
    if (configuredBase.isNotEmpty) return configuredBase.replaceAll(RegExp(r'/$'), '');
    if (kIsWeb && ['localhost','127.0.0.1'].contains(Uri.base.host)) {
      return 'http://127.0.0.1:8788';
    }
    throw StateError('Payment API unavailable on this device. Configure a secure reachable Stripe backend.');
  }

  String get returnUrl {
    if (kIsWeb) return Uri.base.origin;
    if (mobileReturnUrl.isNotEmpty) return mobileReturnUrl;
    throw StateError('Set PAYMENT_RETURN_URL to an authorised HTTPS return address.');
  }

  Future<Map<String, dynamic>> post(String action, Map<String, dynamic> values) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in before checkout.');
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) throw StateError('Sign in again.');
    final response = await http.post(
      Uri.parse('$base/$action'),
      headers: {'Content-Type':'application/json','Authorization':'Bearer $idToken'},
      body: jsonEncode(values),
    ).timeout(const Duration(seconds: 35));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw StateError('Payment service returned invalid data.');
    final result = Map<String,dynamic>.from(decoded);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(result['error']?.toString() ?? 'Payment service rejected the request.');
    }
    return result;
  }

  Future<Map<String,dynamic>> shopQuote(List<Map<String,dynamic>> items) =>
      post('stripeSouvenirQuote', {'items':items});

  Future<Map<String,dynamic>> checkout(String type, String requestId,
      Map<String,dynamic> payload) => post('stripeCommerceCheckout', {
        ...payload, 'type':type, 'requestId':requestId, 'returnUrl':returnUrl,
      });

  Future<Map<String,dynamic>> status(String orderId) =>
      post('stripeCommerceStatus', {'orderId':orderId});

  // PARKSMART_V15_PAYMENT_CROWD: verified server-only payment operations.
  Future<Map<String, dynamic>> cancel(String orderId) =>
      post('stripeCommerceCancel', {'orderId': orderId});

  // PARKSMART_V16_REFUND_CROWD_HISTORY
  Future<Map<String,dynamic>> requestSouvenirRefund(String orderId, String reason) =>
      post('stripeSouvenirRefundRequest', {'orderId':orderId,'reason':reason});

  Future<Map<String,dynamic>> reviewSouvenirRefund(String orderId, String decision) =>
      post('stripeSouvenirRefundDecision', {'orderId':orderId,'decision':decision});

  Future<Map<String,dynamic>> recoverCheckout(String requestId) =>
      post('stripeCommerceRecover', {'type':'souvenir','requestId':requestId});

  Future<void> openCheckout(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' ||
        uri.host != 'checkout.stripe.com') {
      throw StateError('Payment service returned an unsafe payment address.');
    }
    // PARKSMART_V16_REFUND_CROWD_HISTORY: web uses current tab, not an extra browser tab.
    final opened = kIsWeb
        ? await launchUrl(uri, mode: LaunchMode.platformDefault, webOnlyWindowName: '_self')
        : await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      throw StateError('Could not open the secure checkout page.');
    }
  }
}
