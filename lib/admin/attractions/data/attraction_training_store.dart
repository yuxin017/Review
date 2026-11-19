import '../../../attractions/models/attraction.dart';

/// Extra capabilities used by the attraction editor without changing the
/// pre-existing AdminAttractionStore interface or its test fakes.
abstract class AttractionTrainingStore {
  /// Saves the ride and its operator course in one Firestore transaction.
  Future<void> createAttractionWithTraining(
    Attraction attraction, {
    required String courseTitle,
  });

  /// Names of courses linked to an existing attraction.
  Stream<List<String>> watchRequiredTraining(String attractionId);

  /// For rides that existed before the automatic course feature.
  Future<void> addRequiredTrainingToExistingRide(
    String attractionId, {
    required String courseTitle,
  });
}

class AttractionTrainingPolicy {
  const AttractionTrainingPolicy._();

  static String defaultTitle(String rideName) =>
      '${rideName.trim()} Operation & Safety Training';

  static String courseId(String attractionId) => 'ride_$attractionId';

  static String? validateTitle(String? value) {
    final title = (value ?? '').trim();
    return title.length < 4 || title.length > 120
        ? 'Enter a course name (4–120 characters).'
        : null;
  }
}
