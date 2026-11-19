import 'package:flutter_test/flutter_test.dart';
import 'package:collaborative_asg/admin/attractions/data/park_category_repository.dart';
import 'package:collaborative_asg/attractions/models/attraction.dart';

void main() {
  test('Category validation is short and clear', () {
    expect(ParkCategoryRepository.validateName(''),
        'Enter a category name.');
    expect(ParkCategoryRepository.validateName('W'),
        'Enter at least 2 characters.');
    expect(ParkCategoryRepository.validateName('Western'), isNull);
    expect(ParkCategoryRepository.validateName('Family Rides'), isNull);
  });

  test('Western food does not become a ride', () {
    final food = Attraction(
      id: 'food-1',
      name: 'Pasta Corner',
      category: 'Western',
      categoryId: 'western-1',
      placeKind: ParkPlaceKind.dining,
      status: AttractionStatus.closed,
      minHeightCm: 0,
      mapX: .5,
      mapY: .5,
    );
    expect(food.isRide, isFalse);
    expect(food.placeKind, ParkPlaceKind.dining);
    expect(food.toMap()['kind'], 'dining');
    expect(food.toMap()['categoryId'], 'western-1');
    final reread = Attraction.fromMap('food-1', food.toMap());
    expect(reread.placeKind, ParkPlaceKind.dining);
    expect(reread.category, 'Western');
    expect(reread.isRide, isFalse);
  });

  test('Legacy data without kind is still supported', () {
    final item = Attraction.fromMap('legacy-1', {
      'name': 'Old Carousel',
      'category': 'Family rides',
      'status': 'closed',
      'minHeightCm': 0,
      'mapX': .2,
      'mapY': .3,
    });
    expect(item.placeKind, ParkPlaceKind.attractions);
    expect(item.categoryId, isNull);
  });
}
