import 'package:cloud_firestore/cloud_firestore.dart';

import 'staff_access.dart';
import 'staff_form_validation.dart';
import 'staff_role_rules.dart';
import 'staff_records.dart';
import 'staff_training_batch_policy.dart';

/// Firebase storage for staff records. Must be created with the STAFF/ADMIN
/// FirebaseFirestore instance from the existing AdminFirebase service.
///
/// Security: these methods are only a client wrapper. Firestore Security Rules
/// must authorize every read/write. Until rules are deployed, writes should
/// fail with permission-denied. Do not weaken the rules to make them work.
class StaffRecordsRepository {
  const StaffRecordsRepository(this.db);
  final FirebaseFirestore db;

  Stream<List<StaffProfile>> watchStaffDirectory() => db
      .collection('staffProfiles')
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => StaffProfile.fromMap(doc.id, doc.data()))
          .toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName)));

  Stream<StaffProfile?> watchStaffProfile(String uid) {
    _validateUid(uid);
    return db.collection('staffProfiles').doc(uid).snapshots().map((doc) =>
        doc.exists ? StaffProfile.fromMap(doc.id, doc.data()!) : null);
  }

  Stream<List<StaffQualification>> watchQualifications(String uid) {
    _validateUid(uid);
    return db
        .collection('staffQualifications')
        .where('staffUid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => StaffQualification.fromMap(doc.id, doc.data()))
            .toList());
  }

  /// Admin-only operation, to be enabled after secure Firestore rules.
  Future<void> saveStaffProfile({
    required String uid,
    required String fullName,
    required String email,
    required String status,
    required Set<StaffRole> eligibleRoles,
  }) async {
    _validateUid(uid);
    final name = fullName.trim();
    final address = email.trim().toLowerCase();
    final nameError = StaffFormValidation.fullName(name);
    if (nameError != null) throw ArgumentError(nameError);
    final emailError = StaffFormValidation.email(address);
    if (emailError != null) throw ArgumentError(emailError);
    if (!{'active', 'inactive', 'suspended'}.contains(status)) {
      throw ArgumentError('Invalid staff account status.');
    }
    final directory = await db.collection('staffProfiles').get();
    final roleIssue = StaffRoleRules.validate(
      roles: eligibleRoles,
      colleagues: directory.docs.map((doc) => StaffProfile.fromMap(doc.id, doc.data())),
      editingUid: uid,
    );
    if (roleIssue != null) throw ArgumentError(roleIssue);
    await db.collection('staffProfiles').doc(uid).set({
      'fullName': name,
      'email': address,
      'status': status,
      'eligibleRoles': eligibleRoles.map((role) => role.code).toList()..sort(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Admin-only qualification approval. The caller's identity must be checked
  /// by Firestore Rules or a callable; this method cannot establish authority.
  Future<void> saveQualification({
    required String qualificationId,
    required String staffUid,
    required StaffRole role,
    required String title,
    required DateTime completedAt,
    DateTime? expiresAt,
    String? attractionId,
    String? courseId,
  }) async {
    _validateUid(staffUid);
    _validateUid(qualificationId);
    if (role == StaffRole.superAdmin) {
      throw ArgumentError('Super Admin is not a training qualification.');
    }
    if (title.trim().length < 3) {
      throw ArgumentError('Enter the training course name.');
    }
    if (courseId != null && (courseId.isEmpty || courseId.contains('/'))) {
      throw ArgumentError('Select a valid course.');
    }
    if (role == StaffRole.attractionOperator &&
        (attractionId == null || attractionId.isEmpty)) {
      throw ArgumentError('Select a ride for this course.');
    }
    if (expiresAt != null && !expiresAt.isAfter(completedAt)) {
      throw ArgumentError('Expiry must be after completion.');
    }
    await db.collection('staffQualifications').doc(qualificationId).set({
      'staffUid': staffUid,
      'roleCode': role.code,
      'title': title.trim(),
      if (courseId != null) 'courseId': courseId,
      'status': 'approved',
      'attractionId': attractionId ?? '',
      'completedAt': Timestamp.fromDate(completedAt.toUtc()),
      'expiresAt': expiresAt == null
          ? null
          : Timestamp.fromDate(expiresAt.toUtc()),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// All selected training records are committed together, or none are saved.
  /// Every write is still checked by the deployed Firestore Security Rules.
  Future<void> saveQualificationsBatch({
    required String staffUid,
    required DateTime completedAt,
    required List<StaffTrainingEntry> courses,
  }) async {
    _validateUid(staffUid);
    if (courses.isEmpty || courses.length > 3) {
      throw ArgumentError('Select 1–3 courses.');
    }
    if (completedAt.isAfter(DateTime.now().add(const Duration(days: 1)))) {
      throw ArgumentError('Check the completion date.');
    }
    if (courses.map((c) => c.courseId).toSet().length != courses.length) {
      throw ArgumentError('Select each course only once.');
    }
    // Read the authoritative catalogue records again. User-selected ride IDs
    // cannot be used to issue a qualification for a different attraction.
    final catalogue = <String, Map<String, dynamic>>{};
    for (final entry in courses) {
      if (entry.courseId.isEmpty || entry.courseId.contains('/')) {
        throw ArgumentError('Select a valid course.');
      }
      final snap = await db.collection('staffTrainingCourses')
          .doc(entry.courseId).get();
      if (!snap.exists || snap.data()?['active'] != true) {
        throw ArgumentError('This course is no longer available.');
      }
      catalogue[entry.courseId] = snap.data()!;
    }
    final batch = db.batch();
    final collection = db.collection('staffQualifications');
    for (final course in courses) {
      final registered = catalogue[course.courseId]!;
      final boundAttraction = registered['attractionId']?.toString() ?? '';
      if (course.title != registered['title'] ||
          course.role.code != registered['roleCode'] ||
          course.attractionId != (boundAttraction.isEmpty ? null : boundAttraction)) {
        throw ArgumentError('Select a valid course.');
      }
      final reason = StaffTrainingBatchPolicy.validate(
        role: course.role,
        attractionId: boundAttraction.isEmpty ? null : boundAttraction,
        expiresAt: course.expiresAt,
        completedAt: completedAt,
      );
      if (reason != null) throw ArgumentError(reason);
      batch.set(collection.doc(), {
        'staffUid': staffUid,
        'roleCode': course.role.code,
        'title': course.title.trim(),
        'courseId': course.courseId,
        'status': 'approved',
        'attractionId': boundAttraction,
        'completedAt': Timestamp.fromDate(completedAt.toUtc()),
        'expiresAt': course.expiresAt == null ? null
            : Timestamp.fromDate(course.expiresAt!.toUtc()),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> revokeQualification(String qualificationId) async {
    _validateUid(qualificationId);
    await db.collection('staffQualifications').doc(qualificationId).update({
      'status': 'revoked',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  void _validateUid(String uid) {
    if (uid.trim().isEmpty || uid.contains('/') || uid != uid.trim()) {
      throw ArgumentError('Invalid record. Try again.');
    }
  }
}

/// A single course in a multi-course training approval.
class StaffTrainingEntry {
  const StaffTrainingEntry({
    required this.courseId,
    required this.title,
    required this.role,
    this.attractionId,
    this.expiresAt,
  });
  final String courseId;
  final String title;
  final StaffRole role;
  final String? attractionId;
  final DateTime? expiresAt;
}
