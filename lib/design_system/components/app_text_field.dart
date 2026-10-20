import 'package:flutter/material.dart';

class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
    this.keyboardType,
    this.password = false,
    this.hint,
    this.enabled = true,
    this.autofillHints,
    this.onChanged,
    this.prefixIcon,
  });
  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool password, enabled;
  final String? hint;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final IconData? prefixIcon;
  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool hidden = true;
  // A field scrolls its text, not the surrounding page or expansion tile.
  final textScroll = ScrollController(keepScrollOffset: false);
  @override
  void dispose() {
    textScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    scrollController: textScroll,
    controller: widget.controller,
    onChanged: widget.onChanged,
    validator: widget.validator,
    keyboardType: widget.keyboardType,
    enabled: widget.enabled,
    autofillHints: widget.autofillHints,
    obscureText: widget.password && hidden,
    autocorrect: !widget.password,
    enableSuggestions: !widget.password,
    style: const TextStyle(fontSize: 16),
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon),
      suffixIcon: widget.password
          ? IconButton(
              tooltip: hidden ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => hidden = !hidden),
              icon: Icon(
                hidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            )
          : null,
    ),
  );
}
