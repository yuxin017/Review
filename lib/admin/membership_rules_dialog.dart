import 'package:flutter/material.dart';
import '../visitor/models/membership_policy.dart';
import 'admin_widgets.dart';

Color membershipAccent(String key) => switch (key) {
  'slate' => const Color(0xFF687E94),
  'gold' => const Color(0xFFA67B30),
  'violet' => const Color(0xFF8271A0),
  'teal' => const Color(0xFF3B887B),
  _ => const Color(0xFFB47778),
};

/// Compact two-pane editor. Benefit settings are plans only until a trusted
/// backend handles upgrade grants.
class MembershipRulesDialog extends StatefulWidget {
  final MembershipPolicy current;
  final List<Map<String, dynamic>> foodRewards;
  const MembershipRulesDialog({super.key, required this.current,
    this.foodRewards = const []});

  @override
  State<MembershipRulesDialog> createState() => _MembershipRulesDialogState();
}

class _MembershipRulesDialogState extends State<MembershipRulesDialog> {
  static const ink = Color(0xFF342B2C);
  static const muted = Color(0xFF7F6B69);
  static const stroke = Color(0xFFE6D8D2);
  static const paper = Color(0xFFF7EFEB);
  int selected = 0;
  bool showBenefits = false;
  String? error;
  late final List<TextEditingController> names;
  late final List<TextEditingController> thresholds;
  late final List<TextEditingController> descriptions;
  late final List<TextEditingController> highlights;
  late final List<TextEditingController> bonuses;
  late final List<String> voucherIds;
  late final List<String> colors;

  @override
  void initState() {
    super.initState();
    final levels = widget.current.levels;
    names = levels.map((e) => TextEditingController(text: e.name)).toList();
    thresholds = levels.map((e) => TextEditingController(text: '${e.minPoints}')).toList();
    descriptions = levels.map((e) => TextEditingController(text: e.description)).toList();
    highlights = levels.map((e) => TextEditingController(text: e.highlights.join('\n'))).toList();
    bonuses = levels.map((e) => TextEditingController(text: '${e.upgradeBonusPoints}')).toList();
    voucherIds = levels.map((e) => e.foodVoucherRewardId).toList();
    colors = levels.map((e) => e.colorKey).toList();
  }

  @override
  void dispose() {
    for (final c in [...names, ...thresholds, ...descriptions, ...highlights, ...bonuses]) {
      c.dispose();
    }
    super.dispose();
  }

