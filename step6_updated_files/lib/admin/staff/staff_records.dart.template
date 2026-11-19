import 'package:cloud_firestore/cloud_firestore.dart';

import 'staff_access.dart';

/// Staff identity and approved job eligibility. This is DATA, not an auth token.
/// Never use this model by itself to authorize privileged Firebase operations.
class StaffProfile {
  const StaffProfile({
    required this.uid,
    this.staffId = '',
    required this.fullName,
    required this.email,
    required this.status,
    required this.eligibleRoles,
  });

  final String uid;
  final String staffId;
  final String fullName;
  final String email;
  final String status; // active | suspended | inactive
  final Set<StaffRole> eligibleRoles;

  bool get isActive => status == 'active';

  factory StaffProfile.fromMap(String uid, Map<String, dynamic> data) {
    final rawRoles = data['eligibleRoles'];
    final roles = <StaffRole>{};
    if (rawRoles is List) {
      for (final value in rawRoles) {
        if (value is! String) continue;
        final role = StaffRole.fromCode(value);
        // Super Admin privileges come ONLY from trusted Firebase claims.
        if (role != null && role != StaffRole.superAdmin) roles.add(role);
      }
    }
    return StaffProfile(
      uid: uid,
      staffId: data['staffId'] is String ? data['staffId'] as String : '',
      fullName: data['fullName'] is String ? data['fullName'] as String : '',
      email: data['email'] is String ? data['email'] as String : '',
      status: data['status'] is String ? data['status'] as String : 'inactive',
      eligibleRoles: roles,
    );
  }
}

/// Signed-off training/qualification for a role or specific ride.
/// Operator qualifications MUST name the exact attraction; no wildcard.
class StaffQualification {
  const StaffQualification({
    required this.id,
    required this.staffUid,
    required this.role,
    required this.title,
    required this.status,
    required this.completedAt,
    this.expiresAt,
    this.attractionId,
  });

  final String id;
  final String staffUid;
  final StaffRole role;
  final String title;
  final String status; // approved | revoked
  final DateTime completedAt;
  final DateTime? expiresAt;
  final String? attractionId;

  bool validAt(DateTime at) =>
      status == 'approved' &&
      !at.isBefore(completedAt) &&
      (expiresAt == null || at.isBefore(expiresAt!));

  bool covers(StaffRole target, DateTime at, {String? targetAttractionId}) {
    if (role != target || !validAt(at)) return false;
    if (target == StaffRole.attractionOperator) {
      return targetAttractionId != null &&
          targetAttractionId.isNotEmpty &&
          attractionId == targetAttractionId;
    }
    return true;
  }

  factory StaffQualification.fromMap(String id, Map<String, dynamic> data) {
    DateTime? timestamp(Object? value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return null;
    }

    final role = StaffRole.fromCode(data['roleCode'] is String
        ? data['roleCode'] as String
        : '');
    if (role == null || role == StaffRole.superAdmin) {
      throw const FormatException('Unknown staff qualification role.');
    }
    final completed = timestamp(data['completedAt']);
    if (completed == null) {
      throw const FormatException('Training completion date is missing.');
    }
    return StaffQualification(
      id: id,
      staffUid: data['staffUid'] is String ? data['staffUid'] as String : '',
      role: role,
      title: data['title'] is String ? data['title'] as String : '',
      status: data['status'] is String ? data['status'] as String : 'revoked',
      completedAt: completed,
      expiresAt: timestamp(data['expiresAt']),
      attractionId: data['attractionId'] is String &&
              (data['attractionId'] as String).isNotEmpty
          ? data['attractionId'] as String
          : null,
    );
  }
}

/// Eligibility for UI guidance only. Enforcement belongs on the trusted server.
/// Mandatory training for sensitive frontline roles prevents an untrained
/// employee receiving access just because their eligibleRoles include a role.
class StaffTrainingPolicy {
  static const Set<StaffRole> requiresTraining = {
    StaffRole.attractionOperator,
    StaffRole.admissionStaff,
    StaffRole.photographer,
    StaffRole.photoCounterStaff,
  };

  static bool isEligible({
    required StaffProfile staff,
    required Iterable<StaffQualification> qualifications,
    required StaffRole role,
    required DateTime at,
    String? attractionId,
  }) {
    if (!staff.isActive || !staff.eligibleRoles.contains(role)) return false;
    if (role == StaffRole.superAdmin) return false;
    if (!requiresTraining.contains(role)) return true;
    return qualifications.any((record) =>
        record.staffUid == staff.uid &&
        record.covers(role, at, targetAttractionId: attractionId));
  }
}
