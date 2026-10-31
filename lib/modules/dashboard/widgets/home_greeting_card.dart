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
  });
  final String name, organization;
  final Uint8List? logo, heroImage;
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
    final theme = Theme.of(context), colors = theme.colorScheme;
    final firstName = widget.name.trim().split(RegExp(r'\s+')).first;
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final icon = now.hour < 12
        ? Icons.wb_sunny_outlined
        : now.hour < 17
        ? Icons.light_mode_outlined
        : Icons.nightlight_outlined;
    final dark = theme.brightness == Brightness.dark;
    Widget mark(double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.logo == null
          ? Icon(Icons.business_outlined, color: colors.primary, size: size / 2)
          : Image.memory(
              widget.logo!,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.business_outlined, color: colors.primary),
            ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 600 &&
            MediaQuery.textScalerOf(context).scale(14) <= 21;
        return Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colors.primary.withValues(alpha: dark ? .24 : .18),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  colors.primary.withValues(alpha: dark ? .16 : .10),
                  colors.surface,
                ),
                colors.surface,
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: dark ? .28 : .16,
                  child: widget.heroImage == null
                      ? Image.asset(
                          'assets/branding/turf_booking_fallback.png',
                          key: const ValueKey('home-hero-fallback'),
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                        )
                      : Image.memory(
                          widget.heroImage!,
                          key: const ValueKey('home-hero-uploaded'),
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                          errorBuilder: (_, _, _) => Image.asset(
                            'assets/branding/turf_booking_fallback.png',
                            key: const ValueKey('home-hero-fallback'),
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                          ),
                        ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(wide ? 28 : 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(icon, color: colors.primary, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  MaterialLocalizations.of(
                                    context,
                                  ).formatFullDate(now),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Semantics(
                            header: true,
                            child: Text(
                              firstName.isEmpty
                                  ? greeting
                                  : '$greeting, $firstName',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Here’s your day at a glance.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.organization,
                                  style: theme.textTheme.labelLarge,
                                ),
                              ),
                              if (!wide) ...[
                                const SizedBox(width: 12),
                                mark(36),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (wide) ...[const SizedBox(width: 28), mark(72)],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
