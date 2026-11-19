import 'package:flutter/material.dart';
import '../portal/admin_theme.dart';

class AttractionEditorSection extends StatelessWidget {
  const AttractionEditorSection({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.child,
  });

  final String title;
  final String description;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE7D8D5)),
      boxShadow: const [BoxShadow(
        color: Color(0x0C000000), blurRadius: 16, offset: Offset(0, 4),
      )],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 21, color: AdminTheme.rose),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700,
            color: AdminTheme.ink,
          ))),
        ]),
        if (description.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(description, style: const TextStyle(
            fontSize: 12, color: AdminTheme.muted,
          )),
        ],
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}
