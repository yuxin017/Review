import 'package:flutter_test/flutter_test.dart';
import 'package:collaborative_asg/visitor/models/membership_policy.dart';
import 'package:collaborative_asg/visitor/models/rewards.dart';

void main() {
  test('default membership follows lifetime earned points', () {
    expect(MembershipPolicy.defaults.forEarned(0).name, 'Normal');
    expect(MembershipPolicy.defaults.forEarned(499).name, 'Normal');
    expect(MembershipPolicy.defaults.forEarned(500).name, 'Silver');
    expect(MembershipPolicy.defaults.forEarned(1500).name, 'Gold');
    expect(MembershipPolicy.defaults.forEarned(3000).name, 'Platinum');
  });

  test('admin policy changes names and boundaries consistently', () {
    const custom = MembershipPolicy([
      MembershipLevel('normal', 'Starter', 0),
      MembershipLevel('silver', 'Explorer', 200),
      MembershipLevel('gold', 'VIP', 850),
      MembershipLevel('platinum', 'Legend', 2500),
    ]);
    expect(MembershipPolicy.validationError(custom.levels), isNull);
    final policy = MembershipPolicy.fromMap({
      'levels': custom.levels.map((tier) => tier.toMap()).toList(),
    });
    expect(policy.forEarned(300).name, 'Explorer');
    expect(RewardsTier.forEarned(1000, policy).name, 'VIP');
    expect(RewardsTier.forEarned(1000, policy).remaining, 1500);
  });

  test('custom membership appearance and descriptions round-trip', () {
    const custom = MembershipPolicy([
      MembershipLevel('normal', 'Explorer', 0,
        description: 'Every adventure starts somewhere',
        highlights: ['Member-only news'], colorKey: 'teal',
        upgradeBonusPoints: 150, foodVoucherRewardId: 'dining_10'),
      MembershipLevel('silver', 'Voyager', 400, colorKey: 'slate'),
      MembershipLevel('gold', 'Guardian', 1200, colorKey: 'gold'),
      MembershipLevel('platinum', 'Legend', 2500, colorKey: 'violet'),
    ]);
    expect(MembershipPolicy.validationError(custom.levels), isNull);
    final restored = MembershipPolicy.fromMap({
      'levels': custom.levels.map((level) => level.toMap()).toList(),
    });
    expect(restored.levels.first.description, 'Every adventure starts somewhere');
    expect(restored.levels.first.highlights, ['Member-only news']);
    expect(restored.levels.first.colorKey, 'teal');
    expect(restored.levels.first.upgradeBonusPoints, 150);
    expect(restored.levels.first.foodVoucherRewardId, 'dining_10');
    expect(restored.forEarned(401).name, 'Voyager');
  });

  test('old saved membership documents remain compatible', () {
    final oldLevels = [
      {'key': 'normal', 'name': 'Normal', 'minPoints': 0},
      {'key': 'silver', 'name': 'Silver', 'minPoints': 500},
      {'key': 'gold', 'name': 'Gold', 'minPoints': 1500},
      {'key': 'platinum', 'name': 'Platinum', 'minPoints': 3000},
    ];
    final restored = MembershipPolicy.fromMap({'levels': oldLevels});
    expect(restored.levels[2].name, 'Gold');
    expect(restored.levels[2].highlights, isEmpty);
  });

  test('long benefit labels are rejected', () {
    final invalid = [
      const MembershipLevel('normal', 'Normal', 0,
        highlights: ['An extremely long benefit description that is too long for the user interface card and would overflow']),
      ...MembershipPolicy.defaults.levels.skip(1),
    ];
    expect(MembershipPolicy.validationError(invalid), isNotNull);
  });

  test('invalid structured membership benefits are rejected', () {
    final invalid = [
      const MembershipLevel('normal', 'Normal', 0, upgradeBonusPoints: -10),
      ...MembershipPolicy.defaults.levels.skip(1),
    ];
    expect(MembershipPolicy.validationError(invalid), isNotNull);
  });

  test('invalid thresholds cannot be saved', () {
    const invalid = [
      MembershipLevel('normal', 'Normal', 0),
      MembershipLevel('silver', 'Silver', 1000),
      MembershipLevel('gold', 'Gold', 500),
      MembershipLevel('platinum', 'Platinum', 3000),
    ];
    expect(MembershipPolicy.validationError(invalid), isNotNull);
    expect(MembershipPolicy.fromMap({
      'levels': invalid.map((level) => level.toMap()).toList(),
    }).levels[1].minPoints, 500);
  });
}
