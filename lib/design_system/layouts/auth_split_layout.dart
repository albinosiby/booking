import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../components/booking_brand.dart';
import '../tokens/app_theme.dart';
import '../tokens/auth_layout.dart';

/// Tablet and phone use the focused form; desktop adds a quiet brand illustration.
class AuthSplitLayout extends StatelessWidget {
  const AuthSplitLayout({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => box.maxWidth < AuthLayout.desktopBreakpoint
        ? child
        : Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Row(
              children: [
                const Expanded(
                  flex: 5,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 24, 0, 24),
                    child: _BrandPanel(),
                  ),
                ),
                Expanded(flex: 6, child: child),
              ],
            ),
          ),
  );
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('auth-brand-panel'),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF172015), AppColors.ink, Color(0xFF161B13)],
      ),
    ),
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.all(40),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, box.maxHeight - 80),
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BookingBrand(color: AppColors.white),
                  const SizedBox(height: 48),
                  const Spacer(),
                  const Text(
                    'Your day,\nunder control.',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 40,
                      height: 1.12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Bookings, teams and accounts.\nOne place to keep things moving.',
                    style: TextStyle(
                      color: AppColors.white.withValues(alpha: .66),
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 36),
                  const _CalendarIllustration(),
                  const SizedBox(height: 48),
                  const Spacer(),
                  Wrap(
                    spacing: 22,
                    runSpacing: 12,
                    children: [
                      for (final (icon, text) in const [
                        (Icons.calendar_today_outlined, 'Bookings'),
                        (Icons.people_outline_rounded, 'Teams'),
                        (Icons.account_balance_wallet_outlined, 'Accounts'),
                      ])
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icon,
                              color: AppColors.lime.withValues(alpha: .8),
                              size: 16,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              text,
                              style: TextStyle(
                                color: AppColors.white.withValues(alpha: .65),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Decorative example, kept out of the real booking data and interactive focus order.
class _CalendarIllustration extends StatelessWidget {
  const _CalendarIllustration();

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Illustration of venue bookings in a weekly calendar',
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: .035),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.white.withValues(alpha: .09)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.calendar_month_outlined,
                  color: AppColors.lime,
                  size: 18,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'A calmer calendar',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  'PREVIEW',
                  style: TextStyle(
                    color: AppColors.white.withValues(alpha: .4),
                    fontSize: 9,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                for (final day in const ['M', 'T', 'W', 'T', 'F'])
                  Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          color: AppColors.white.withValues(alpha: .38),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 168,
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    Positioned.fill(
                      child: Row(
                        children: [
                          for (var column = 0; column < 5; column++)
                            Expanded(
                              child: Column(
                                children: [
                                  for (var row = 0; row < 4; row++)
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: BorderSide(
                                              color: AppColors.white.withValues(
                                                alpha: .04,
                                              ),
                                            ),
                                            bottom: BorderSide(
                                              color: AppColors.white.withValues(
                                                alpha: .04,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 5,
                      width: box.maxWidth * .55,
                      child: const _CalendarBooking(
                        label: 'Court booking',
                        time: '09:00 – 10:00',
                        highlighted: true,
                      ),
                    ),
                    Positioned(
                      top: 70,
                      left: box.maxWidth * .25,
                      right: 5,
                      child: const _CalendarBooking(
                        label: 'Pool session',
                        time: '11:00 – 12:00',
                      ),
                    ),
                    Positioned(
                      top: 130,
                      left: box.maxWidth * .05,
                      width: box.maxWidth * .47,
                      child: Container(
                        height: 27,
                        decoration: BoxDecoration(
                          color: AppColors.white.withValues(alpha: .035),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CalendarBooking extends StatelessWidget {
  const _CalendarBooking({
    required this.label,
    required this.time,
    this.highlighted = false,
  });
  final String label, time;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: highlighted
          ? AppColors.lime.withValues(alpha: .12)
          : AppColors.white.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(8),
      border: Border(
        left: BorderSide(
          color: highlighted
              ? AppColors.lime
              : AppColors.white.withValues(alpha: .3),
          width: 2,
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: highlighted
                ? AppColors.lime
                : AppColors.white.withValues(alpha: .8),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          time,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.white.withValues(alpha: .45),
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}
