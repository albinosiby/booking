import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_text_field.dart';

/// Controllers are presentation objects; field values belong to the wizard Cubit.
class ConfigurationField extends StatefulWidget {
  const ConfigurationField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.numeric = false,
    this.validator,
    this.prefixIcon,
    this.keyboardType,
  });
  final String label, value;
  final ValueChanged<String> onChanged;
  final bool enabled, numeric;
  final String? Function(String?)? validator;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  @override
  State<ConfigurationField> createState() => _ConfigurationFieldState();
}

class _ConfigurationFieldState extends State<ConfigurationField> {
  late final controller = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(ConfigurationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller.text != widget.value) {
      final offset = controller.selection.baseOffset;
      controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(
          offset: math.min(math.max(offset, 0), widget.value.length),
        ),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppTextField(
    label: widget.label,
    controller: controller,
    onChanged: widget.onChanged,
    enabled: widget.enabled,
    prefixIcon: widget.prefixIcon,
    keyboardType:
        widget.keyboardType ??
        (widget.numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text),
    validator: widget.validator,
  );
}
