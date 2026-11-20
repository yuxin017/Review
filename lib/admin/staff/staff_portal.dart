import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../firebase_options.dart';
import 'staff_records.dart';
import 'staff_records_repository.dart';
import 'staff_portal_policy.dart';
import 'staff_portal_navigation.dart';
import '../admin_shell.dart';
import '../admin_repository.dart';
import '../admin_portal.dart';

/// Uses a DIFFERENT Firebase app than AdminPortal and the visitor app.
/// Signing in as a restricted employee will not replace the Super Admin's
/// Firebase session in the same browser. Restricted staff NEVER receive the
/// legacy `admin:true` claim. They reuse the AdminShell UI.
class StaffPortal extends StatefulWidget {
  const StaffPortal({super.key});

  @override
  State<StaffPortal> createState() => _StaffPortalState();
}

/// Opens the role-scoped workspace using the account already signed in to Admin.
class StaffPortalWorkspace extends StatelessWidget {
  const StaffPortalWorkspace({
    super.key,
    required this.service,
    required this.user,
  });

  final AdminFirebase service;
  final User user;

  @override
  Widget build(BuildContext context) => _StaffSignedIn(
    key: ValueKey(user.uid),
    user: user,
    session: _StaffSession(auth: service.auth, db: service.db),
  );
}

class _StaffSession {
  const _StaffSession({required this.auth, required this.db});
  final FirebaseAuth auth;
  final FirebaseFirestore db;

