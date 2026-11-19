import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../portal/admin_theme.dart';

/// Compact, validated numeric field with accessible increase/decrease actions.
/// Does not invent a value on load: old records may leave optional fields empty.
class AttractionNumberField extends StatelessWidget {
  const AttractionNumberField({
    super.key,
    required this.controller,
    required this.label,
    required this.min,
    required this.max,
    this.optional = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final int min;
  final int max;
  final bool optional;
  final bool enabled;

  String? validate(String? input) {
    final value = input?.trim() ?? '';
    if (value.isEmpty) return optional ? null : 'Enter $label.';
    final number = int.tryParse(value);
    if (number == null || number < min || number > max) {
      return 'Use $min–$max.';
    }
    return null;
  }

  void _change(int direction) {
    final current = int.tryParse(controller.text.trim());
    final next = current == null
        ? min
        : (current + direction).clamp(min, max);
    controller.value = TextEditingValue(
      text: '$next',
      selection: TextSelection.collapsed(offset: '$next'.length),
    );
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    enabled: enabled,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    autovalidateMode: AutovalidateMode.onUserInteraction,
    validator: validate,
    decoration: InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AdminTheme.border),
      ),
      suffixIconConstraints: const BoxConstraints(minWidth: 96, maxWidth: 104),
      suffixIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('decrease-$label'),
            tooltip: 'Decrease $label',
            icon: const Icon(Icons.remove_circle_outline, size: 21),
            onPressed: enabled ? () => _change(-1) : null,
            color: AdminTheme.rose,
            constraints: const BoxConstraints(minWidth: 42, minHeight: 44),
          ),
          IconButton(
            key: Key('increase-$label'),
            tooltip: 'Increase $label',
            icon: const Icon(Icons.add_circle_outline, size: 21),
            onPressed: enabled ? () => _change(1) : null,
            color: AdminTheme.rose,
            constraints: const BoxConstraints(minWidth: 42, minHeight: 44),
          ),
        ],
      ),
    ),
  );
}
