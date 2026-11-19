import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../admin_widgets.dart';

/// Shared visual system for ALL workforce dialogs (create, edit, train,
/// status, confirmation, and catalogue). Using one component prevents the
/// alternating pink AlertDialog / white Dialog styles seen previously.
class StaffDialogFrame extends StatelessWidget {
  const StaffDialogFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.actions,
    this.maxWidth = 620,
    this.maxHeight = 670,
    this.onClose,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;
  final double maxHeight;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: const Color(0xFFFFF9F7),
    surfaceTintColor: Colors.transparent,
    elevation: 18,
    shadowColor: const Color(0x55000000),
    insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFE8DAD7)),
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: math.min(maxHeight, MediaQuery.sizeOf(context).height - 38),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 22, 18, 18),
            child: Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w700,
                    color: adminDark,
                  )),
                  const SizedBox(height: 5),
                  Text(subtitle, style: const TextStyle(
                    fontSize: 13, color: adminMuted,
                  )),
                ],
              )),
              if (onClose != null) IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close, color: adminMuted),
              ),
            ]),
          ),
          const Divider(height: 1, color: adminBorder),
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 20, 26, 20),
            child: child,
          )),
          const Divider(height: 1, color: adminBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 14, 26, 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i != 0) const SizedBox(width: 10),
                  actions[i],
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class StaffFieldLabel extends StatelessWidget {
  const StaffFieldLabel(this.value, {super.key});
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(value, style: const TextStyle(
      fontSize: 13, fontWeight: FontWeight.w600, color: adminDark,
    )),
  );
}
