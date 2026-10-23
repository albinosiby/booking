import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';

/// Visible labels and keyboard actions specific to the compact auth forms.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
    required this.autofillHints,
    this.hint,
    this.validator,
    this.focusNode,
    this.password = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.labelAction,
  });
  final String label;
  final String? hint;
  final IconData icon;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;
  final Iterable<String> autofillHints;
  final bool password, enabled;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? labelAction;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (widget.labelAction != null)
              Flexible(child: widget.labelAction!),
          ],
        ),
        const SizedBox(height: 8),
        Semantics(
          label: widget.label,
          child: TextFormField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            validator: widget.validator,
            enabled: widget.enabled,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onFieldSubmitted: widget.onSubmitted,
            autofillHints: widget.autofillHints,
            obscureText: widget.password && _hidden,
            autocorrect:
                !widget.password &&
                widget.keyboardType != TextInputType.emailAddress,
            enableSuggestions: !widget.password,
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
            decoration: InputDecoration(
              hintText: widget.hint,
              fillColor: theme.scaffoldBackgroundColor,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 17,
              ),
              constraints: const BoxConstraints(
                minHeight: AuthLayout.fieldHeight,
              ),
              prefixIcon: Icon(
                widget.icon,
                size: 19,
                color: scheme.onSurface.withValues(alpha: .45),
              ),
              hintStyle: TextStyle(
                color: scheme.onSurface.withValues(alpha: .38),
                fontSize: 14,
              ),
              errorMaxLines: 3,
              suffixIcon: widget.password
                  ? IconButton(
                      tooltip: _hidden ? 'Show password' : 'Hide password',
                      onPressed: widget.enabled
                          ? () => setState(() => _hidden = !_hidden)
                          : null,
                      icon: Icon(
                        _hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 19,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
