import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import '../models/agent_call_models.dart';

const _steps = [
  ('requested', 'Request received', 'Your request is in the setup queue.'),
  ('in_review', 'Under review', 'We review your venue and call requirements.'),
  (
    'setting_up',
    'Being set up',
    'Your call service is being configured for your venue.',
  ),
  (
    'active',
    'Connected',
    'Your number and services are connected. Choose spaces to get started.',
  ),
];

String agentStatusLabel(AgentServiceStatus status) => switch (status.status) {
  'requested' => 'Request received',
  'in_review' => 'Under review',
  'setting_up' => 'Setting up',
  'active' =>
    !status.ready
        ? 'Finishing setup'
        : status.enabled
        ? 'Service enabled'
        : 'Connected · service off',
  'paused' => 'Service paused',
  'rejected' => 'Request declined',
  _ => 'Not requested',
};

String agentStatusDescription(
  AgentServiceStatus status,
) => switch (status.status) {
  'requested' =>
    'Your request has arrived. You can follow each setup step here.',
  'in_review' => 'We are reviewing the details for your venue’s call service.',
  'setting_up' =>
    'Your call service is being prepared. Check back here for updates.',
  'active' =>
    !status.ready
        ? 'Final setup is still in progress. Call controls will appear when ready.'
        : status.enabled
        ? 'Callers can use your activated services for selected spaces.'
        : 'Your service is connected. Select spaces and enable the service when ready.',
  'paused' =>
    'Your service is on hold. Call actions are blocked. Contact support for details.',
  'rejected' => 'Review the message below before sending another request.',
  _ => 'Give your callers a helpful first response, even when you are busy.',
};

class AgentRequestProgress extends StatelessWidget {
  const AgentRequestProgress({super.key, required this.status});
  final AgentServiceStatus status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context), c = t.colorScheme;
    final paused = status.status == 'paused';
    // A paused response does not tell us which setup stages were completed.
    // Do not imply completion when the API has not supplied that history.
    final current = _steps.indexWhere((s) => s.$1 == status.status);
    final ready = status.status == 'active' && status.ready;
    final activeIndex = status.status == 'active' && !ready ? 2 : current;
    String date(DateTime value) =>
        MaterialLocalizations.of(context).formatMediumDate(value.toLocal());
    return AppCard(
      key: const ValueKey('agent-request-progress'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Request status', style: t.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'From your first request to your first call.',
            style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          for (final (i, step) in _steps.indexed)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 32,
                    child: Column(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: i <= activeIndex && !paused
                                ? c.primary.withValues(alpha: .12)
                                : c.surfaceContainerHighest,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: i == activeIndex && !paused
                                  ? c.primary
                                  : c.outlineVariant,
                            ),
                          ),
                          child: Icon(
                            !paused && (i < activeIndex || ready)
                                ? Icons.check_rounded
                                : i == activeIndex && !paused
                                ? Icons.more_horiz_rounded
                                : Icons.circle_outlined,
                            size: 18,
                            color: i <= activeIndex && !paused
                                ? c.primary
                                : c.onSurfaceVariant,
                          ),
                        ),
                        if (i < _steps.length - 1)
                          Expanded(
                            child: Container(
                              width: 2,
                              constraints: const BoxConstraints(minHeight: 24),
                              color: i < activeIndex && !paused
                                  ? c.primary.withValues(alpha: .4)
                                  : c.outlineVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: i == 3 ? 0 : 24, top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.$2,
                            style: t.textTheme.titleSmall?.copyWith(
                              color: i == activeIndex && !paused
                                  ? c.primary
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            step.$3,
                            style: t.textTheme.bodySmall?.copyWith(
                              color: c.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (status.requestedAt != null || status.updatedAt != null) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                if (status.requestedAt != null)
                  Text(
                    'Requested ${date(status.requestedAt!)}',
                    style: t.textTheme.bodySmall,
                  ),
                if (status.updatedAt != null)
                  Text(
                    'Updated ${date(status.updatedAt!)}',
                    style: t.textTheme.bodySmall,
                  ),
              ],
            ),
          ],
          if (paused || status.message.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    paused ? 'Service paused' : 'Latest update',
                    style: t.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    status.message.isNotEmpty
                        ? status.message
                        : 'The service is paused. Contact support for details.',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
