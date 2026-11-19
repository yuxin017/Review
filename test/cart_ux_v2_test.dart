import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collaborative_asg/visitor/models/tickets.dart';
import 'package:collaborative_asg/visitor/services/ticket_repository.dart';
import 'package:collaborative_asg/visitor/services/ticket_journey.dart';
import 'package:collaborative_asg/visitor/pages/ticket_checkout_screens.dart';

class CartFixtureRepository extends TicketRepository {
  final packageStream = StreamController<List<TicketPackage>>.broadcast();
  @override
  String? get userId => 'cart_fixture';
  @override
  Stream<List<TicketPackage>> packages() => packageStream.stream;
  @override
  Stream<List<ParkTicket>> tickets() => Stream.value([]);
  @override
  Stream<List<TicketOrder>> orders() => Stream.value([]);
  @override
  Future<void> checkout(TicketCheckout request) async {}
  @override
  Stream<BookingProfile> profile() => Stream.value(const BookingProfile());
  void emitActive() => packageStream.add(const [
    TicketPackage(id: 'day', name: 'Day Pass', priceMinor: 14000,
      childPriceMinor: 11000),
  ]);
  Future<void> close() async => packageStream.close();
}

TicketCartLine fixture({String? date, String id = 'line'}) => TicketCartLine(
  id: id,
  packageId: 'day',
  packageName: 'Day Pass',
  visitDate: date ?? visitDateString(parkToday()),
  adults: 1,
  children: 0,
  adultPriceMinor: 14000,
  childPriceMinor: 11000,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('past dates are removed and guest records follow the new cart', () async {
    final repo = CartFixtureRepository();
    final j = TicketJourney(repo, PendingTicketCheckoutStore());
    addTearDown(() async { j.dispose(); await repo.close(); });
    await j.start();
    repo.emitActive();
    await Future<void>.delayed(Duration.zero);
    j.add(fixture());
    final tomorrow = parkToday().add(const Duration(days: 1));
    final count = j.pruneUnavailableCartLines(
      today: tomorrow.add(const Duration(days: 1)),
    );
    expect(count, 1);
    expect(j.cart, isEmpty);
    expect(j.guests, isEmpty);
    expect(j.cartNotice, contains('expired'));
  });

  test('inactive packages disappear from an uncommitted cart', () async {
    final repo = CartFixtureRepository();
    final j = TicketJourney(repo, PendingTicketCheckoutStore());
    addTearDown(() async { j.dispose(); await repo.close(); });
    await j.start();
    repo.emitActive();
    await Future<void>.delayed(Duration.zero);
    j.add(fixture());
    repo.packageStream.add([]);
    await Future<void>.delayed(Duration.zero);
    expect(j.cart, isEmpty);
    expect(j.cartNotice, contains('unavailable'));
  });

  test('editing date and guest counts updates total and guest slots', () async {
    final repo = CartFixtureRepository();
    final j = TicketJourney(repo, PendingTicketCheckoutStore());
    addTearDown(() async { j.dispose(); await repo.close(); });
    await j.start();
    repo.emitActive();
    await Future<void>.delayed(Duration.zero);
    j.add(fixture());
    final tomorrow = parkToday().add(const Duration(days: 1));
    j.updateCartLine('line', tomorrow, 2, 1);
    expect(j.cart.single.visitDate, visitDateString(tomorrow));
    expect(j.cart.single.quantity, 3);
    expect(j.guests.length, 3);
    expect(j.subtotal, 39000);
    expect(j.termsAccepted, false);
  });

  testWidgets('Cart offers inline editing and saves updated quantities',
      (tester) async {
    final repo = CartFixtureRepository();
    final j = TicketJourney(repo, PendingTicketCheckoutStore());
    addTearDown(() async { j.dispose(); await repo.close(); });
    await j.start();
    repo.emitActive();
    await tester.pump();
    j.add(fixture());
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: TicketCartScreen(journey: j, onShop: () {}, onCheckout: () {}),
    )));
    await tester.pump();
    await tester.tap(find.byKey(const Key('cart-date-line')));
    await tester.pumpAndSettle();
    expect(find.text('Save Changes'), findsOneWidget);
    await tester.tap(find.byTooltip('More adults'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(j.cart.single.adults, 2);
  });
}
