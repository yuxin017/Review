/// UI-only access gate for the Spark-plan Staff Portal.
/// A `staff:true` custom claim is NOT required: Spark client-side registration
/// cannot safely issue claims. The staff identity comes from a Staff Profile
/// created by an authorized admin under Firestore Rules.
///
/// This is NOT an authorization layer for ticket validation, operations, etc.
enum StaffPortalStage {
  signIn,
  notStaff,
  verifyEmail,
  pendingApproval,
  suspended,
  ready,
}

class StaffPortalPolicy {
  const StaffPortalPolicy._();

  static StaffPortalStage evaluate({
    required bool signedIn,
    required bool hasStaffProfile,
    required bool emailVerified,
    required String? profileStatus,
  }) {
    if (!signedIn) return StaffPortalStage.signIn;
    if (!hasStaffProfile) return StaffPortalStage.notStaff;
    if (!emailVerified) return StaffPortalStage.verifyEmail;
    if (profileStatus == 'suspended') return StaffPortalStage.suspended;
    if (profileStatus == 'inactive') return StaffPortalStage.pendingApproval;
    if (profileStatus == 'active') return StaffPortalStage.ready;
    return StaffPortalStage.notStaff;
  }
}
