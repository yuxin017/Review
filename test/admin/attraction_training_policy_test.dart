import 'package:flutter_test/flutter_test.dart';
import '../../lib/admin/attractions/data/attraction_training_store.dart';

void main() {
  test('one attraction has a stable required course ID', () {
    expect(AttractionTrainingPolicy.courseId('abc123'), 'ride_abc123');
    expect(AttractionTrainingPolicy.courseId('abc123'), 'ride_abc123');
  });
  test('the operator training name follows the attraction name', () {
    expect(AttractionTrainingPolicy.defaultTitle(' Ferris Wheel '),
        'Ferris Wheel Operation & Safety Training');
    expect(AttractionTrainingPolicy.validateTitle(
        AttractionTrainingPolicy.defaultTitle('Carousel')), isNull);
  });
  test('course names must be meaningful and fit the catalogue', () {
    expect(AttractionTrainingPolicy.validateTitle('abc'), isNotNull);
    expect(AttractionTrainingPolicy.validateTitle(List.filled(121, 'X').join()), isNotNull);
    expect(AttractionTrainingPolicy.validateTitle('Bumper Cars Training'), isNull);
  });
}
