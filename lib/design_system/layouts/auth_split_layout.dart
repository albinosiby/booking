import 'package:flutter/material.dart';
import '../tokens/app_theme.dart';

/// Pairs sign-in pages with a brand panel on wide web windows.
class AuthSplitLayout extends StatelessWidget {
  const AuthSplitLayout({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => c.maxWidth < 960
        ? child
        : Material(
            child: Row(
              children: [
                const Expanded(flex: 5, child: _BrandPanel()),
                Expanded(flex: 6, child: child),
              ],
            ),
          ),
  );
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();
  static const features = [
    (
      Icons.calendar_month_rounded,
      'Live calendar for every court, hall and pool',
    ),
    (Icons.event_note_rounded, 'Bookings, blocks and admissions in one list'),
    (Icons.account_balance_wallet_rounded, 'Income, expenses and reports'),
    (Icons.groups_rounded, 'Invite staff with the right access'),
  ];
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('auth-brand-panel'),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF14240D), AppColors.ink, Color(0xFF0B1407)],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          top: -160,
          right: -120,
          child: Container(
            width: 420,
            height: 420,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.lime.withValues(alpha: .28),
                  AppColors.lime.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(56, 48, 56, 40),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight - 88),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(13),
                              gradient: const LinearGradient(
                                colors: [AppColors.lime, AppColors.forest],
                              ),
                            ),
                            child: const Icon(
                              Icons.event_available_rounded,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Text(
                            'Booking OS',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.4,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const Text(
                        'Run every space\nfrom one screen.',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 44,
                          height: 1.08,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.6,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Bookings, staff and accounts for turfs, courts, halls and pools.',
                        style: TextStyle(
                          color: AppColors.white.withValues(alpha: .65),
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 36),
                      for (final (icon, label) in features)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: AppColors.lime.withValues(alpha: .12),
                                  border: Border.all(
                                    color: AppColors.lime.withValues(
                                      alpha: .25,
                                    ),
                                  ),
                                ),
                                child: Icon(
                                  icon,
                                  size: 18,
                                  color: AppColors.lime,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: AppColors.white.withValues(
                                      alpha: .85,
                                    ),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Spacer(),
                      Text(
                        '© ${DateTime.now().year} Booking OS',
                        style: TextStyle(
                          color: AppColors.white.withValues(alpha: .4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
