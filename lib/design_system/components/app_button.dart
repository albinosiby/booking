import 'package:flutter/material.dart';
import '../animations/app_loading_animation.dart';

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.icon,
    this.secondary = false,
    this.busyLabel,
  });
  final String label;
  final String? busyLabel;
  final VoidCallback? onPressed;
  final bool busy, secondary;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy) ...[
          AppSavingDots(
            color: secondary
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onPrimary,
          ),
          const SizedBox(width: 10),
        ] else if (icon != null) ...[
          Icon(icon, size: 19),
          const SizedBox(width: 9),
        ],
        Flexible(
          child: Text(
            busy ? busyLabel ?? label : label,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
    return Semantics(
      liveRegion: busy,
      value: busy ? 'In progress' : null,
      child: SizedBox(
        width: double.infinity,
        child: secondary
            ? OutlinedButton(onPressed: busy ? null : onPressed, child: child)
            : FilledButton(
                style: busy
                    ? FilledButton.styleFrom(
                        disabledBackgroundColor: Theme.of(
                          context,
                        ).colorScheme.primary,
                        disabledForegroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                      )
                    : null,
                onPressed: busy ? null : onPressed,
                child: child,
              ),
      ),
    );
  }
}
