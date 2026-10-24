import '../models/team_deletion_target.dart';
import 'package:flutter/material.dart';
import '../models/team_removal_target.dart';

Future<bool> confirmTeamRemoval(
  BuildContext context,
  TeamRemovalTarget target,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('${target.label}?'),
        content: Text(target.confirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep member'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialog).colorScheme.error,
              foregroundColor: Theme.of(dialog).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(target.label),
          ),
        ],
      ),
    ) ??
    false;

Future<bool> confirmTeamDeletion(
  BuildContext context,
  TeamDeletionTarget target,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(target.confirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep record'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialog).colorScheme.error,
              foregroundColor: Theme.of(dialog).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    ) ??
    false;
