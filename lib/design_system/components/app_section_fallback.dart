import 'package:flutter/material.dart';

/// Calm stand-in for a section that could not load and has nothing to show.
/// Sections with data keep showing it instead of an error.
class AppSectionFallback extends StatelessWidget {
  const AppSectionFallback({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 20, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: muted)),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
