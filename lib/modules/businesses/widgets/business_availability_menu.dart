import 'package:flutter/material.dart';
import '../../workspace/models/workspace.dart';
import '../models/business_availability_action.dart';
import '../models/business_removal_action.dart';

class BusinessAvailabilityMenu extends StatelessWidget {
  const BusinessAvailabilityMenu({
    super.key,
    required this.business,
    required this.onSelected,
    this.onRemove,
  });
  final Business business;
  final ValueChanged<BusinessAvailabilityAction>? onSelected;
  final ValueChanged<BusinessRemovalAction>? onRemove;

  @override
  Widget build(BuildContext context) {
    final action = BusinessAvailabilityAction.forBusiness(business);
    if (action == null && onRemove == null) return const SizedBox.shrink();
    return PopupMenuButton<Object>(
      key: ValueKey('business-menu-${business.id}'),
      tooltip: 'Options for ${business.name}',
      enabled: onSelected != null || onRemove != null,
      onSelected: (value) {
        if (value is BusinessAvailabilityAction) onSelected?.call(value);
        if (value is BusinessRemovalAction) onRemove?.call(value);
      },
      itemBuilder: (_) => [
        if (action != null)
          PopupMenuItem(
            value: action,
            enabled: onSelected != null,
            child: Row(
              children: [
                Icon(
                  action.enabled
                      ? Icons.power_settings_new
                      : Icons.pause_circle_outline,
                  size: 20,
                  color: action.enabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 10),
                Flexible(child: Text(action.label)),
              ],
            ),
          ),
        if (onRemove != null)
          PopupMenuItem(
            value: BusinessRemovalAction.fromBusiness(business),
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 10),
                const Flexible(child: Text('Delete business')),
              ],
            ),
          ),
      ],
    );
  }
}

Future<bool> confirmBusinessRemoval(
  BuildContext context,
  BusinessRemovalAction action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete business?'),
        content: Text(
          'Permanently delete ${action.name}, its spaces and linked setup? '
          'This cannot be undone in the app. Businesses with booking, admission or financial history cannot be deleted. '
          'You can turn a business off to keep its history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    ) ??
    false;

Future<bool> confirmBusinessAvailability(
  BuildContext context,
  BusinessAvailabilityAction action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${action.label}?'),
        content: Text(action.confirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: action.enabled
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
            child: Text(action.enabled ? 'Turn on' : 'Turn off'),
          ),
        ],
      ),
    ) ??
    false;
