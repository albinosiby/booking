import 'package:flutter/material.dart';
import '../models/configuration_draft.dart';

class ConfigurationDraftNotice extends StatelessWidget {
  const ConfigurationDraftNotice({
    super.key,
    required this.status,
    required this.dirty,
    this.message,
    required this.onRetry,
  });
  final LocalDraftStatus status;
  final bool dirty;
  final String? message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        message ??
            switch (status) {
              LocalDraftStatus.loading => 'Restoring your local draft…',
              LocalDraftStatus.loadFailed =>
                'Could not restore your local draft.',
              LocalDraftStatus.saving => 'Saving draft on this device…',
              LocalDraftStatus.saved =>
                dirty
                    ? 'Draft saved on this device · Save or Activate to apply online'
                    : 'Saved configuration',
              LocalDraftStatus.failed => 'Could not save the local draft.',
              LocalDraftStatus.conflict =>
                'Newer settings exist online. Reload saved settings before publishing.',
              LocalDraftStatus.idle =>
                dirty
                    ? 'Changes are kept on this device until you Save or Activate.'
                    : 'Online settings are unchanged until you Save or Activate.',
            },
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if ([
        LocalDraftStatus.failed,
        LocalDraftStatus.loadFailed,
      ].contains(status))
        TextButton(onPressed: onRetry, child: const Text('Retry local draft')),
    ],
  );
}