  InputDecoration decoration(String label, {String? hint}) => InputDecoration(
    labelText: label, hintText: hint, counterText: '',
    labelStyle: const TextStyle(fontSize: 13, color: muted),
    filled: true, fillColor: const Color(0xFFFFFAF7),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: stroke)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: adminRose, width: 1.4)),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );

  Widget field(TextEditingController control, String label,
      {bool number = false, bool enabled = true, int lines = 1,
       String? hint, int? maxLength}) => TextField(
    controller: control, enabled: enabled, maxLines: lines,
    maxLength: maxLength,
    keyboardType: number ? TextInputType.number : TextInputType.text,
    onChanged: (_) => setState(() => error = null),
    style: const TextStyle(fontSize: 14, color: ink),
    decoration: decoration(label, hint: hint),
  );

  void save() {
    final list = <MembershipLevel>[];
    for (var i = 0; i < names.length; i++) {
      final min = int.tryParse(thresholds[i].text.trim());
      final bonus = int.tryParse(bonuses[i].text.trim());
      if (min == null || bonus == null) {
        setState(() { selected = i; error = 'Enter whole numbers for points.'; });
        return;
      }
      if (i == 0) {
        // Normal is the permanent default tier. No one can edit its identity.
        list.add(widget.current.levels[i]);
        continue;
      }
      list.add(MembershipLevel(widget.current.levels[i].key,
        names[i].text.trim(), min,
        description: descriptions[i].text.trim(),
        highlights: highlights[i].text.split('\n')
            .map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
        colorKey: colors[i],
        upgradeBonusPoints: bonus,
        foodVoucherRewardId: voucherIds[i],
      ));
    }
    final problem = MembershipPolicy.validationError(list);
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    Navigator.pop(context, MembershipPolicy(list));
  }

  Widget tierSelector(int i, {bool compact = false}) {
    final chosen = selected == i;
    final color = membershipAccent(colors[i]);
    return InkWell(
      onTap: () => setState(() { selected = i; showBenefits = false; error = null; }),
      borderRadius: BorderRadius.circular(13),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: chosen ? color.withValues(alpha: .13) : const Color(0xFFFDF8F5),
          border: Border.all(color: chosen ? color : stroke,
            width: chosen ? 1.5 : 1),
          borderRadius: BorderRadius.circular(13)),
        child: Row(mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            CircleAvatar(radius: 15, backgroundColor: color.withValues(alpha: .18),
              child: Text('${i + 1}', style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700, color: color))),
            const SizedBox(width: 9),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(names[i].text.isEmpty ? 'Level ${i + 1}' : names[i].text,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: ink)),
              Text(i == 0 ? 'Default · locked' : '${thresholds[i].text} earned points',
                style: const TextStyle(color: muted, fontSize: 11)),
            ]),
            if (i == 0) ...[
              const SizedBox(width: 7),
              const Icon(Icons.lock_outline, size: 14, color: muted),
            ],
          ]),
      ),
    );
  }

  Widget basics() => selected == 0
    ? Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: const Color(0xFFF3E9E4),
          borderRadius: BorderRadius.circular(14)),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.lock_outline, color: muted),
            SizedBox(width: 9), Text('Default Membership', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: ink))]),
          SizedBox(height: 10),
          Text('Every visitor starts as a Normal Member with 0 earned points. '
            'This level is fixed to keep new registrations consistent.',
            style: TextStyle(color: muted, height: 1.5)),
        ]),
      )
    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Level details', style: TextStyle(color: ink,
      fontWeight: FontWeight.w700, fontSize: 16)),
    const SizedBox(height: 12),
    LayoutBuilder(builder: (context, c) {
      final left = field(names[selected], 'Level name', maxLength: 24);
      final right = field(thresholds[selected], 'Points to unlock', number: true,
        enabled: selected != 0);
      if (c.maxWidth < 400) return Column(children: [left, const SizedBox(height: 12), right]);
      return Row(children: [Expanded(child: left), const SizedBox(width: 12),
        Expanded(child: right)]);
    }),
    const SizedBox(height: 12),
    field(descriptions[selected], 'Short member description',
      hint: 'e.g. Unlock more park rewards', maxLength: 100),
    const SizedBox(height: 12),
    const Text('Badge colour', style: TextStyle(
      color: ink, fontWeight: FontWeight.w600, fontSize: 13)),
    const SizedBox(height: 8),
    Wrap(spacing: 11, runSpacing: 8, children: [
      for (final item in const [
        ('rose','Warm rose'), ('slate','Slate blue'), ('gold','Gold'),
        ('violet','Violet'), ('teal','Teal')
      ]) Tooltip(message: item.$2,
        child: InkWell(
          onTap: () => setState(() => colors[selected] = item.$1),
          borderRadius: BorderRadius.circular(24),
          child: Container(width: 47, height: 47,
            decoration: BoxDecoration(color: membershipAccent(item.$1),
              shape: BoxShape.circle,
              border: Border.all(color: colors[selected] == item.$1
                ? ink : Colors.transparent, width: 3)),
            child: colors[selected] == item.$1
              ? const Icon(Icons.check, color: Colors.white, size: 22) : null),
        )),
    ]),
    const SizedBox(height: 5),
    const Text('Choose a colour from the palette.',
      style: TextStyle(fontSize: 11, color: muted)),
    const SizedBox(height: 16),
    Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(
      color: const Color(0xFFEADFD9), borderRadius: BorderRadius.circular(10)),
      child: Text(selected == 0
        ? 'Everyone starts at this level. The minimum is always 0 points.'
        : 'The next level unlocks automatically after enough lifetime points are earned.',
        style: const TextStyle(color: ink, fontSize: 12, height: 1.4))),
  ]);

  Widget benefits() {
    if (selected == 0) return basics();
    final selectedId = voucherIds[selected];
    final available = widget.foodRewards;
    final isKnown = available.any((e) => e['id'] == selectedId);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Upgrade Rewards', style: TextStyle(color: ink,
        fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 5),
      const Text('Choose a promotion reward for visitors who reach this level. Issuing it automatically requires backend integration.',
        style: TextStyle(color: muted, fontSize: 12, height: 1.35)),
      const SizedBox(height: 14),
      field(bonuses[selected], 'Extra points on upgrade', number: true,
        hint: 'e.g. 100'),
      const SizedBox(height: 13),
      DropdownButtonFormField<String>(
        value: selectedId,
        isExpanded: true,
        decoration: decoration('Promotion reward on upgrade'),
        items: [
          const DropdownMenuItem(value: '', child: Text('No reward selected')),
          if (selectedId.isNotEmpty && !isKnown)
            DropdownMenuItem(value: selectedId,
              child: Text('Previously selected voucher ($selectedId)',
                overflow: TextOverflow.ellipsis)),
          for (final reward in available)
            if (reward['id'] is String)
              DropdownMenuItem(value: reward['id'] as String,
                child: Text(reward['name']?.toString() ?? 'Dining reward',
                  overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (value) => setState(() => voucherIds[selected] = value ?? ''),
      ),
      if (available.isEmpty) ...[
        const SizedBox(height: 6),
        const Text('No active rewards in Promotions & Rewards. Create one there first.',
          style: TextStyle(color: muted, fontSize: 11)),
      ],
      const SizedBox(height: 14),
      field(highlights[selected], 'Other benefit descriptions (up to 3)',
        lines: 3, hint: 'One benefit per line'),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(
        color: const Color(0xFFEADFD9), borderRadius: BorderRadius.circular(10)),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: Color(0xFF9D6469), size: 19),
            SizedBox(width: 9),
            Expanded(child: Text(
              'Saving a benefit does not issue a voucher or points. It becomes active only after the server-side reward process is connected.',
              style: TextStyle(fontSize: 11, color: ink, height: 1.4))),
          ])),
    ]);
  }

  Widget editor() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: const Color(0xFFFCF8F5),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: stroke)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('${names[selected].text} Membership',
          style: const TextStyle(color: ink, fontSize: 18,
            fontWeight: FontWeight.bold))),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: membershipAccent(colors[selected])
            .withValues(alpha: .14), borderRadius: BorderRadius.circular(20)),
          child: Text('Level ${selected + 1}', style: TextStyle(
            color: membershipAccent(colors[selected]), fontSize: 12,
            fontWeight: FontWeight.w700))),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        _tab('Level Settings', false), const SizedBox(width: 8),
        _tab('Upgrade Rewards', true),
      ]),
      const SizedBox(height: 17),
      selected == 0 ? basics() : (showBenefits ? benefits() : basics()),
    ]),
  );

  Widget _tab(String name, bool isBenefits) => OutlinedButton(
    onPressed: () => setState(() => showBenefits = isBenefits),
    style: OutlinedButton.styleFrom(
      backgroundColor: showBenefits == isBenefits
        ? const Color(0xFFEAD8D3) : const Color(0xFFFFFCFA),
      foregroundColor: ink,
      side: BorderSide(color: showBenefits == isBenefits
        ? adminRose : stroke)),
    child: Text(name, style: const TextStyle(fontSize: 12)),
  );

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: paper,
    insetPadding: const EdgeInsets.all(14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 880,
      maxHeight: 680),
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(19, 16, 9, 12),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFEAD8D3),
                borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.workspace_premium_outlined,
                color: Color(0xFF9F6569), size: 23)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Manage Membership', style: TextStyle(
                  color: ink, fontSize: 22, fontWeight: FontWeight.bold)),
                SizedBox(height: 3),
                Text('Choose a level on the left, then edit only what you need.',
                  style: TextStyle(color: muted, fontSize: 12)),
              ])),
            IconButton(onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close)),
          ])),
        const Divider(height: 1, color: stroke),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 650;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              if (wide) Row(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 204,
                    child: Column(children: [
                      for (var i = 0; i < names.length; i++) ...[
                        tierSelector(i), const SizedBox(height: 9),
                      ],
                    ])),
                  const SizedBox(width: 14),
                  Expanded(child: editor()),
                ])
              else ...[
                SingleChildScrollView(scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (var i = 0; i < names.length; i++) ...[
                      tierSelector(i, compact: true),
                      const SizedBox(width: 8),
                    ],
                  ])),
                const SizedBox(height: 12),
                editor(),
              ],
              if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
                child: Text(error!, style: const TextStyle(
                  fontSize: 12, color: Color(0xFFAE3C45)))),
            ]),
          );
        })),
        const Divider(height: 1, color: stroke),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Row(children: [
            const Expanded(child: Text('Levels use lifetime earned points.',
              style: TextStyle(fontSize: 11, color: muted))),
            TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
            const SizedBox(width: 9),
            AdminButton('Save Changes', icon: Icons.check, onPressed: save),
          ])),
      ])),
  );
}
