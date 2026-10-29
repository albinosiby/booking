import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../workspace/models/workspace.dart';
import 'business_icon.dart';
import 'business_management_widgets.dart';
import 'business_availability_menu.dart';
import '../models/business_availability_action.dart';

/// Rounded status label: green when ready, amber when paused, neutral when
/// setup is still needed.
class BusinessStatusPill extends StatelessWidget {
  const BusinessStatusPill(this.business, {super.key});
  final Business business;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (business.status) {
      'ready' => colors.primary,
      'paused' => Colors.amber.shade700,
      _ => colors.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              businessStatus(business),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Square tinted icon for a business type.
class BusinessIconBadge extends StatelessWidget {
  const BusinessIconBadge(this.type, {super.key, this.size = 48});
  final BusinessType type;
  final double size;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: Icon(businessIcon(type), color: colors.primary, size: size * .5),
    );
  }
}

/// Desktop grid card for one business with its actions.
class BusinessGridCard extends StatelessWidget {
  const BusinessGridCard({
    super.key,
    required this.business,
    required this.position,
    this.location,
    this.onOpen,
    this.onRename,
    this.onConfigure,
    this.onAvailability,
  });
  final Business business;
  final int position;
  final String? location;
  final VoidCallback? onOpen, onRename, onConfigure;
  final ValueChanged<BusinessAvailabilityAction>? onAvailability;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final spaces = business.resources.length;
    final muted = TextStyle(
      fontSize: 13,
      color: colors.onSurface.withValues(alpha: .65),
    );
    return AppCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BusinessIconBadge(business.type),
                const Spacer(),
                BusinessStatusPill(business),
                BusinessAvailabilityMenu(
                  business: business,
                  onSelected: onAvailability,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            business.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(business.type.label, style: muted),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _Fact(
                Icons.grid_view_rounded,
                '$spaces ${spaces == 1 ? 'space' : 'spaces'}',
              ),
              _Fact(Icons.format_list_numbered, 'Position $position'),
              if (location != null && location!.isNotEmpty)
                _Fact(Icons.location_on_outlined, location!),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: colors.outline.withValues(alpha: .35)),
          OverflowBar(
            spacing: 2,
            children: [
              TextButton(onPressed: onOpen, child: const Text('View details')),
              TextButton(onPressed: onRename, child: const Text('Rename')),
              TextButton.icon(
                onPressed: onConfigure,
                icon: const Icon(Icons.tune, size: 18),
                label: Text(
                  business.ready || business.status == 'paused'
                      ? 'Configure'
                      : 'Continue setup',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: .7);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: color),
          ),
        ),
      ],
    );
  }
}
