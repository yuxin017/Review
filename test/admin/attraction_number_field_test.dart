import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:collaborative_asg/admin/attractions/attraction_number_field.dart';

void main() {
  testWidgets('plus/minus updates value and never exceeds bounds', (tester) async {
    final controller = TextEditingController(text: '9');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Form(child: AttractionNumberField(
        controller: controller,
        label: 'Riders',
        min: 1,
        max: 10,
      ))),
    ));
    await tester.tap(find.byKey(const Key('increase-Riders')));
    await tester.pump();
    expect(controller.text, '10');
    await tester.tap(find.byKey(const Key('increase-Riders')));
    await tester.pump();
    expect(controller.text, '10');
    await tester.tap(find.byKey(const Key('decrease-Riders')));
    await tester.pump();
    expect(controller.text, '9');
  });

  testWidgets('empty optional field accepted; out of range shows inline error', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Form(key: formKey, child: AttractionNumberField(
        controller: controller,
        label: 'Ride duration',
        min: 1,
        max: 120,
        optional: true,
      ))),
    ));
    expect(formKey.currentState!.validate(), isTrue);
    controller.text = '121';
    await tester.pump();
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Use 1–120.'), findsOneWidget);
  });
}
