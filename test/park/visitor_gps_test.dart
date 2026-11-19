import 'package:flutter_test/flutter_test.dart';
import 'package:collaborative_asg/park/visitor_gps.dart';

void main() {
  test('Configured TAR UMT Penang center is inside the campus bounding area', () {
    expect(VisitorGps.inside(5.45235045, 100.28507965), isTrue);
  });
  test('Far-away position is never treated as on campus', () {
    expect(VisitorGps.inside(50.4501, 30.5234), isFalse);
    expect(VisitorGps.inside(5.4164, 100.3327), isFalse);
  });
}
