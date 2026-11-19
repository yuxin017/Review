import 'package:flutter_test/flutter_test.dart';
import 'package:collaborative_asg/admin/cameras/crowdsense_engine.dart';

CrowdSenseMetric metric(int index, int count, {bool closed = false}) =>
    CrowdSenseMetric(
      zone: CrowdSenseZone(
        id: 'test_$index',
        name: 'Test $index',
        mapX: 0.5,
        mapY: 0.5,
        isDemo: true,
      ),
      count: count,
      capacity: 3,
      isLive: false,
      closed: closed,
    );

void main() {
  test('route changes when area A becomes congested', () {
    final original = CrowdSenseRouter.compute([
      metric(0, 0), metric(1, 1), metric(2, 1), metric(3, 0),
    ]);
    final congested = CrowdSenseRouter.compute([
      metric(0, 6), metric(1, 1), metric(2, 1), metric(3, 0),
    ]);
    expect(original, isNotNull);
    expect(congested, isNotNull);
    expect(original!.nodeIds, contains(0));
    expect(congested!.nodeIds, isNot(contains(0)));
    expect(congested.nodeIds, contains(1));
  });

  test('closed zones are excluded', () {
    final route = CrowdSenseRouter.compute([
      metric(0, 0), metric(1, 1, closed: true),
      metric(2, 1), metric(3, 0),
    ]);
    expect(route, isNotNull);
    expect(route!.nodeIds, isNot(contains(1)));
  });

  test('short timelines do not produce a fake prediction', () {
    final now = DateTime.utc(2026, 11, 13);
    expect(CrowdSenseRouter.predict30Seconds([
      CrowdSensorReading(1, now),
      CrowdSensorReading(2, now.add(const Duration(seconds: 1))),
    ], 3), isNull);
  });
}
