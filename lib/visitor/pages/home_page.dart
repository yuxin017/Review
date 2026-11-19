import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../visitor_main_page.dart';
import '../widgets/visitor_ui.dart';
import '../../groups/group_pages.dart';
import '../../groups/group_repository.dart';
import '../../photos/photo_gallery_pages.dart';
import '../../photos/photo_repository.dart';
import '../../park/assistant_page.dart';
import '../../park/intelligence_repository.dart';
import '../../park/offers_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Widget _sectionTitle(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: Text(title,
        style: const TextStyle(fontSize: 20,
          fontWeight: FontWeight.w800, color: Color(0xFF302A2A)))),
      Text(subtitle, style: const TextStyle(
        color: Color(0xFF957F7B), fontSize: 11)),
    ]),
  );

  Widget _shortcutGrid(List<_HomeShortcut> actions) =>
      LayoutBuilder(builder: (context, bounds) {
        final cardWidth = (bounds.maxWidth - 12) / 2;
        return Wrap(spacing: 12, runSpacing: 12,
          children: [for (final item in actions)
            SizedBox(width: cardWidth, height: 138,
              child: _ShortcutCard(item: item))]);
      });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName?.trim();
    return VisitorScreen(title: 'Discover', children: [
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('visitors')
          .doc(user?.uid).snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? {};
          final nickname = (data['nickname'] as String? ?? '').trim();
          final display = nickname.isNotEmpty ? nickname :
              (data['fullName'] as String? ?? name ?? 'Explorer');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('WELCOME TO YOUR ADVENTURE',
                style: TextStyle(fontSize: 10, letterSpacing: 1.7,
                  color: visitorRose, fontWeight: FontWeight.w800)),
              const SizedBox(height: 7),
              Text('Hello, ${display.isEmpty ? 'Explorer' : display}!',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 26,
                  fontWeight: FontWeight.w800, letterSpacing: -.5,
                  color: Color(0xFF302A2A))),
              const SizedBox(height: 5),
              const Text('Your next adventure starts here.',
                style: TextStyle(fontSize: 13, color: Color(0xFF7E7774))),
            ],
          );
        },
      ),
      const SizedBox(height: 19),
      Semantics(label: 'Buy Tickets', button: true,
        child: Material(
          borderRadius: BorderRadius.circular(21),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => VisitorMainPage.openTickets(context, 'catalog'),
            child: Image.asset('assets/images/ticketing/hero.png',
              height: 175, width: double.infinity,
              fit: BoxFit.cover, excludeFromSemantics: true),
          ),
        ),
      ),
      const SizedBox(height: 25),
      _sectionTitle('Plan your visit', 'EXPLORE & PLAY'),
      _shortcutGrid([
        _HomeShortcut(Icons.confirmation_number_outlined, 'My Tickets',
          'Your passes & QR',
          () => VisitorMainPage.openTickets(context, 'tickets')),
        _HomeShortcut(Icons.hourglass_bottom_outlined, 'Virtual Queue',
          'Save time on rides',
          () => VisitorMainPage.goTo(context, 3)),
        _HomeShortcut(Icons.map_outlined, 'Park Map',
          'Find your way',
          () => VisitorMainPage.goTo(context, 2)),
        _HomeShortcut(Icons.local_offer_outlined, 'Park Offers',
          'Discover rewards',
          () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ParkOffersPage(
              repository: FirebaseParkOffersRepository())))),
      ]),
      const SizedBox(height: 24),
      _sectionTitle('Made for you', 'YOUR PARK DAY'),
      _shortcutGrid([
        _HomeShortcut(Icons.groups_outlined, 'My Groups',
          'Explore together',
          () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => GroupsPage(
              repository: FirebaseGroupRepository())))),
        _HomeShortcut(Icons.photo_library_outlined, 'My Park Photos',
          'Your best memories',
          () => Navigator.push(context, MaterialPageRoute(
            settings: const RouteSettings(name: 'photos-hub'),
            builder: (_) => PhotoHubPage(
              repository: FirebasePhotoRepository())))),
        _HomeShortcut(Icons.support_agent_outlined, 'Park Assistant',
          'Here to help',
          () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ParkAssistantPage(
              repository: FirebaseParkIntelligenceRepository(),
              visitorName: name ?? '')))),
        _HomeShortcut(Icons.person_outline, 'My Profile',
          'Your account',
          () => VisitorMainPage.goTo(context, 4)),
      ]),
      const SizedBox(height: 10),
    ]);
  }
}

class _HomeShortcut {
  const _HomeShortcut(this.icon, this.title, this.subtitle, this.onTap);
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({required this.item});
  final _HomeShortcut item;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Color(0xFFF2E7E3))),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 15, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 40, height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF8EBE8),
                borderRadius: BorderRadius.circular(13)),
              child: Icon(item.icon, size: 22, color: visitorRose)),
            const Spacer(),
            Text(item.title, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: Color(0xFF302A2A))),
            const SizedBox(height: 3),
            Text(item.subtitle, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11,
                color: Color(0xFF857B78))),
          ],
        ),
      ),
    ),
  );
}
