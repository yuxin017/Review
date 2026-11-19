import 'package:flutter/material.dart';
import '../admin_widgets.dart';
import 'staff_portal_navigation.dart';

/// Staff pages intentionally use the exact same AdminHeading, AdminStat,
/// AdminCard, AdminBadge, and sidebar container as the Super Admin portal.
/// This widget never fabricates operational data or grants backend access.
class StaffWorkspaceUi extends StatelessWidget {
  const StaffWorkspaceUi({
    super.key,
    required this.navigation,
    required this.staffName,
    required this.page,
    required this.onOpen,
  });

  final StaffPortalNavigation navigation;
  final String staffName;
  final String page;
  final ValueChanged<String> onOpen;

  static const Map<String, (String, String, IconData)> details = {
    'dashboard': ('Dashboard', 'Your work overview', Icons.dashboard_outlined),
    'visitors': ('Visitors', 'Visitor enquiries and account lookup', Icons.people_outline),
    'staff': ('Staff Management', 'Staff access management', Icons.badge_outlined),
    'tickets': ('Tickets & Orders', 'Ticket and order enquiries', Icons.confirmation_number_outlined),
    'packages': ('Pass Packages', 'Ticket packages and pass information', Icons.local_activity_outlined),
    'photos': ('Smart Photos', 'Park photography and photo services', Icons.photo_library_outlined),
    'promotions': ('Promotions & Rewards', 'Campaigns and loyalty rewards', Icons.redeem_outlined),
    'reports': ('Reports & Analytics', 'Performance and business reports', Icons.insights_outlined),
    'crowd': ('Crowd Monitoring', 'Visitor density and park occupancy', Icons.hub_outlined),
    'landmarks': ('Landmark References', 'Park locations and landmarks', Icons.location_searching),
    'anomalies': ('Unusual Activity', 'Unusual activity review', Icons.policy_outlined),
    'photo-kiosk': ('Photo Kiosk', 'Photo pickup and printing', Icons.local_printshop_outlined),
    'facilities': ('Park Facilities', 'Facilities and attraction status', Icons.attractions_outlined),
    'reservations': ('Reservations', 'Visitor queue reservations', Icons.event_available_outlined),
    'validation': ('Ticket Validation', 'Entry scanning and validation', Icons.qr_code_scanner),
    'ride-entry': ('Attraction Check-in', 'Ride check-ins and attendance', Icons.sensor_door_outlined),
    'activity': ('Activity Monitoring', 'Park operational activity', Icons.monitor_heart_outlined),
    'support': ('Feedback & Complaints', 'Guest feedback and support cases', Icons.forum_outlined),
  };

  @override
  Widget build(BuildContext context) => page == 'dashboard'
      ? _dashboard(context)
      : _feature(context);

  Widget _dashboard(BuildContext context) {
    final available = navigation.availableMenus
        .where((id) => id != 'dashboard').toList();
    final readOnly = available.where(navigation.readOnly).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminHeading(
          'Park Operations Overview',
          'Your approved staff workspace and assigned services',
        ),
        const SizedBox(height: 26),
        AdminStats(children: [
          AdminStat('Available Sections', '${available.length}',
              'Based on your staff roles', Icons.space_dashboard_outlined),
          AdminStat('Approved Roles', '${navigation.roles.length}',
              'Your assigned job roles', Icons.badge_outlined,
              color: const Color(0xFF379568)),
          AdminStat('View-only Sections', '$readOnly',
              'Limited to your job duties', Icons.visibility_outlined,
              color: const Color(0xFF637FB3)),
          const AdminStat('Account Status', 'Active',
              'Verified staff account', Icons.verified_user_outlined,
              color: Color(0xFFBE8752)),
        ]),
        const SizedBox(height: 24),
        AdminCard(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome, $staffName',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                    color: adminDark)),
            const SizedBox(height: 6),
            Text(navigation.roleLabel,
                style: const TextStyle(color: adminMuted, fontSize: 13)),
            const SizedBox(height: 10),
            const Text(
              'Select a service below, or use the sidebar. Tools that need '
              'additional server authorisation will say so before you use them.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        )),
        const SizedBox(height: 24),
        const Text('Your Services', style: TextStyle(
            fontSize: 21, fontWeight: FontWeight.w700, color: adminDark)),
        const SizedBox(height: 14),
        if (available.isEmpty)
          const AdminCard(child: Text('No services assigned yet. Please contact your supervisor.'))
        else
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth >= 870
                ? (constraints.maxWidth - 32) / 3
                : constraints.maxWidth >= 560
                    ? (constraints.maxWidth - 16) / 2
                    : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final id in available)
                  SizedBox(width: width, child: _serviceCard(id)),
              ],
            );
          }),
      ],
    );
  }

  Widget _serviceCard(String id) {
    final info = details[id]!;
    final isReadOnly = navigation.readOnly(id);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onOpen(id),
        child: AdminCard(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(info.$3, size: 28, color: adminRose),
            const SizedBox(height: 16),
            Text(info.$1, style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: adminDark)),
            const SizedBox(height: 6),
            Text(info.$2, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: adminMuted)),
            const SizedBox(height: 14),
            AdminBadge(isReadOnly ? 'View only' : 'Role assigned'),
          ],
        )),
      ),
    );
  }

  Widget _feature(BuildContext context) {
    final info = details[page];
    final title = info?.$1 ?? 'Staff Service';
    final summary = info?.$2 ?? 'Assigned staff service';
    final viewOnly = navigation.readOnly(page);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminHeading(title, summary),
        const SizedBox(height: 25),
        AdminCard(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(info?.$3 ?? Icons.work_outline,
                  color: adminRose, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Text(
                  viewOnly ? 'Limited staff access' : 'Staff service',
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w700,
                      color: adminDark))),
            ]),
            const SizedBox(height: 16),
            AdminBadge(viewOnly ? 'View only' : 'Role assigned'),
            const SizedBox(height: 16),
            Text(viewOnly
                ? 'This section is included for your job, but you cannot '
                  'make administrator-level changes.'
                : 'You are assigned to this service. Live tools require '
                  'the correct server permissions and, where applicable, '
                  'a valid shift or completed training.'),
            const SizedBox(height: 12),
            const Text(
              'The staff data connection for this section is not enabled '
              'in the current Firebase backend. No records are shown to '
              'avoid exposing administrator-only information.',
              style: TextStyle(color: adminMuted, fontSize: 13),
            ),
            const SizedBox(height: 18),
            AdminButton('Back to Dashboard',
                icon: Icons.arrow_back, outlined: true,
                onPressed: () => onOpen('dashboard')),
          ],
        )),
      ],
    );
  }
}
