import 'package:flutter_test/flutter_test.dart';
import 'package:collaborative_asg/attractions/models/attraction.dart';

void main() {
  Attraction ride({int? minutes = 4, int? riders = 24}) => Attraction(
        id: 'ride_test',
        name: 'Ferris Wheel',
        category: 'Family rides',
        status: AttractionStatus.closed,
        minHeightCm: 110,
        mapX: .4,
        mapY: .6,
        description: 'Scenic family attraction',
        rideDurationMinutes: minutes,
        ridersPerCycle: riders,
        safetyNotes: 'Stay seated.',
      );

  test('ride details persist without overwriting map coordinates', () {
    final original = ride();
    final restored = Attraction.fromMap(original.id, original.toMap());
    expect(restored.rideDurationMinutes, 4);
    expect(restored.ridersPerCycle, 24);
    expect(restored.safetyNotes, 'Stay seated.');
    expect(restored.mapX, .4);
    expect(restored.mapY, .6);
  });

  test('invalid equipment limits are rejected', () {
    expect(() => ride(minutes: 0), throwsArgumentError);
    expect(() => ride(riders: 0), throwsArgumentError);
    expect(() => ride(minutes: 121), throwsArgumentError);
  });

  test('existing attractions without new details still load', () {
    final original = ride(minutes: null, riders: null);
    final restored = Attraction.fromMap(original.id, original.toMap());
    expect(restored.rideDurationMinutes, null);
    expect(restored.ridersPerCycle, null);
  });
}
