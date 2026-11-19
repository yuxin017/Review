import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../attractions/models/attraction.dart';
import 'crowdsense_engine.dart';

/// CrowdSense FYP demonstration: actual on-device camera counts are consumed
/// from Live Cameras while that video viewer is open. Other places use clearly
/// labelled test scenario inputs. This deliberately does not write fake data
/// into the production Firestore collections.
class CrowdSenseLab extends StatefulWidget {
  const CrowdSenseLab({
    super.key,
    required this.attractions,
    required this.readings,
  });

  final List<Attraction> attractions;
  final ValueListenable<Map<String, CrowdSensorReading>> readings;

  @override
  State<CrowdSenseLab> createState() => _CrowdSenseLabState();
}

class _CrowdSenseLabState extends State<CrowdSenseLab> {
  static const _rose = Color(0xFFAD7472);
  static const _ink = Color(0xFF312D37);
  static const _base = <int>[0, 1, 1, 0];
  final Map<String, int> _simulatedCounts = {};
  final Map<String, List<CrowdSensorReading>> _history = {};
  final Map<String, DateTime> _lastSeen = {};
  Timer? _clock;
  bool _whatIf = false;
  int _capacity = 3;
  String _closed = '';

  @override
  void initState() {
    super.initState();
    widget.readings.addListener(_collect);
    _clock = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {}); // expire stale camera samples
    });
    _collect();
  }

  @override
  void didUpdateWidget(covariant CrowdSenseLab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.readings != widget.readings) {
      oldWidget.readings.removeListener(_collect);
      widget.readings.addListener(_collect);
      _collect();
    }
  }

  @override
  void dispose() {
    widget.readings.removeListener(_collect);
    _clock?.cancel();
    super.dispose();
  }

  void _collect() {
    for (final entry in widget.readings.value.entries) {
      if (_lastSeen[entry.key] == entry.value.receivedAt) continue;
      _lastSeen[entry.key] = entry.value.receivedAt;
      final list = _history.putIfAbsent(entry.key, () => []);
      list.add(entry.value);
      list.removeWhere(
        (item) =>
            entry.value.receivedAt.difference(item.receivedAt).inSeconds > 60,
      );
      if (list.length > 60) list.removeRange(0, list.length - 60);
    }
    if (mounted) setState(() {});
  }

  List<CrowdSenseZone> _zones() {
    // The assigned cameras are passed first, so an observed camera is in the
    // four-node demonstration graph even in a large attraction catalogue.
    final existing = widget.attractions.take(4).toList();
    final zones = <CrowdSenseZone>[];
    for (final a in existing) {
      zones.add(
        CrowdSenseZone(
          id: a.id,
          name: a.name,
          mapX: a.mapX,
          mapY: a.mapY,
          isDemo: false,
        ),
      );
    }
    for (var i = zones.length; i < 4; i++) {
      zones.add(
        CrowdSenseZone(
          id: 'crowdsense_demo_$i',
          name: 'Demo Attraction ${String.fromCharCode(65 + i)}',
          mapX: CrowdSenseRouter.positions[i].x,
          mapY: CrowdSenseRouter.positions[i].y,
          isDemo: true,
        ),
      );
    }
    return zones;
  }

  int _countFor(
    CrowdSenseZone zone,
    int index,
    DateTime now, {
    required bool scenario,
  }) {
    final camera = widget.readings.value[zone.id];
    if (!scenario && camera != null && camera.isRecent(now)) {
      return camera.count;
    }
    if (!scenario && _whatIf) return _base[index];
    return _simulatedCounts[zone.id] ?? _base[index];
  }

  List<CrowdSenseMetric> _metrics(
    List<CrowdSenseZone> zones,
    DateTime now, {
    required bool scenario,
  }) {
    return [
      for (var i = 0; i < zones.length; i++)
        CrowdSenseMetric(
          zone: zones[i],
          count: _countFor(zones[i], i, now, scenario: scenario),
          capacity: _capacity,
          isLive:
              !scenario &&
              (widget.readings.value[zones[i].id]?.isRecent(now) ?? false),
          closed: scenario && zones[i].id == _closed,
          rapidIncrease:
              !scenario &&
              (widget.readings.value[zones[i].id]?.isRecent(now) ?? false) &&
              CrowdSenseRouter.rapidlyIncreasing(
                _history[zones[i].id] ?? const [],
              ),
        ),
    ];
  }

  void _reset() {
    setState(() {
      _simulatedCounts.clear();
      _closed = '';
      _capacity = 3;
      _whatIf = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final zones = _zones();
    final now = DateTime.now();
    final actual = _metrics(zones, now, scenario: false);
    final evaluated = _whatIf ? _metrics(zones, now, scenario: true) : actual;
    final route = _whatIf ? CrowdSenseRouter.compute(evaluated) : null;
    final live = actual.where((m) => m.isLive).length;
    final high = evaluated
        .where((m) => !m.closed && m.risk == CrowdSenseRisk.high)
        .length;
    final routeNames = route == null
        ? 'No valid route. Reopen an attraction.'
        : route.nodeIds
              .map(
                (i) => i == 4
                    ? 'Entrance'
                    : i == 5
                    ? 'Exit'
                    : zones[i].name,
              )
              .join(' → ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: const Color(0xFFFFFAF7),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _rose.withValues(alpha: .3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 8,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Crowd Overview',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'See which attractions are getting crowded.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
                if (_whatIf)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Reset practice'),
                    onPressed: _reset,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _tag(
                  '$live live camera${live == 1 ? '' : 's'}',
                  live > 0 ? Colors.green.shade800 : Colors.blueGrey,
                ),
                if (_whatIf)
                  _tag(
                    '$high crowded area${high == 1 ? '' : 's'}',
                    high > 0 ? Colors.deepOrange : Colors.teal,
                  ),
                if (_whatIf) _tag('Practice mode', _rose),
              ],
            ),
            const SizedBox(height: 10),
            if (live == 0 && !_whatIf)
              const Text('No live crowd counts yet. Select View Camera below.'),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < evaluated.length; i++)
                  if (_whatIf || !evaluated[i].zone.isDemo)
                    SizedBox(
                      width: 205,
                      child: _zoneCard(i, evaluated[i], actual[i]),
                    ),
              ],
            ),
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Practice crowd planning',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Try different crowd counts or a closure. Live counts stay separate.',
              ),
              value: _whatIf,
              activeTrackColor: _rose.withValues(alpha: .55),
              onChanged: (value) => setState(() => _whatIf = value),
            ),
            if (_whatIf)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 230,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('closure-$_closed'),
                      initialValue: zones.any((z) => z.id == _closed)
                          ? _closed
                          : '',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Practice closure',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('None')),
                        for (final z in zones)
                          DropdownMenuItem(
                            value: z.id,
                            child: Text(
                              z.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _closed = v ?? ''),
                    ),
                  ),
                  SizedBox(
                    width: 245,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Crowded at $_capacity people',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Slider(
                          min: 2,
                          max: 12,
                          divisions: 10,
                          value: _capacity.toDouble(),
                          label: '$_capacity',
                          onChanged: (value) =>
                              setState(() => _capacity = value.round()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            if (_whatIf) ...[
              Text(
                'Practice route',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(routeNames),
              const Text(
                'For planning practice only. Follow posted paths in the park.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _zoneCard(
    int index,
    CrowdSenseMetric metric,
    CrowdSenseMetric actual,
  ) {
    final color = metric.closed || !_whatIf
        ? (metric.isLive ? Colors.teal.shade700 : Colors.blueGrey)
        : switch (metric.risk) {
            CrowdSenseRisk.low => Colors.teal.shade700,
            CrowdSenseRisk.medium => Colors.orange.shade800,
            CrowdSenseRisk.high => Colors.deepOrange.shade800,
          };
    final value = _simulatedCounts[metric.zone.id] ?? _base[index];
    final hasCount = _whatIf || metric.isLive;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.zone.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          if (hasCount)
            Row(
              children: [
                Text(
                  '${metric.count}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 27,
                    color: color,
                  ),
                ),
                const Text(' people', style: TextStyle(fontSize: 12)),
                const Spacer(),
                Icon(metric.closed ? Icons.block : Icons.groups, color: color),
              ],
            ),
          Text(
            metric.closed
                ? 'Closed for practice'
                : _whatIf
                ? 'Practice count'
                : metric.isLive
                ? 'Live camera'
                : 'No live count',
            style: TextStyle(fontSize: 12, color: color),
          ),
          if (_whatIf && !metric.closed)
            Text(switch (metric.risk) {
              CrowdSenseRisk.low => 'Quiet',
              CrowdSenseRisk.medium => 'Getting busy',
              CrowdSenseRisk.high => 'Crowded',
            }, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          if (metric.rapidIncrease) const Text('The crowd is growing quickly.'),
          if (_whatIf && actual.isLive) Text('Live count: ${actual.count}'),
          if (_whatIf)
            Slider(
              min: 0,
              max: 12,
              divisions: 12,
              value: value.toDouble(),
              label: '$value',
              onChanged: (newValue) => setState(
                () => _simulatedCounts[metric.zone.id] = newValue.round(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: .25)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}
