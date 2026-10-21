import 'package:flutter/material.dart';
import '../components/app_card.dart';
import '../tokens/spacing.dart';

/// One destination in the desktop configuration rail.
class ConfigurationNavItem {
  const ConfigurationNavItem({
    required this.label,
    required this.icon,
    this.subtitle,
    this.selected = false,
    this.onTap,
    this.key,
  });
  final String label;
  final String? subtitle;
  final IconData icon;
  final bool selected;

  /// Null disables the item, for example while a step-by-step flow is open.
  final VoidCallback? onTap;
  final Key? key;
}

/// Desktop configure layout: a rail with the business, its sections and the
/// save actions beside the open section's editor.
///
/// Every setup module (turf, court, pool, hall) builds the same three parts it
/// shows on phones; this only arranges them side by side.
class ConfigurationWorkspace extends StatelessWidget {
  const ConfigurationWorkspace({
    super.key,
    required this.businessName,
    required this.ready,
    required this.sections,
    required this.content,
    this.actions = const [],
    this.kind,
  });
  final String businessName;

  /// Business type label shown under the name, such as "Badminton courts".
  final String? kind;
  final bool ready;
  final List<ConfigurationNavItem> sections;
  final List<Widget> content, actions;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('configuration-workspace'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BusinessCard(name: businessName, kind: kind, ready: ready),
            const SizedBox(height: 16),
            AppCard(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [for (final item in sections) _NavTile(item: item)],
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              AppCard(
                key: const ValueKey('configuration-actions'),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: actions,
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(width: 32),
      Expanded(
        child: Column(
          key: const ValueKey('configuration-content'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: content,
        ),
      ),
    ],
  );
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({required this.name, required this.ready, this.kind});
  final String name;
  final String? kind;
  final bool ready;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tone = ready ? colors.primary : const Color(0xFFE0A33A);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary.withValues(alpha: .16),
            colors.primary.withValues(alpha: .04),
          ],
        ),
        border: Border.all(color: colors.primary.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (kind != null)
            Text(kind!, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ready ? Icons.check_circle : Icons.pending_outlined,
                  size: 14,
                  color: tone,
                ),
                const SizedBox(width: 6),
                Text(
                  ready ? 'Live for bookings' : 'Setup in progress',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: tone,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item});
  final ConfigurationNavItem item;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = item.selected;
    final enabled = item.onTap != null;
    final fg = selected
        ? colors.primary
        : colors.onSurface.withValues(alpha: enabled ? .85 : .4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: .12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: item.key,
          onTap: item.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(item.icon, size: 20, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: selected ? colors.onSurface : fg,
                        ),
                      ),
                      if (item.subtitle != null)
                        Text(
                          item.subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: colors.onSurface.withValues(
                              alpha: enabled ? .6 : .35,
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
      ),
    );
  }
}
