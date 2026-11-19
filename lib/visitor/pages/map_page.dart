import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../attractions/data/attraction_reader.dart';
import '../../attractions/data/attraction_repository.dart';
import '../../attractions/data/slot_reader.dart';
import '../../attractions/models/attraction.dart';
import '../../attractions/pages/attraction_details_page.dart';
import '../../attractions/widgets/attraction_cover.dart';
import '../../attractions/widgets/attraction_widgets.dart';
import '../../attractions/widgets/queue_attraction_card.dart';
import '../../park/park_feed.dart';
import '../../park/park_map_canvas.dart';
import '../../park/park_visit.dart';
import '../../park/assistant_page.dart';
import '../../park/intelligence_repository.dart';
import '../../park/landmark_page.dart';
import '../../park/live_location_page.dart';
import '../../park/venue_map.dart';
import '../../park/visitor_gps.dart';
import '../../park/visitor_map_types.dart';
import '../../park/visitor_navigation_page.dart';
import '../../park/park_live_sharing.dart';
import '../../reservations/data/reservation_repository.dart';
import '../../reservations/pages/my_reservations_page.dart';
import '../../reservations/pages/reserve_attraction_page.dart';
import '../../reservations/widgets/reservation_widgets.dart';
import 'profile_settings_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key, this.startPlace, this.attractions, this.slots});

  final ValueNotifier<String?>? startPlace;
  final AttractionReader? attractions;
  final SlotReader? slots;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late final _catalogue = AttractionRepository(
    firestore: FirebaseFirestore.instance,
  );
  final _search = TextEditingController();
  String? _localStart, _selectedId, _destinationId;
  ParkPlaceKind? _kind = ParkPlaceKind.attractions;
  bool _filterChosen = false;
  bool _showAll = false, _heatmap = false;


  Position? _gpsPosition;
  String? _gpsMessage;
  bool _locating = false;
  String? _selectedGroupId;
  Timer? _gpsClock;
  Position? get _effectiveGps => VisitorGps.trusted(_gpsPosition)
      ? _gpsPosition : ParkLiveSharing.instance.position.value;
  bool get _onCampus => VisitorGps.trusted(_effectiveGps);

  // A coarse fix can be displayed and used to preview a walking route.
  Position? get _displayGps {
    final fix = _gpsPosition ?? ParkLiveSharing.instance.position.value;
    if (fix == null || !fix.latitude.isFinite || !fix.longitude.isFinite ||
        !fix.accuracy.isFinite || fix.accuracy < 0 ||
        DateTime.now().difference(fix.timestamp).abs() > VisitorGps.maxAge ||
        !VisitorGps.inside(fix.latitude, fix.longitude)) {
      return null;
    }
    return fix;
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() { _locating = true; _gpsMessage = null; });
    try {
      final fix = await VisitorGps.locate();
      if (!mounted) return;
      setState(() {
        _gpsPosition = fix;
        _gpsMessage = VisitorGps.reason(fix);
        _locating = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _gpsPosition = null;
        _gpsMessage = e is StateError ? e.message :
            'Unable to find your current location. Try again.';
        _locating = false;
      });
    }
  }

  Future<void> _navigateTo(
    String name,
    LatLng destination, {
    ParkVisit? visit,
    String? destinationId,
  }) async {
    final selected = _startId == destinationId ? null : visit?.place(_startId);
    await Navigator.push(context, MaterialPageRoute<void>(
      builder: (_) => VisitorNavigationPage(
        destinationName: name,
        destination: destination,
        initialPosition: _displayGps,
        initialStart: selected == null || visit == null
            ? null
            : (
                name: selected.name,
                point: venueCoordinate(selected, visit.places),
              ),
        chooseStart: visit == null
            ? null
            : () async {
                final place = await _chooseStart(
                  visit,
                  excludedId: destinationId,
                );
                if (place == null) return null;
                return (
                  name: place.name,
                  point: venueCoordinate(place, visit.places),
                );
              },
      ),
    ));
  }

  Future<void> _chooseTeam() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final groups = await FirebaseFirestore.instance.collection('groups')
          .where('memberUids', arrayContains: uid).get();
      if (!mounted) return;
      final selected = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Show teammates on map'),
                subtitle: Text('Only teammates who have chosen to share can appear.')),
            ListTile(leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Hide teammates'),
                onTap: () => Navigator.pop(ctx, 'hide')),
            for (final group in groups.docs)
              ListTile(leading: const Icon(Icons.groups_outlined),
                title: Text(group.data()['name'] as String? ?? 'My group'),
                onTap: () => Navigator.pop(ctx, group.id)),
          ],
        )),
      );
      if (mounted && selected != null) {
        setState(() => _selectedGroupId = selected == 'hide' ? null : selected);
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not load your groups. Check your connection.'),
      ));
    }
  }

  void _teammateDetails(VisitorTeammatePin teammate) {
    showModalBottomSheet<void>(context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.person_pin_circle_outlined, color: Color(0xFF557BB9)),
              const SizedBox(width: 12),
              Expanded(child: Text(teammate.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 8),
            const Text('This teammate has opted to share a recent on-campus location.'),
            const SizedBox(height: 15),
            FilledButton.icon(
              onPressed: () { Navigator.pop(ctx); _navigateTo(teammate.name, teammate.position); },
              icon: const Icon(Icons.directions_walk),
              label: const Text('Walk to teammate'),
            ),
          ],
        ),
      )),
    );
  }

  Widget _mapWithTeam(ParkVisit visit, List<Attraction> matches, Attraction? origin) {
    Widget render(List<VisitorTeammatePin> pins) => ParkMapCanvas(
      visit: visit,
      visible: matches,
      origin: _onCampus ? origin : null,
      heatmap: _heatmap,
      selectedId: _selectedId,
      currentPosition: _displayGps == null ? null
          : LatLng(_displayGps!.latitude, _displayGps!.longitude),
      currentAccuracyMeters: _displayGps?.accuracy,
      approximateCurrentPosition: _displayGps != null && !_onCampus,
      teammates: pins,
      onTeammate: _teammateDetails,
      onPlace: (place) => _placeDetails(place, visit),
    );
    final id = _selectedGroupId;
    if (id == null) return render(const []);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('groupMembers')
          .where('groupId', isEqualTo: id).snapshots(),
      builder: (context, memberSnapshot) {
        final members = <String,String>{};
        for (final doc in memberSnapshot.data?.docs ?? []) {
          final d = doc.data();
          if (d['memberId'] is String) members[d['memberId'] as String] =
              d['displayName'] as String? ?? 'Teammate';
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('groupLocations')
              .where('groupId', isEqualTo: id).snapshots(),
          builder: (context, locationSnapshot) {
            final pins = <VisitorTeammatePin>[];
            final myUid = FirebaseAuth.instance.currentUser?.uid;
            for (final doc in locationSnapshot.data?.docs ?? []) {
              final d = doc.data();
              final owner = d['ownerUid'];
              final lat = d['latitude'], lon = d['longitude'];
              final expires = d['expiresAt'];
              final accuracy = d['accuracy'];
              if (owner is! String || owner == myUid ||
                  !members.containsKey(owner) ||
                  lat is! num || lon is! num || accuracy is! num ||
                  accuracy > VisitorGps.maxAccuracyMeters ||
                  expires is! Timestamp ||
                  !expires.toDate().isAfter(DateTime.now()) ||
                  !VisitorGps.inside(lat.toDouble(), lon.toDouble())) continue;
              pins.add(VisitorTeammatePin(id: owner,
                  name: members[owner] ?? 'Teammate',
                  position: LatLng(lat.toDouble(), lon.toDouble())));
            }
            return render(pins);
          },
        );
      },
    );
  }

  void _showDetailsPage(Attraction place, ParkVisit visit) {
    Navigator.push(context, MaterialPageRoute<void>(
      builder: (_) => AttractionDetailsPage(
        store: _attractions,
        attractionId: place.id,
        slotReader: place.isRide ? _slots : null,
        day: visit.day,
        placeKind: place.placeKind,
      ),
    ));
  }

  void _placeDetails(Attraction place, ParkVisit visit) {
    showModalBottomSheet<void>(context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              AttractionCover(encoded: place.coverImageBase64,
                width: 84, height: 84,
                placeholderIcon: parkPlaceIcon(place.placeKind)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(place.name, style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${place.placeKind.label} • ${place.category}'),
                  Text(_status(place), style: TextStyle(color: place.status ==
                      AttractionStatus.open ? Colors.green : queueRose)),
                ],
              )),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () { Navigator.pop(ctx); _showDetailsPage(place, visit); },
                child: const Text('View Details'),
              )),
              const SizedBox(width: 10),
              Expanded(child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _directions(place, visit);
                },
                icon: const Icon(Icons.directions_walk, size: 18),
                label: const Text('Navigate'),
              )),
            ]),
          ],
        ),
      )),
    );
  }

  String _status(Attraction place) => switch(place.status) {
    AttractionStatus.open => 'Open',
    AttractionStatus.closed => 'Closed',
    AttractionStatus.maintenance => 'Under maintenance',
  };

  AttractionReader get _attractions => widget.attractions ?? _catalogue;
  SlotReader get _slots => widget.slots ?? _catalogue;
  String? get _startId => widget.startPlace?.value ?? _localStart;
  Future<void> _landmark(ParkVisit visit) async {
    final result = await Navigator.push<Object>(
      context,
      MaterialPageRoute(
        builder: (_) => LandmarkLocationPage(
          repository: FirebaseParkIntelligenceRepository(),
        ),
      ),
    );
    if (!mounted) return;
    if (result == LandmarkAction.chooseOnMap) {
      await _setStart(visit);
    } else if (result is String && visit.place(result) != null) {
      setState(() {
        _localStart = result;
        widget.startPlace?.value = result;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _gpsClock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && (_gpsPosition != null || ParkLiveSharing.instance.active.value)) setState(() {});
    });
  }

  @override
  void dispose() {
    _gpsClock?.cancel();
    _search.dispose();
    super.dispose();
  }

  ReservationRepository? _reservations() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return ReservationRepository(
      uid: user.uid,
      email: user.email,
      firestore: FirebaseFirestore.instance,
      functions: FirebaseFunctions.instanceFor(region: 'us-central1'),
    );
  }

  void _details(Attraction place, ParkVisit visit) {
    final reservations = place.isRide ? _reservations() : null;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          if (reservations != null) {
            return ReserveAttractionPage(
              attraction: place,
              attractions: _attractions,
              slots: _slots,
              reservations: reservations,
              day: visit.day,
            );
          }
          return AttractionDetailsPage(
            store: _attractions,
            attractionId: place.id,
            slotReader: place.isRide ? _slots : null,
            day: visit.day,
            placeKind: place.placeKind,
          );
        },
      ),
    );
  }

  Future<Attraction?> _chooseStart(
    ParkVisit visit, {
    String? excludedId,
  }) => showModalBottomSheet<Attraction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      var selected = _startId == excludedId ? null : visit.place(_startId);
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Find My Location',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  const ReservationPanel(
                    child: Text(
                      'Select a nearby landmark to set your starting point on the park map.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selected?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Nearby landmark',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final place in visit.places)
                        if (place.id != excludedId)
                          DropdownMenuItem(
                            value: place.id,
                            child: Text(
                              place.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    ],
                    onChanged: (value) =>
                        setSheetState(() => selected = visit.place(value)),
                  ),
                  const SizedBox(height: 14),
                  ReservationButton(
                    label: 'Use This Landmark',
                    onPressed: selected == null
                        ? null
                        : () => Navigator.pop(context, selected),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  Future<void> _setStart(ParkVisit visit, {Attraction? destination}) async {
    final origin = await _chooseStart(visit);
    if (origin == null || !mounted) return;
    widget.startPlace?.value = origin.id;
    setState(() {
      _localStart = origin.id;
      _destinationId = destination?.id == origin.id ? null : destination?.id;
    });
  }

  void _directions(Attraction destination, ParkVisit visit) {
    _navigateTo(
      destination.name,
      venueCoordinate(destination, visit.places),
      visit: visit,
      destinationId: destination.id,
    );
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: queueBackground,
    child: SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ParkFeed(
            attractions: _attractions,
            slots: _slots,
            builder: (context, visit, reload) {
              final origin = visit.place(_startId);
              final destination = visit.place(_destinationId);
              if (origin != null &&
                  destination != null &&
                  origin.id != destination.id) {
                return _route(visit, origin, destination);
              }
              return _browse(visit, origin);
            },
          ),
        ),
      ),
    ),
  );

  Widget _browse(ParkVisit visit, Attraction? origin) {
    final query = _search.text.trim().toLowerCase();
    final activeKind = !_filterChosen && query.isNotEmpty ? null : _kind;
    final matches = visit.places
        .where(
          (place) =>
              (activeKind == null || place.placeKind == activeKind) &&
              '${place.name} ${place.category} ${place.placeKind.label}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    if (_onCampus) {
      matches.sort((a, b) => VisitorGps.metres(_effectiveGps!,
        venueCoordinate(a, visit.places)).compareTo(VisitorGps.metres(
        _effectiveGps!, venueCoordinate(b, visit.places))));
    }
    final selected = matches
        .where((place) => place.id == _selectedId)
        .firstOrNull;
    return ListView(
      padding: const EdgeInsets.only(top: 10, bottom: 18),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Park Map',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: queueInk,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Park Assistant',
                    icon: const Icon(Icons.support_agent, color: queueRose),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ParkAssistantPage(
                          repository: FirebaseParkIntelligenceRepository(),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Profile settings',
                    icon: const Icon(Icons.settings_outlined, color: queueRose),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfileSettingsPage(),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reservations and reminders',
                    icon: const Icon(
                      Icons.notifications_outlined,
                      color: queueRose,
                    ),
                    onPressed: () {
                      final store = _reservations();
                      if (store != null) {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => MyReservationsPage(store: store),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 7),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {
                  _selectedId = null;
                  _showAll = false;
                }),
                decoration: InputDecoration(
                  hintText: 'Search attractions & facilities',
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Color(0xFF69727A),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFEEDCD8)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: queueRose),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final kind in ParkPlaceKind.values)
                    ChoiceChip(
                      label: Text(kind.label),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      labelPadding: const EdgeInsets.only(left: 3, right: 1),
                      visualDensity: VisualDensity.compact,
                      avatarBoxConstraints: const BoxConstraints.tightFor(
                        width: 16,
                        height: 16,
                      ),
                      avatar: Icon(
                        parkPlaceIcon(kind),
                        size: 16,
                        color: activeKind == kind ? Colors.white : queueRose,
                      ),
                      selected: activeKind == kind,
                      showCheckmark: false,
                      selectedColor: const Color(0xFFAD7472),
                      backgroundColor: queueBackground,
                      shape: const StadiumBorder(),
                      side: BorderSide(
                        color: activeKind == kind
                            ? const Color(0xFFAD7472)
                            : const Color(0xFFEADBD7),
                      ),
                      labelStyle: TextStyle(
                        color: activeKind == kind ? Colors.white : queueInk,
                        fontSize: 12,
                      ),
                      onSelected: (selected) => setState(() {
                        _filterChosen = true;
                        _kind = selected ? kind : null;
                        _selectedId = null;
                        _showAll = false;
                      }),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: .98,
          child: Stack(
            children: [
              Positioned.fill(
                child: _mapWithTeam(visit, matches, origin),
              ),
              Positioned(
                right: 14,
                bottom: 12,
                child: Column(
                  children: [
                    _mapButton(
                      _heatmap ? 'Hide crowd heatmap' : 'Show crowd heatmap',
                      Icons.layers_outlined,
                      () => setState(() => _heatmap = !_heatmap),
                    ),
                    const SizedBox(height: 8),
                    _mapButton(
                      'Locate a Landmark',
                      Icons.photo_camera_outlined,
                      () => _landmark(visit),
                    ),
                    const SizedBox(height: 8),
                    _mapButton(
                      'Show My Team',
                      Icons.groups_2_outlined,
                      _chooseTeam,
                    ),
                    const SizedBox(height: 8),
                    _mapButton(
                      'My Live Location',
                      Icons.location_searching,
                      () async {
                         await Navigator.push(context, MaterialPageRoute(
                           builder: (_) => const LiveLocationPage(),
                         ));
                         if (mounted) setState(() => _gpsPosition = ParkLiveSharing.instance.position.value);
                       },
                    ),
                    const SizedBox(height: 8),
                    _mapButton(
                      'Use My GPS',
                       Icons.my_location,
                       _locating ? null : _locate,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ReservationPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4D9D6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _onCampus ? 'Nearby' : 'Explore the park',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: queueInk,
                      ),
                    ),
                  ),
                  if (selected != null || matches.length > 2)
                    TextButton(
                      onPressed: () => setState(() {
                        _showAll = selected != null || !_showAll;
                        _selectedId = null;
                      }),
                      child: Text(
                        selected == null && _showAll ? 'See less' : 'See all',
                      ),
                    ),
                ],
              ),
              if (_onCampus)
                Text('Showing facilities by distance from your location • accuracy ±${_effectiveGps!.accuracy.round()} m',
                  style: const TextStyle(fontSize: 12))
              else ...[
                if (_displayGps != null) ...[
                  Text('Approximate location shown on map (±${_displayGps!.accuracy.round()} m). Choose a landmark to plan a route when GPS is imprecise.',
                    style: const TextStyle(fontSize: 12, color: queueInk)),
                  const SizedBox(height: 8),
                ],
                Container(padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFFF6F2),
                    borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Icon(Icons.location_off_outlined, color: queueRose),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_gpsMessage ?? VisitorGps.reason(_effectiveGps) ??
                      'Enable GPS when you arrive at TAR UMT Penang.',
                      style: const TextStyle(fontSize: 12))),
                  ])),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: _locating ? null : _locate,
                  icon: const Icon(Icons.my_location, size: 17),
                  label: Text(_locating ? 'Finding location…' : 'Check My Location')),
                if (_search.text.trim().isEmpty)
                  TextButton(onPressed: () => setState(() => _showAll = !_showAll),
                    child: Text(_showAll ? 'Hide park directory' : 'Browse all facilities')),
              ],
              const SizedBox(height: 8),
              if (selected != null) ...[
                _placeRow(selected, visit),
                OutlinedButton.icon(
                  onPressed: origin?.id == selected.id
                      ? null
                      : () => _directions(selected, visit),
                  icon: const Icon(Icons.directions_walk),
                  label: const Text('Directions'),
                ),
              ] else if (!_onCampus && _search.text.trim().isEmpty && !_showAll)
                const SizedBox.shrink()
              else if (matches.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No places match this view.'),
                )
              else
                for (final place in (_showAll ? matches : matches.take(2)))
                  _placeRow(place, visit),
            ],
          ),
        ),
      ],
    );
  }

  Widget _placeRow(Attraction place, ParkVisit visit) {
    final distance = _onCampus
        ? VisitorGps.metres(_effectiveGps!, venueCoordinate(place, visit.places))
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _placeDetails(place, visit),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AttractionCover(encoded: place.coverImageBase64,
                  width: 70, height: 70,
                  placeholderIcon: parkPlaceIcon(place.placeKind)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(place.name, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 15, color: queueInk)),
                  const SizedBox(height: 3),
                  Text('${place.category}  •  ${_status(place)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF81726F))),
                  if (distance != null) ...[
                    const SizedBox(height: 4),
                    Text('~${distance.round()} m away (straight-line)',
                      style: const TextStyle(fontSize: 11, color: queueRose)),
                  ],
                ],
              )),
              const Icon(Icons.chevron_right, color: queueRose),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _mapButton(String label, IconData icon, VoidCallback? action) =>
      IconButton.filled(
        tooltip: label,
        onPressed: action,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: queueInk,
        ),
        icon: Icon(icon),
      );

  Widget _route(
    ParkVisit visit,
    Attraction origin,
    Attraction destination,
  ) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      ReservationPanel(
        child: Row(
          children: [
            const Icon(Icons.directions_outlined, color: queueRose, size: 35),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Towards ${destination.name}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    'From ${origin.name}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      AspectRatio(
        aspectRatio: .9,
        child: ParkMapCanvas(
          visit: visit,
          visible: [destination],
          origin: origin,
          destination: destination,
          selectedId: destination.id,
          onPlace: (place) => _details(place, visit),
        ),
      ),
      const SizedBox(height: 12),
      ReservationPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Schematic direction preview',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            const Text(
              'Walking distance and arrival estimates require a surveyed path map.',
            ),
            const SizedBox(height: 12),
            ReservationButton(
              label: 'End Navigation',
              onPressed: () => setState(() => _destinationId = null),
            ),
          ],
        ),
      ),
    ],
  );
}
