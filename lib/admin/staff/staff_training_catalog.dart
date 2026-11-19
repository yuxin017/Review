import 'package:cloud_firestore/cloud_firestore.dart';

import 'staff_access.dart';

/// Park-controlled course catalogue. A course is defined ONCE and then selected
/// when staff training is recorded. No ad-hoc qualification titles are entered
/// on an individual employee's training form.
class StaffTrainingCourse {
  const StaffTrainingCourse({
    required this.id,
    required this.title,
    required this.role,
    required this.active,
    required this.attractionId,
  });

  final String id;
  final String title;
  final StaffRole role;
  final bool active;
  /// Bound ONCE in the course catalogue, never chosen per employee.
  final String attractionId;

  bool get needsRideLink =>
      role == StaffRole.attractionOperator && attractionId.isEmpty;

  factory StaffTrainingCourse.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final role = StaffRole.fromCode(data['roleCode']?.toString() ?? '');
    if (role == null || role == StaffRole.superAdmin) {
      throw const FormatException('Select a valid role.');
    }
    return StaffTrainingCourse(
      id: doc.id,
      title: data['title']?.toString() ?? '',
      role: role,
      active: data['active'] == true,
      attractionId: data['attractionId']?.toString() ?? '',
    );
  }
}

class StaffTrainingCatalogRepository {
  const StaffTrainingCatalogRepository(this.db);
  final FirebaseFirestore db;

  CollectionReference<Map<String, dynamic>> get _collection =>
      db.collection('staffTrainingCourses');

  Stream<List<StaffTrainingCourse>> watchCourses() =>
      _collection.snapshots().map((snapshot) {
        final courses = snapshot.docs
            .map(StaffTrainingCourse.fromDocument)
            .toList();
        courses.sort((a, b) => a.title.compareTo(b.title));
        return courses;
      });

  Future<List<StaffTrainingCourse>> activeCourses() async {
    final snapshot = await _collection.where('active', isEqualTo: true).get();
    final courses = snapshot.docs.map(StaffTrainingCourse.fromDocument).toList();
    courses.sort((a, b) => a.title.compareTo(b.title));
    return courses;
  }

  Future<void> createCourse({
    required String title,
    required StaffRole role,
    String attractionId = '',
  }) async {
    final cleaned = title.trim();
    if (cleaned.length < 4 || cleaned.length > 120) {
      throw ArgumentError('Enter a valid course name.');
    }
    if (role == StaffRole.superAdmin) {
      throw ArgumentError('Select a different role.');
    }
    final boundRide = role == StaffRole.attractionOperator
        ? attractionId.trim() : '';
    if (role == StaffRole.attractionOperator) {
      await _checkRide(boundRide);
    }
    final matching = await _collection.where('roleCode', isEqualTo: role.code).get();
    if (matching.docs.any((doc) =>
        (doc.data()['title']?.toString().toLowerCase() ?? '') ==
        cleaned.toLowerCase())) {
      throw ArgumentError('This course already exists.');
    }
    await _collection.add({
      'title': cleaned,
      'roleCode': role.code,
      'attractionId': boundRide,
      'active': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// For courses created before ride linking existed. One-time link only.
  /// A linked course cannot silently switch rides; archive it instead.
  Future<void> linkExistingRide(StaffTrainingCourse course, String rideId) async {
    if (course.role != StaffRole.attractionOperator ||
        course.attractionId.isNotEmpty) {
      throw ArgumentError('This course already has a ride.');
    }
    await _checkRide(rideId);
    // Read again to avoid overwriting an already-bound course.
    await db.runTransaction((transaction) async {
      final ref = _collection.doc(course.id);
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists ||
          snapshot.data()?['roleCode'] != StaffRole.attractionOperator.code ||
          (snapshot.data()?['attractionId']?.toString() ?? '').isNotEmpty) {
        throw ArgumentError('This course already has a ride.');
      }
      transaction.update(ref, {
        'attractionId': rideId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _checkRide(String rideId) async {
    if (rideId.isEmpty || rideId.contains('/')) {
      throw ArgumentError('Select an attraction.');
    }
    final ride = await db.collection('attractions').doc(rideId).get();
    if (!ride.exists || ride.data()?['deletedAt'] != null) {
      throw ArgumentError('Select an available attraction.');
    }
  }

  Future<void> setActive(StaffTrainingCourse course, bool active) async {
    if (active && course.needsRideLink) {
      throw ArgumentError('Link an attraction first.');
    }
    await _collection.doc(course.id).update({
      'attractionId': course.attractionId,
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
