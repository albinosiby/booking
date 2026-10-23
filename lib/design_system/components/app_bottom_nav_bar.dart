import 'package:flutter/material.dart';
import '../tokens/spacing.dart';

/// Primary destinations shared by the bottom bar and the web sidebar.
class AppDestination {
  const AppDestination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon, selectedIcon;
}

const appDestinations = [
  AppDestination('Home', Icons.home_outlined, Icons.home_rounded),
  AppDestination(
    'Calendar',
    Icons.calendar_month_outlined,
    Icons.calendar_month_rounded,
  ),
  AppDestination(
    'Bookings',
    Icons.event_note_outlined,
    Icons.event_note_rounded,
  ),
  AppDestination(
    'Accounts',
    Icons.account_balance_wallet_outlined,
    Icons.account_balance_wallet_rounded,
  ),
  AppDestination('Profile', Icons.person_outline_rounded, Icons.person_rounded),
  AppDestination('My classes', Icons.sports_outlined, Icons.sports),
];

/// Floating primary navigation; Scaffold reserves its complete safe-area height.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.index,
    required this.onTap,
    this.branches = const [0, 1, 2, 3, 4],
  });
  final List<int> branches;
  final int index;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        AppSpacing.navGap,
        10,
        AppSpacing.navGap,
        AppSpacing.navGap,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.navMaxWidth),
          child: Material(
            key: const ValueKey('floating-bottom-nav'),
            elevation: AppSpacing.navElevation,
            shadowColor: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? .6 : .18,
            ),
            color: colors.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.navRadius),
              side: BorderSide(color: colors.outline.withValues(alpha: .45)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: NavigationBarTheme(
                data: theme.navigationBarTheme.copyWith(
                  indicatorShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  labelTextStyle: WidgetStateProperty.resolveWith(
                    (states) => TextStyle(
                      fontSize: 11,
                      fontWeight: states.contains(WidgetState.selected)
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: states.contains(WidgetState.selected)
                          ? colors.primary
                          : colors.onSurface.withValues(alpha: .65),
                    ),
                  ),
                  iconTheme: WidgetStateProperty.resolveWith(
                    (states) => IconThemeData(
                      size: 23,
                      color: states.contains(WidgetState.selected)
                          ? colors.onPrimary
                          : colors.onSurface.withValues(alpha: .65),
                    ),
                  ),
                ),
                child: NavigationBar(
                  selectedIndex: branches.contains(index)
                      ? branches.indexOf(index)
                      : 0,
                  onDestinationSelected: (position) =>
                      onTap(branches[position]),
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  indicatorColor: colors.primary,
                  height: AppSpacing.navHeight,
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  destinations: [
                    for (final branch in branches)
                      NavigationDestination(
                        icon: Icon(appDestinations[branch].icon),
                        selectedIcon: Icon(
                          appDestinations[branch].selectedIcon,
                        ),
                        label: appDestinations[branch].label,
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
}
