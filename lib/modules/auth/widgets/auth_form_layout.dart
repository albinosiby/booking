import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';

/// Centers short forms and scrolls naturally when the keyboard or text needs room.
class AuthFormLayout extends StatelessWidget {
  const AuthFormLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.footer,
    this.eyebrow,
    this.error,
    this.notice,
  });
  final String title, subtitle;
  final String? eyebrow, error, notice;
  final Widget child, footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final desktop =
        MediaQuery.sizeOf(context).width >= AuthLayout.desktopBreakpoint;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final padding = EdgeInsets.symmetric(
              horizontal: AuthLayout.gutter,
              vertical: desktop ? 36 : 24,
            );
            return SingleChildScrollView(
              key: const PageStorageKey('auth-form-scroll'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: padding,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(0, box.maxHeight - padding.vertical),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AuthLayout.formWidth,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!desktop) ...[
                          const Center(child: BookingBrand()),
                          const SizedBox(height: 28),
                        ],
                        DecoratedBox(
                          key: const ValueKey('auth-form-card'),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(
                              AuthLayout.cardRadius,
                            ),
                            border: Border.all(
                              color: scheme.outline.withValues(
                                alpha: dark ? .55 : .65,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: dark ? .12 : .035,
                                ),
                                blurRadius: 32,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(desktop ? 32 : 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (eyebrow != null) ...[
                                  Text(
                                    eyebrow!,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.primary,
                                      letterSpacing: 1.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                Text(
                                  title,
                                  style: theme.textTheme.headlineLarge
                                      ?.copyWith(
                                        fontSize: 28,
                                        letterSpacing: -1,
                                        height: 1.15,
                                      ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  subtitle,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurface.withValues(
                                      alpha: .7,
                                    ),
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                if (error != null || notice != null) ...[
                                  _AuthFeedback(
                                    message: error ?? notice!,
                                    isError: error != null,
                                  ),
                                  const SizedBox(height: 20),
                                ],
                                child,
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        footer,
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AuthFeedback extends StatelessWidget {
  const _AuthFeedback({required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : scheme.primary;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.info_outline_rounded,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isError ? scheme.error : scheme.onSurface,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
