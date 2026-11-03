import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class HomeGreetingCard extends StatefulWidget {
  const HomeGreetingCard({
    super.key,
    required this.name,
    required this.organization,
    this.logo,
    this.heroImage,
    this.onWebsite,
    this.onAlerts,
    this.hasAlerts = false,
    this.onProfile,
  });

  final String name, organization;
  final Uint8List? logo, heroImage;
  final VoidCallback? onWebsite, onAlerts, onProfile;
  final bool hasAlerts;

  @override
  State<HomeGreetingCard> createState() => _HomeGreetingCardState();
}

class _HomeGreetingCardState extends State<HomeGreetingCard>
    with WidgetsBindingObserver {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  late DateTime now;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    now = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
  }

  void refresh() {
    if (mounted) setState(() => now = DateTime.now());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String get _initials {
    final parts = widget.organization.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'B';
    return parts.length > 1
        ? '${parts.first[0]}${parts[1][0]}'.toUpperCase()
        : parts.first
              .substring(0, parts.first.length.clamp(0, 2))
              .toUpperCase();
  }

  Widget _avatar(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF092B18), Color(0xFF22C815)],
      ),
      border: Border.all(color: const Color(0xFF8FE770).withValues(alpha: .3)),
    ),
    clipBehavior: Clip.antiAlias,
    alignment: Alignment.center,
    child: widget.logo == null
        ? Text(
            _initials,
            style: TextStyle(
              color: Colors.white,
              fontSize: size * .37,
              fontWeight: FontWeight.w800,
            ),
          )
        : Image.memory(
            widget.logo!,
            fit: BoxFit.cover,
            width: size,
            height: size,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => Text(
              _initials,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * .37,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstName = widget.name.trim().split(RegExp(r'\s+')).first;
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final scaled = MediaQuery.textScalerOf(context).scale(14);
    final compact = scaled > 20;
    final date =
        '${_days[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}';
    const foreground = Colors.white;

    Widget fallback() => Image.asset(
      'assets/branding/turf_booking_fallback.png',
      key: const ValueKey('home-hero-fallback'),
      fit: BoxFit.cover,
      excludeFromSemantics: true,
    );

    final dateBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        date,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
              child: Row(
                children: [
                  _avatar(compact ? 48 : 56),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.organization,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Sports & Turf Booking',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onAlerts != null) ...[
                    const SizedBox(width: 4),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          tooltip: 'Review payments to collect',
                          onPressed: widget.onAlerts,
                          icon: const Icon(Icons.notifications_none_outlined),
                        ),
                        if (widget.hasAlerts)
                          Positioned(
                            top: 6,
                            right: 8,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF3042),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (widget.onProfile != null)
                    IconButton(
                      tooltip: 'Profile',
                      onPressed: widget.onProfile,
                      icon: const Icon(Icons.account_circle_outlined),
                    ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: const Color(0xFF082E22),
                border: Border.all(
                  color: const Color(0xFF73D747).withValues(alpha: .35),
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRect(
                      child: Transform.scale(
                        scale: widget.heroImage == null ? 2.1 : 1,
                        alignment: Alignment.centerRight,
                        child: Opacity(
                          opacity: .84,
                          child: widget.heroImage == null
                              ? fallback()
                              : Image.memory(
                                  widget.heroImage!,
                                  key: const ValueKey('home-hero-uploaded'),
                                  fit: BoxFit.cover,
                                  excludeFromSemantics: true,
                                  errorBuilder: (_, _, _) => fallback(),
                                ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            const Color(0xFF06291D).withValues(alpha: .94),
                            const Color(0xFF06291D).withValues(alpha: .72),
                            const Color(0xFF06291D).withValues(alpha: .22),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(wide ? 28 : 20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: wide ? 190 : 165),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (compact) ...[
                            Align(
                              alignment: Alignment.centerRight,
                              child: dateBadge,
                            ),
                            const SizedBox(height: 14),
                            _greeting(theme, greeting, firstName),
                          ] else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _greeting(theme, greeting, firstName),
                                ),
                                const SizedBox(width: 8),
                                dateBadge,
                              ],
                            ),
                          const SizedBox(height: 8),
                          Text(
                            'Manage your bookings, payments and schedule.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: foreground.withValues(alpha: .9),
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (widget.onWebsite != null)
                            SizedBox(
                              width: (constraints.maxWidth - (wide ? 56 : 40))
                                  .clamp(0.0, 260.0),
                              child: OutlinedButton(
                                key: const ValueKey('home-booking-website'),
                                onPressed: widget.onWebsite,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: foreground,
                                  backgroundColor: const Color(
                                    0xFF154A28,
                                  ).withValues(alpha: .54),
                                  side: BorderSide(
                                    color: foreground.withValues(alpha: .58),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.language_outlined, size: 18),
                                    SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        'Booking website',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 9),
                                    Icon(Icons.north_east_rounded, size: 18),
                                  ],
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
          ],
        );
      },
    );
  }

  Widget _greeting(ThemeData theme, String greeting, String firstName) =>
      Semantics(
        header: true,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Text(
              firstName.isEmpty ? greeting : '$greeting, $firstName',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: -.5,
              ),
            ),
            const Text('👋', style: TextStyle(fontSize: 23)),
          ],
        ),
      );
}
