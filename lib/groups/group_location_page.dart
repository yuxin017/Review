import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../attractions/widgets/queue_attraction_card.dart';
import '../reservations/widgets/reservation_widgets.dart';
import 'group_repository.dart';
import 'group_pages.dart';
import '../park/venue_map.dart';
import '../park/visitor_gps.dart';
import '../park/visitor_navigation_page.dart';
import 'group_live_sharing.dart';

class GroupLocationPage extends StatefulWidget {
  final GroupRepository repository;
  final GroupRecord group;
  const GroupLocationPage({
    super.key,
    required this.repository,
    required this.group,
  });
  @override
  State<GroupLocationPage> createState() => _GroupLocationPageState();
}

class _GroupLocationPageState extends State<GroupLocationPage> {
  late final locations = widget.repository.locations(widget.group.id),
      members = widget.repository.members(widget.group.id);
  final map = MapController();
  Timer? timer;
  bool busy = false;
  String? error;
  bool get sharing => GroupLiveSharing.instance.activeGroupId.value == widget.group.id;

  @override
  void initState() {
    super.initState();
    GroupLiveSharing.instance.activeGroupId.addListener(_changed);
    timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  void _changed() {if (mounted) setState(() {});}

  @override
  void dispose() {
    timer?.cancel();
    GroupLiveSharing.instance.activeGroupId.removeListener(_changed);
    map.dispose();
    super.dispose();
  }

  Future<void> toggle(bool value) async {
    if (busy) return;
    setState(() {busy = true; error = null;});
    try {
      if (value) {
        await GroupLiveSharing.instance.start(widget.group.id, widget.repository);
      } else {
        await GroupLiveSharing.instance.stop();
      }
    } catch (e) {
      if (mounted) setState(() => error = e is StateError
          ? e.message : 'Could not update location sharing. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> navigate(GroupRecord location) async {
    try {
      final p = await VisitorGps.locate();
      if (!VisitorGps.trusted(p)) {
        throw StateError(VisitorGps.reason(p) ?? 'You are outside the park.');
      }
      final lat = (location.data['latitude'] as num).toDouble();
      final lon = (location.data['longitude'] as num).toDouble();
      if (!VisitorGps.inside(lat, lon)) {
        throw StateError('This teammate is not currently on the park map.');
      }
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute<void>(
        builder: (_) => VisitorNavigationPage(
          destinationName: 'My teammate', destination: LatLng(lat, lon)),
      ));
    } catch (e) {
      if (mounted) setState(() => error = e is StateError ? e.message :
          'Could not start walking directions. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) => GroupFrame(
    title: 'Group Live Location',
    body: StreamBuilder<List<GroupRecord>>(
      stream: locations,
      builder: (context, snapshot) {
        final fresh = (snapshot.data ?? <GroupRecord>[]).where((record) {
          final expires = record.data['expiresAt'];
          return expires is Timestamp &&               expires.toDate().isAfter(DateTime.now()) &&
               record.data['latitude'] is num &&
               record.data['longitude'] is num &&
               record.data['accuracy'] is num &&
               (record.data['accuracy'] as num) <= VisitorGps.maxAccuracyMeters &&
               VisitorGps.inside((record.data['latitude'] as num).toDouble(),
                 (record.data['longitude'] as num).toDouble());
        }).toList();
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            ReservationPanel(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Share my location',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Only this group can see your location. Sharing continues while the app is in the foreground. Stop anytime.',
                ),
                value: sharing,
                onChanged: busy ? null : toggle,
              ),
            ),
            const SizedBox(height: 15),
            if (snapshot.hasError)
              const ReservationPanel(
                child: Text(
                  'Unable to load group locations. Check your connection or membership.',
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 370,
                child: fresh.isEmpty
                    ? Container(
                        color: const Color(0xFFEAE4DA),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.location_off_outlined,
                              size: 70,
                              color: queueRose,
                            ),
                            SizedBox(height: 18),
                            Text(
                              'No live locations shared yet',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 10),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                'Members appear here after choosing to share their device location.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      )
                    : FlutterMap(
                        mapController: map,
                        options: MapOptions(
                          initialCenter: LatLng(
                            (fresh.first.data['latitude'] as num).toDouble(),
                            (fresh.first.data['longitude'] as num).toDouble(),
                          ),
                          initialZoom: 17,
                        ),
                        children: [
                          const ProviderTileLayer(),
                          MarkerLayer(
                            markers: [
                              for (final record in fresh)
                                Marker(
                                  point: LatLng(
                                    (record.data['latitude'] as num).toDouble(),
                                    (record.data['longitude'] as num)
                                        .toDouble(),
                                  ),
                                  width: 44,
                                  height: 54,
                                  child: const Icon(
                                    Icons.location_on,
                                    size: 45,
                                    color: queueRose,
                                  ),
                                ),
                            ],
                          ),
                          const ProviderAttribution(),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 14),
            ReservationPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.group.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh locations',
                        onPressed: () => setState(() {}),
                        icon: const Icon(Icons.refresh, color: queueRose),
                      ),
                    ],
                  ),
                  const Text(
                    'Device location • accuracy varies by device',
                    style: TextStyle(fontSize: 11, color: Color(0xFF6D737A)),
                  ),
                  const SizedBox(height: 13),
                  StreamBuilder<List<GroupRecord>>(
                    stream: members,
                    builder: (context, people) {
                      if (people.hasError) {
                        return const Text('Unable to load members.');
                      }
                      return Column(
                        children: [
                          for (final member in people.data ?? <GroupRecord>[])
                            Builder(
                              builder: (context) {
                                final position = fresh
                                    .where(
                                      (p) =>
                                          p.data['ownerUid'] ==
                                          member.data['memberId'],
                                    )
                                    .firstOrNull;
                                final own =
                                    member.data['memberId'] ==
                                    widget.repository.uid;
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: MemberAvatar(member: member),
                                  title: Text(
                                    '${member.data['displayName']}${own ? ' (You)' : ''}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    position == null
                                        ? 'Location sharing off or unavailable'
                                        : 'Accuracy ±${(position.data['accuracy'] as num).round()} m • ${(position.data['updatedAt'] as Timestamp?)?.toDate().toLocal().toString().substring(11, 16) ?? 'just now'}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  trailing: position != null && !own
                                      ? TextButton(
                                          onPressed: () => navigate(position),
                                          child: const Text('Navigate'),
                                        )
                                      : own && sharing
                                      ? const Text(
                                          'Sharing',
                                          style: TextStyle(
                                            color: queueRose,
                                            fontSize: 12,
                                          ),
                                        )
                                      : null,
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(14),
                child: LinearProgressIndicator(),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(15),
                child: Text(error!, style: const TextStyle(color: queueRose)),
              ),
            const SizedBox(height: 10),
            const Text(
              'Stop sharing at any time. Walking directions open in your maps application.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF6D737A)),
            ),
          ],
        );
      },
    ),
  );
}
