import 'dart:math' as math;

/// The demo uses real camera readings where available and clearly labelled
/// scenario values for other zones. It does not claim calibrated safety scores.
class CrowdSenseZone {
  const CrowdSenseZone({
    required this.id,
    required this.name,
    required this.mapX,
    required this.mapY,
    required this.isDemo,
  });

  final String id;
  final String name;
  final double mapX;
  final double mapY;
  final bool isDemo;
}

class CrowdSensorReading {
  const CrowdSensorReading(this.count, this.receivedAt);
  final int count;
  final DateTime receivedAt;

  bool isRecent(DateTime now) =>
      now.difference(receivedAt).inSeconds >= 0 &&
      now.difference(receivedAt).inSeconds <= 15;
}

enum CrowdSenseRisk { low, medium, high }

class CrowdSenseMetric {
  const CrowdSenseMetric({
    required this.zone,
    required this.count,
    required this.capacity,
    required this.isLive,
    this.next30Seconds,
    this.rapidIncrease = false,
    this.closed = false,
  });
  final CrowdSenseZone zone;
  final int count;
  final int capacity;
  final bool isLive;
  final int? next30Seconds;
  final bool rapidIncrease;
  final bool closed;

  double get load => count / math.max(capacity, 1);
  CrowdSenseRisk get risk => count >= capacity
      ? CrowdSenseRisk.high
      : count >= capacity * .6
          ? CrowdSenseRisk.medium
          : CrowdSenseRisk.low;

  // This is an interpretable cost heuristic, not a measured wait-time model.
  double get congestionCost =>
      math.min(load, 4) * 11 + (rapidIncrease ? 5 : 0);
}

class CrowdSenseRoute {
  const CrowdSenseRoute(this.nodeIds, this.cost);
  final List<int> nodeIds;
  final double cost;
}

/// A six-node *demonstration graph*. Edges are deliberately fixed and must
/// not be represented as verified walkable paths around TAR UMT buildings.
class CrowdSenseRouter {
  static const positions = <math.Point<double>>[
    math.Point(.29, .22), // zone A
    math.Point(.29, .78), // zone B
    math.Point(.70, .22), // zone C
    math.Point(.70, .78), // zone D
    math.Point(.06, .50), // entrance
    math.Point(.94, .50), // exit
  ];

  static const links = <(int, int)>[
    (4, 0), (4, 1), (0, 2), (0, 3),
    (1, 2), (1, 3), (2, 5), (3, 5),
  ];

  static CrowdSenseRoute? compute(List<CrowdSenseMetric> metrics) {
    if (metrics.length != 4) return null;
    const start = 4, end = 5, n = 6;
    final dist = List<double>.filled(n, double.infinity);
    final previous = List<int?>.filled(n, null);
    final visited = List<bool>.filled(n, false);
    dist[start] = 0;

    for (var i = 0; i < n; i++) {
      int current = -1;
      for (var j = 0; j < n; j++) {
        if (!visited[j] && (current == -1 || dist[j] < dist[current])) {
          current = j;
        }
      }
      if (current == -1 || dist[current].isInfinite) break;
      if (current == end) break;
      visited[current] = true;
      for (final (a, b) in links) {
        final neighbour = a == current ? b : b == current ? a : -1;
        if (neighbour < 0 || visited[neighbour]) continue;
        if (current < 4 && metrics[current].closed) continue;
        if (neighbour < 4 && metrics[neighbour].closed) continue;
        final walk = 1 + positions[current].distanceTo(positions[neighbour]) * 8;
        final crowd = neighbour < 4 ? metrics[neighbour].congestionCost : 0.0;
        final candidate = dist[current] + walk + crowd;
        if (candidate < dist[neighbour]) {
          dist[neighbour] = candidate;
          previous[neighbour] = current;
        }
      }
    }
    if (dist[end].isInfinite) return null;
    final nodes = <int>[];
    int? at = end;
    while (at != null) {
      nodes.insert(0, at);
      at = previous[at];
    }
    return CrowdSenseRoute(nodes, dist[end]);
  }

  static int? predict30Seconds(List<CrowdSensorReading> readings, int capacity) {
    if (readings.length < 3) return null;
    final first = readings.first;
    final last = readings.last;
    final span = last.receivedAt.difference(first.receivedAt).inMilliseconds / 1000;
    if (span < 6) return null;
    final changePerSecond = (last.count - first.count) / span;
    // Clamp the extrapolation to keep a noisy detector from producing huge values.
    final prediction = (last.count + changePerSecond * 30).round();
    return prediction.clamp(0, math.max(capacity * 4, 12)).toInt();
  }

  static bool rapidlyIncreasing(List<CrowdSensorReading> readings) {
    if (readings.length < 2) return false;
    final recent = readings.where(
      (r) => readings.last.receivedAt.difference(r.receivedAt).inSeconds <= 10,
    ).toList();
    return recent.length >= 2 &&
        recent.last.count - recent.first.count >= 2;
  }
}