  static Future<_StaffSession> initialize() async {
    FirebaseApp app;
    try {
      app = Firebase.app('ThemeParkStaff');
    } catch (_) {
      app = await Firebase.initializeApp(
        name: 'ThemeParkStaff',
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    return _StaffSession(
      auth: FirebaseAuth.instanceFor(app: app),
      db: FirebaseFirestore.instanceFor(app: app),
    );
  }
}

class _StaffPortalState extends State<StaffPortal> {
  late final Future<_StaffSession> _session = _StaffSession.initialize();

  @override
  Widget build(BuildContext context) => FutureBuilder<_StaffSession>(
    future: _session,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const _StaffMessage(
          title: 'Cannot open Staff Portal',
          details: "Couldn't open the page. Try again.",
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final session = snapshot.data!;
      return StreamBuilder<User?>(
        stream: session.auth.idTokenChanges(),
        initialData: session.auth.currentUser,
        builder: (context, authSnapshot) {
          if (authSnapshot.hasError) {
            return _StaffMessage(
              title: 'Session ended',
              details: 'Please check your connection and sign in again.',
              onSignOut: session.auth.signOut,
            );
          }
          final user = authSnapshot.data;
          if (user == null) {
            return _StaffLogin(auth: session.auth);
          }
          return _StaffSignedIn(key: ValueKey(user.uid), user: user, session: session);
        },
      );
    },
  );
}

// Both portals share the same login layout; authentication sessions remain
// separate. Staff signs in to the named ThemeParkStaff Firebase app, never
// through the primary AdminFirebase auth instance.
class _StaffLogin extends StatelessWidget {
  const _StaffLogin({required this.auth});

  final FirebaseAuth auth;

  @override
  Widget build(BuildContext context) => Theme(
    data: adminTheme(context),
    child: AdminLoginPage(
      portalTitle: 'Staff Portal',
      portalSubtitle: 'Sign in to access your staff workspace',
      accessNotice: 'Access is restricted to authorized park employees.',
      onSignIn: (email, password, remember) async {
        if (kIsWeb) {
          await auth.setPersistence(
            remember ? Persistence.LOCAL : Persistence.SESSION,
          );
        }
        await auth.signInWithEmailAndPassword(
          email: email.trim().toLowerCase(),
          password: password,
        );
      },
      onReset: ({required String email}) => auth.sendPasswordResetEmail(
        email: email.trim().toLowerCase(),
      ),
    ),
  );
}

class _StaffSignedIn extends StatefulWidget {
  const _StaffSignedIn({super.key, required this.user, required this.session});
  final User user;
  final _StaffSession session;

  @override
  State<_StaffSignedIn> createState() => _StaffSignedInState();
}

class _StaffSignedInState extends State<_StaffSignedIn> {
  late Future<IdTokenResult> _token = widget.user.getIdTokenResult();

  @override
  void initState() {
    super.initState();
    // The password-setup link does not verify the email. Once the employee
    // has verified it, register the proof automatically on sign-in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }
  bool _busy = false;
  String? _error;
  String? _notice;

  // Spark-safe verification proof: only a verified Firebase ID token can
  // create this record under the server-side Firestore Security Rules.
  Future<void> _syncVerifiedEmail() async {
    final user = widget.session.auth.currentUser;
    if (user == null || !user.emailVerified || user.email == null) return;
    final token = await user.getIdTokenResult(true);
    if (token.claims?['email_verified'] != true) return;
    await widget.session.db.collection('staffEmailVerifications').doc(user.uid).set({
      'email': user.email!.trim().toLowerCase(),
      'verifiedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      await widget.user.reload();
      // This records the verification with a token verified by Firebase,
      // not a checkbox or administrator-entered flag.
      await _syncVerifiedEmail();
      if (!mounted) return;
      setState(() => _token = widget.session.auth.currentUser!.getIdTokenResult(true));
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.code == 'user-disabled'
        ? 'Account disabled. Contact your supervisor.'
        : 'Unable to refresh account. Try signing in again.');
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't refresh. Try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyEmail() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      await widget.user.sendEmailVerification();
      if (mounted) setState(() => _notice =
        'Check your inbox, then select Refresh Access.');
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.code == 'too-many-requests'
        ? 'Too many requests. Try again later.' : 'Unable to send verification email.');
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't send the email. Try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<IdTokenResult>(
    future: _token,
    builder: (context, tokenSnapshot) {
      if (tokenSnapshot.hasError) {
        return _StaffMessage(title: 'Could not verify your account',
          details: 'Please refresh your access or sign in again.',
          onRefresh: _refresh, onSignOut: widget.session.auth.signOut);
      }
      if (!tokenSnapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      // Firebase Auth proves identity, while a rules-protected Staff Profile
      // proves that a root administrator actually approved this employee.
      // Ordinary visitor Auth accounts do not have a staff profile.
      final verified = widget.session.auth.currentUser?.emailVerified == true;
      final repo = StaffRecordsRepository(widget.session.db);
      return StreamBuilder<StaffProfile?>(
        stream: repo.watchStaffProfile(widget.user.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StaffMessage(title: 'Could not load your details',
              details: "Couldn't load your staff details. Try again.",
              onRefresh: _refresh, onSignOut: widget.session.auth.signOut);
          }
          if (!snapshot.hasData) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            return _StaffMessage(title: 'Account Not Linked',
              details: 'Ask your supervisor to link your account.',
              onSignOut: widget.session.auth.signOut);
          }
          final profile = snapshot.data!;
          // Refuse to proceed if an unexpected account/profile mismatch occurs.
          if (profile.email.trim().toLowerCase() != widget.user.email?.trim().toLowerCase()) {
            return _StaffMessage(title: 'Account mismatch',
              details: 'This account is not linked to your staff record.',
              onSignOut: widget.session.auth.signOut);
          }
          final access = StaffPortalPolicy.evaluate(
            signedIn: true, hasStaffProfile: true, emailVerified: verified,
            profileStatus: profile.status,
          );
          if (access == StaffPortalStage.verifyEmail) {
            return _StaffMessage(title: 'Verify Your Email',
              details: 'Check your inbox, verify your email, then refresh.',
              onPrimary: _verifyEmail, primaryLabel: 'Send Verification Email',
              onRefresh: _refresh, onSignOut: widget.session.auth.signOut,
              error: _error, notice: _notice, busy: _busy);
          }
          if (access == StaffPortalStage.suspended) {
            return _StaffMessage(title: 'Staff Account Suspended',
              details: 'Contact your supervisor. You cannot access employee tools.',
              onSignOut: widget.session.auth.signOut);
          }
          if (access == StaffPortalStage.pendingApproval) {
            return _StaffMessage(title: 'Account Awaiting Activation',
              details: 'Email verified. Waiting for supervisor approval.',
              onRefresh: _refresh, onSignOut: widget.session.auth.signOut);
          }
          if (access != StaffPortalStage.ready) {
            return _StaffMessage(title: 'Staff access unavailable',
              details: 'Your account is not ready. Please contact your supervisor.',
              onSignOut: widget.session.auth.signOut);
          }
          return _StaffAdminHome(profile: profile, repository: repo,
            auth: widget.session.auth, onSignOut: widget.session.auth.signOut);
        },
      );
    },
  );
}

/// Shares the EXACT AdminShell/sidebar and feature file used by Super Admin.
/// Uses the Firebase session supplied by the portal that authenticated staff.
class _StaffAdminHome extends StatelessWidget {
  const _StaffAdminHome({
    required this.profile,
    required this.repository,
    required this.auth,
    required this.onSignOut,
  });
  final StaffProfile profile;
  final StaffRecordsRepository repository;
  final FirebaseAuth auth;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => Theme(
    data: adminTheme(context),
    child: AdminShell(
    key: ValueKey(('staff-shell', profile.uid, profile.eligibleRoles.map((role) => role.code).join(','))),
    repository: StaffScopedAdminRepository(
      auth: auth,
      db: repository.db,
      profile: profile,
    ),
    adminName: profile.fullName,
    adminEmail: profile.email,
    onSignOut: onSignOut,
    portalNavigation: StaffPortalNavigation.employee(profile),
    staffWorkDb: repository.db,
    staffWorkProfile: profile,
  ));
}

class _StaffMessage extends StatelessWidget {
  const _StaffMessage({required this.title, required this.details,
    this.onSignOut, this.onRefresh, this.onPrimary, this.primaryLabel,
    this.error, this.notice, this.busy = false});
  final String title;
  final String details;
  final Future<void> Function()? onSignOut;
  final Future<void> Function()? onRefresh;
  final Future<void> Function()? onPrimary;
  final String? primaryLabel;
  final String? error;
  final String? notice;
  final bool busy;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Staff Portal')),
    body: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 540),
        child: Card(child: Padding(padding: const EdgeInsets.all(25), child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.verified_user_outlined, size: 48, color: Color(0xFFAD7472)),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(details, textAlign: TextAlign.center),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 14),
              child: _Feedback(error!, isError: true)),
            if (notice != null) Padding(padding: const EdgeInsets.only(top: 14),
              child: _Feedback(notice!)),
            const SizedBox(height: 20),
            if (onPrimary != null) FilledButton(onPressed: busy ? null : onPrimary,
              child: Text(primaryLabel ?? 'Continue')),
            if (onRefresh != null) OutlinedButton(onPressed: busy ? null : onRefresh,
              child: const Text('Refresh Access')),
            if (onSignOut != null) TextButton(onPressed: busy ? null : onSignOut,
              child: const Text('Sign Out')),
          ],
        ))),
      ),
    )),
  );
}

class _Feedback extends StatelessWidget {
  const _Feedback(this.message, {this.isError = false});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Card(
    color: isError ? const Color(0xFFFFEAEA) : const Color(0xFFEAF7EE),
    child: Padding(padding: const EdgeInsets.all(12),
      child: Text(message, style: TextStyle(
        color: isError ? const Color(0xFFB3261E) : const Color(0xFF1B5E20)))),
  );
}
