import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import 'staff_access.dart';
import 'staff_records.dart';
import 'staff_role_rules.dart';
import 'staff_spark_policy.dart';

class StaffAccountCreated {
  const StaffAccountCreated({
    required this.uid,
    required this.staffId,
    required this.email,
  });
  final String uid;
  final String staffId;
  final String email;
}

/// Spark-plan FYP implementation: no Cloud Functions or Admin SDK.
///
/// IMPORTANT: This is a demo onboarding flow, NOT server-side provisioning.
/// The trusted security boundary is the already deployed Firestore Rules:
/// only an `admin: true` claimant can create staffProfiles, and a staff user
/// cannot grant roles or edit their staff profile. Operational tools remain
/// locked; there is no `staff:true` or `admin:true` claim given to employees.
///
/// Firebase client Auth registration itself is intentionally available to
/// ordinary users (the visitor app has public registration), so the Auth
/// account alone never means a person is an authorized employee.
class StaffOnboardingRepository {
  StaffOnboardingRepository()
      : _adminAuth = FirebaseAuth.instanceFor(
          app: Firebase.app('ThemeParkAdmin'),
        ),
        _adminDb = FirebaseFirestore.instanceFor(
          app: Firebase.app('ThemeParkAdmin'),
        );

  final FirebaseAuth _adminAuth;
  final FirebaseFirestore _adminDb;
  final Random _random = Random.secure();

  static const String _provisioningAppName = 'ThemeParkStaffProvisioning';
  static const String _characters =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#%_-';

  Future<FirebaseAuth> _secondaryAuth() async {
    FirebaseApp app;
    try {
      app = Firebase.app(_provisioningAppName);
    } catch (_) {
      app = await Firebase.initializeApp(
        name: _provisioningAppName,
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    final auth = FirebaseAuth.instanceFor(app: app);
    // On web, do not persist the temporary employee session between reloads.
    if (kIsWeb) await auth.setPersistence(Persistence.NONE);
    return auth;
  }

  Future<String> _unusedStaffId() async {
    // Staff IDs are display identifiers, never secrets/credentials.
    // Checking an eight-digit random ID is sufficient for this small FYP
    // demo, but it is not a transactional global uniqueness guarantee.
    for (var attempt = 0; attempt < 12; attempt++) {
      final value = 10000000 + _random.nextInt(90000000);
      final id = StaffSparkPolicy.staffIdFromNumber(value);
      final existing = await _adminDb
          .collection('staffProfiles')
          .where('staffId', isEqualTo: id)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) return id;
    }
    throw StateError('Could not allocate a Staff ID. Try again.');
  }

  String _temporaryPassword() {
    // Include each character class in case the Firebase project's password
    // policy requires mixed case, digits, and special characters.
    final chars = <String>[
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ'[_random.nextInt(26)],
      'abcdefghijklmnopqrstuvwxyz'[_random.nextInt(26)],
      '0123456789'[_random.nextInt(10)],
      '!@#%_-'[_random.nextInt(6)],
      ...List.generate(
        36,
        (_) => _characters[_random.nextInt(_characters.length)],
      ),
    ];
    chars.shuffle(_random);
    return chars.join();
  }

  Future<StaffAccountCreated> createStaff({
    required String fullName,
    required String email,
    required Set<StaffRole> eligibleRoles,
  }) async {
    StaffSparkPolicy.validate(
      fullName: fullName,
      email: email,
      eligibleRoles: eligibleRoles,
    );
    final name = fullName.trim();
    final address = StaffSparkPolicy.normalizeEmail(email);

    // Admin session is never switched to the employee account.
    final admin = _adminAuth.currentUser;
    if (admin == null || !admin.emailVerified) {
      throw StateError('Sign in with a verified Admin account first.');
    }
    final adminToken = await admin.getIdTokenResult(true);
    if (adminToken.claims?['admin'] != true) {
      throw StateError('Your account is not authorized to create staff.');
    }

    // Check existing roles before creating a Firebase Auth identity.
    final directory = await _adminDb.collection('staffProfiles').get();
    final roleIssue = StaffRoleRules.validate(
      roles: eligibleRoles,
      colleagues: directory.docs.map((doc) => StaffProfile.fromMap(doc.id, doc.data())),
    );
    if (roleIssue != null) throw ArgumentError(roleIssue);

    // Allocate before creating Auth user so a failed query never leaves one.
    final staffId = await _unusedStaffId();
    final provisioningAuth = await _secondaryAuth();
    User? newlyCreatedUser;
    var profileSaved = false;

    try {
      // The separate app MUST have no lingering staff session.
      if (provisioningAuth.currentUser != null) {
        await provisioningAuth.signOut();
      }

      // The random password is never displayed, logged, or saved in Firestore.
      // The employee gets a normal Firebase password-reset/setup email next.
      final result = await provisioningAuth.createUserWithEmailAndPassword(
        email: address,
        password: _temporaryPassword(),
      );
      newlyCreatedUser = result.user;
      if (newlyCreatedUser == null) {
        throw StateError('Firebase did not return a new employee account.');
      }

      // This write uses the ADMIN Firebase session, not the temporary staff
      // session. Rules check the real admin token and reject visitor writes.
      await _adminDb.collection('staffProfiles').doc(newlyCreatedUser.uid).set({
        'staffId': staffId,
        'fullName': name,
        'email': address,
        'status': 'inactive',
        'eligibleRoles': eligibleRoles.map((r) => r.code).toList()..sort(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      profileSaved = true;

      return StaffAccountCreated(
        uid: newlyCreatedUser.uid,
        staffId: staffId,
        email: address,
      );
    } catch (error) {
      if (newlyCreatedUser != null && !profileSaved) {
        // Newly registered Auth users can ordinarily delete themselves right
        // away. If rollback fails, report a possible orphaned Auth identity.
        try {
          await newlyCreatedUser.delete();
        } catch (_) {
          throw StateError(
            'An employee Auth account may exist without a Staff Profile. '
            'Check Firebase Authentication and Firestore before retrying.',
          );
        }
      }
      rethrow;
    } finally {
      // This is ONLY the named provisioning Auth, not the Super Admin Auth.
      try {
        await provisioningAuth.signOut();
      } catch (_) {
        // The temporary auth session has no staff operating permissions.
      }
    }
  }

  /// Uses Firebase's built-in password reset email, supported on Spark.
  /// Sends to the employee's existing mailbox; Firebase does not create inboxes.
  Future<void> sendPasswordSetupEmail(String email) =>
      _adminAuth.sendPasswordResetEmail(
        email: StaffSparkPolicy.normalizeEmail(email),
      );
}
