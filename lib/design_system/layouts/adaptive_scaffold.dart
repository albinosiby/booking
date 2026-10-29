import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../constants/asset_path.dart';
import '../components/app_bottom_nav_bar.dart';
import '../tokens/app_theme.dart';
import 'responsive_builder.dart';

/// Bottom navigation on phones; a persistent sidebar on tablet and web widths.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.shell,
    this.onTabSelected,
    this.branches = const [0, 1, 2, 3, 4],
    this.staffPayments = false,
  });
  final bool staffPayments;
  final List<int> branches;
  final StatefulNavigationShell shell;
  final VoidCallback? onTabSelected;

  void select(int i) {
    shell.goBranch(i);
    onTabSelected?.call();
  }

  @override
  Widget build(BuildContext context) => ResponsiveBuilder(
    builder: (context, type) => type == ScreenType.mobile
        ? Scaffold(
            body: SafeArea(bottom: false, child: shell),
            bottomNavigationBar: AppBottomNavBar(
              index: shell.currentIndex,
              onTap: select,
              branches: branches,
              staffPayments: staffPayments,
            ),
          )
        : Scaffold(
            body: Row(
              children: [
                AppSideNav(
                  index: shell.currentIndex,
                  onTap: select,
                  branches: branches,
                  staffPayments: staffPayments,
                  extended: type == ScreenType.desktop,
                ),
                Expanded(child: SafeArea(left: false, child: shell)),
              ],
            ),
          ),
  );
}

class AppSideNav extends StatelessWidget {
  const AppSideNav({
    super.key,
    required this.index,
    required this.onTap,
    required this.extended,
    this.branches = const [0, 1, 2, 3, 4],
    this.staffPayments = false,
  });
  final bool staffPayments;
  final List<int> branches;
  final int index;
  final ValueChanged<int> onTap;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return AnimatedContainer(
      key: const ValueKey('side-nav'),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: extended ? 264 : 88,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF151515) : Colors.white,
        border: Border(
          right: BorderSide(color: colors.outline.withValues(alpha: .5)),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: extended ? 16 : 12,
            vertical: 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Brand(extended: extended),
              const SizedBox(height: 32),
              if (extended)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 10),
                  child: Text(
                    'WORKSPACE',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface.withValues(alpha: .45),
                    ),
                  ),
                ),
              for (final i in branches) ...[
                _NavItem(
                  destination: appDestination(i, staffPayments: staffPayments),
                  selected: i == index,
                  extended: extended,
                  onTap: () => onTap(i),
                ),
                const SizedBox(height: 4),
              ],
              const Spacer(),
              if (extended)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.lime.withValues(alpha: dark ? .18 : .16),
                        AppColors.forest.withValues(alpha: dark ? .10 : .06),
                      ],
                    ),
                    border: Border.all(
                      color: AppColors.lime.withValues(alpha: .25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bolt_rounded, color: colors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Bookings, spaces and accounts in one place.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: colors.onSurface.withValues(alpha: .75),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.extended});
  final bool extended;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mark = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        AssetPath.bookingLogo,
        width: 40,
        height: 40,
        semanticLabel: 'Booking OS',
      ),
    );
    if (!extended) return Center(child: mark);
    return Row(
      children: [
        const SizedBox(width: 4),
        mark,
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Booking OS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -.4,
              color: colors.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.extended,
    required this.onTap,
  });
  final AppDestination destination;
  final bool selected, extended;
  final VoidCallback onTap;
  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final foreground = selected
        ? colors.primary
        : colors.onSurface.withValues(alpha: hover ? .95 : .65);
    final item = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: Semantics(
        button: true,
        selected: selected,
        label: widget.destination.label,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: widget.extended ? 14 : 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected
                  ? colors.primary.withValues(alpha: .14)
                  : hover
                  ? colors.onSurface.withValues(alpha: .06)
                  : Colors.transparent,
            ),
            child: Row(
              mainAxisAlignment: widget.extended
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  selected
                      ? widget.destination.selectedIcon
                      : widget.destination.icon,
                  size: 22,
                  color: foreground,
                ),
                if (widget.extended) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.destination.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected ? colors.onSurface : foreground,
                      ),
                    ),
                  ),
                  if (selected)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return widget.extended
        ? item
        : Tooltip(message: widget.destination.label, child: item);
  }
}
