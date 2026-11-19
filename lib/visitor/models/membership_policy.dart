/// Shared membership rules for the admin portal and visitor rewards.
/// Membership is based on cumulative earned points, not the spendable balance.
/// Display-only descriptions and perk labels do NOT grant redeemable benefits.
class MembershipLevel {
  final String key;
  final String name;
  final int minPoints;
  final String description;
  final List<String> highlights;
  final String colorKey;
  /// Structured benefit settings only; a trusted backend must fulfil grants.
  final int upgradeBonusPoints;
  final String foodVoucherRewardId;

  const MembershipLevel(
    this.key,
    this.name,
    this.minPoints, {
    this.description = '',
    this.highlights = const [],
    this.colorKey = 'rose',
    this.upgradeBonusPoints = 0,
    this.foodVoucherRewardId = '',
  });

  Map<String, Object> toMap() => {
    'key': key,
    'name': name,
    'minPoints': minPoints,
    'description': description,
    'highlights': highlights,
    'colorKey': colorKey,
    'upgradeBonusPoints': upgradeBonusPoints,
    'foodVoucherRewardId': foodVoucherRewardId,
  };
}

class MembershipPolicy {
  final List<MembershipLevel> levels;
  const MembershipPolicy(this.levels);

  static const defaults = MembershipPolicy([
    MembershipLevel('normal', 'Normal', 0, colorKey: 'rose'),
    MembershipLevel('silver', 'Silver', 500, colorKey: 'slate'),
    MembershipLevel('gold', 'Gold', 1500, colorKey: 'gold'),
    MembershipLevel('platinum', 'Platinum', 3000, colorKey: 'violet'),
  ]);

  static const keys = ['normal', 'silver', 'gold', 'platinum'];
  static const colorKeys = ['rose', 'slate', 'gold', 'violet', 'teal'];

  static MembershipPolicy fromMap(Map<String, dynamic>? data) {
    final raw = data?['levels'];
    if (raw is! List || raw.length != keys.length) return defaults;
    try {
      final parsed = <MembershipLevel>[];
      for (var i = 0; i < keys.length; i++) {
        final level = Map<String, dynamic>.from(raw[i] as Map);
        final key = level['key'];
        final name = level['name'];
        final threshold = level['minPoints'];
        if (key != keys[i] || name is! String || threshold is! int) {
          return defaults;
        }
        final description = level['description'];
        final highlightValues = level['highlights'];
        final colorKey = level['colorKey'];
        final upgradeBonusPoints = level['upgradeBonusPoints'];
        final foodVoucherRewardId = level['foodVoucherRewardId'];
        if (description != null && description is! String) return defaults;
        if (highlightValues != null && highlightValues is! List) return defaults;
        if (colorKey != null && colorKey is! String) return defaults;
        if (upgradeBonusPoints != null && upgradeBonusPoints is! int) return defaults;
        if (foodVoucherRewardId != null && foodVoucherRewardId is! String) return defaults;
        parsed.add(MembershipLevel(
          key as String,
          name,
          threshold,
          description: description as String? ?? '',
          highlights: highlightValues == null
              ? const []
              : List<String>.from(highlightValues),
          colorKey: colorKey as String? ?? defaults.levels[i].colorKey,
          upgradeBonusPoints: upgradeBonusPoints as int? ?? 0,
          foodVoucherRewardId: foodVoucherRewardId as String? ?? '',
        ));
      }
      if (validationError(parsed) != null) return defaults;
      return MembershipPolicy(parsed);
    } catch (_) {
      return defaults;
    }
  }

  /// Returns null for a valid policy, or a user-facing validation error.
  static String? validationError(List<MembershipLevel> values) {
    if (values.length != keys.length) return 'Four membership levels are required.';
    final names = <String>{};
    for (var i = 0; i < values.length; i++) {
      final level = values[i];
      if (level.key != keys[i]) return 'The membership levels must stay in their original order.';
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9 &-]{1,23}$').hasMatch(level.name.trim())) {
        return 'Use a 2-24 character English name for each level.';
      }
      if (!names.add(level.name.trim().toLowerCase())) {
        return 'Each level needs a different name.';
      }
      if (level.minPoints < 0 || level.minPoints > 10000000) {
        return 'Point thresholds must be between 0 and 10,000,000.';
      }
      if (i == 0 && level.minPoints != 0) return 'The first level must start at 0 points.';
      if (i > 0 && level.minPoints <= values[i - 1].minPoints) {
        return 'Each higher level must require more earned points.';
      }
      if (level.description.length > 100) {
        return 'Keep each tier description to 100 characters or fewer.';
      }
      if (level.highlights.length > 3 ||
          level.highlights.any((item) => item.trim().isEmpty || item.length > 70)) {
        return 'Enter up to 3 short benefit descriptions per level (max 70 characters each).';
      }
      if (level.upgradeBonusPoints < 0 || level.upgradeBonusPoints > 10000) {
        return 'Upgrade bonus must be between 0 and 10,000 points.';
      }
      if (level.foodVoucherRewardId.isNotEmpty &&
          !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(level.foodVoucherRewardId)) {
        return 'Use the ID of an existing food reward (letters, numbers, - or _).';
      }
      if (!colorKeys.contains(level.colorKey)) {
        return 'Choose a valid membership badge colour.';
      }
    }
    return null;
  }

  MembershipLevel forEarned(int points) {
    var result = levels.first;
    for (final level in levels) {
      if (points >= level.minPoints) result = level;
    }
    return result;
  }

  int nextIndexFor(int points) {
    for (var i = 0; i < levels.length; i++) {
      if (points < levels[i].minPoints) return i;
    }
    return -1;
  }
}
