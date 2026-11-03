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
  });
  final String name, organization;
  final Uint8List? logo, heroImage;
  final VoidCallback? onWebsite;
  @override
  State<HomeGreetingCard> createState() => _HomeGreetingCardState();
}

class _HomeGreetingCardState extends State<HomeGreetingCard>
    with WidgetsBindingObserver {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstName = widget.name.trim().split(RegExp(r'\s+')).first;
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    const foreground = Colors.white;
    Widget mark(double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.logo == null
          ? Icon(Icons.business_outlined, color: foreground, size: size / 2)
          : Image.memory(
              widget.logo!,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.business_outlined, color: foreground),
            ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 600 &&
            MediaQuery.textScalerOf(context).scale(14) <= 21;
        final stackedHeader =
            !wide && MediaQuery.textScalerOf(context).scale(14) > 20;
        final date = MaterialLocalizations.of(context).formatMediumDate(now);
        final dateBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .34),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            date,
            style: theme.textTheme.labelSmall?.copyWith(color: foreground),
          ),
        );
        Widget fallback() => Image.asset(
          'assets/branding/turf_booking_fallback.png',
          key: const ValueKey('home-hero-fallback'),
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        );
        return Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: const Color(0xFF082E22),
            border: Border.all(color: foreground.withValues(alpha: .14)),
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
                        const Color(0xFF06291D).withValues(alpha: .96),
                        const Color(0xFF06291D).withValues(alpha: .78),
                        const Color(0xFF06291D).withValues(alpha: .42),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (stackedHeader) ...[
                        Row(
                          children: [
                            mark(32),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                widget.organization,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        dateBadge,
                      ] else
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  mark(32),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      widget.organization,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: foreground,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            dateBadge,
                          ],
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Semantics(
                          header: true,
                          child: Text(
                            firstName.isEmpty
                                ? greeting
                                : '$greeting, $firstName',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.5,
                            ),
                          ),
                        ),
                      ),
                      if (widget.onWebsite != null)
                        OutlinedButton.icon(
                          key: const ValueKey('home-booking-website'),
                          onPressed: widget.onWebsite,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: foreground,
                            backgroundColor: foreground.withValues(alpha: .13),
                            side: BorderSide(
                              color: foreground.withValues(alpha: .38),
                            ),
                          ),
                          icon: const Icon(Icons.language_outlined, size: 18),
                          label: const Text('Booking website'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
