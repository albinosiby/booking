import 'package:flutter/material.dart';
import '../../workspace/models/workspace.dart';
import '../models/business_availability_action.dart';

class BusinessAvailabilityMenu extends StatelessWidget {
  const BusinessAvailabilityMenu({
    super.key,
    required this.business,
    required this.onSelected,
  });
  final Business business;
  final ValueChanged<BusinessAvailabilityAction>? onSelected;

  @override
  Widget build(BuildContext context) {
    final action = BusinessAvailabilityAction.forBusiness(business);
    if (action == null) return const SizedBox.shrink();
    return PopupMenuButton<BusinessAvailabilityAction>(
      key: ValueKey('business-menu-${business.id}'),
      tooltip: 'Options for ${business.name}',
      enabled: onSelected != null,
      onSelected: onSelected,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: action,
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
      ],
    );
  }
}

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
