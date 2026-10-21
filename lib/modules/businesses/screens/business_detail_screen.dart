import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../workspace/models/workspace.dart';
import '../cubit/business_management_cubit.dart';
import '../models/business_management_model.dart';
import '../models/business_detail_model.dart';
import '../widgets/business_icon.dart';
import '../widgets/business_management_widgets.dart';
import '../widgets/business_detail_sections.dart';

class BusinessDetailScreen extends StatefulWidget {
  const BusinessDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<BusinessDetailScreen> createState() => _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends State<BusinessDetailScreen> {
  late final cubit = getIt<BusinessManagementCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  @override
  void initState() {
    super.initState();
    cubit.showDetails(widget.id);
  }

  @override
  void didUpdateWidget(covariant BusinessDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) cubit.showDetails(widget.id);
  }

  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<void> rename(Business business) async {
    final name = await editBusinessName(context, business);
    if (name != null && mounted) await cubit.rename(business.id, name);
  }

  String readiness(Business business) => business.ready
      ? 'Ready for bookings. Review your spaces and current setup below.'
      : business.status == 'paused'
      ? 'This business is paused. Review its configuration before taking bookings.'
      : 'Finish setting up spaces, hours and prices to start taking bookings.';

  // Wide windows: overview tiles, a grid of spaces with their hours and
  // prices, and business information beside it.
  Widget desktop(
    BuildContext context,
    BusinessManagementModel s,
    Business? business,
    BusinessLocationSummary? location,
    BusinessDetailSummary? detail,
  ) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final position = business == null
        ? 0
        : s.data.businesses.indexWhere((b) => b.id == business.id) + 1;
    final spaces = detail?.spaceCount ?? business?.resources.length ?? 0;
    final rates = detail == null
        ? 0
        : detail.sections
              .expand((x) => x.entries)
              .expand((e) => e.prices)
              .fold<int>(0, (n, g) => n + g.rates.length);
    return AppPage(
      back: true,
      title: business?.name ?? 'Business details',
      eyebrow: 'WORKSPACE MANAGEMENT',
      subtitle: 'Overview, spaces, opening hours and prices.',
      maxWidth: 1200,
      scrollId: 'business-details-${widget.id}',
      actions: s.data.isOwner && business != null
          ? [
              TextButton.icon(
                onPressed: s.busy ? null : cubit.reload,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: s.busy ? null : () => rename(business),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Rename business'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    context.push('/businesses/${business.id}/bookings'),
                icon: const Icon(Icons.event_note_outlined, size: 18),
                label: const Text('View bookings'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: s.busy
                    ? null
                    : () => context.push(businessSettingsPath(business)),
                icon: const Icon(Icons.tune, size: 18),
                label: Text(
                  business.ready ? 'Configure business' : 'Continue setup',
                ),
              ),
            ]
          : null,
      children: [
        if (!s.data.isOwner)
          const AppErrorWidget(message: 'Only the owner can manage businesses.')
        else if (business == null)
          AppErrorWidget(
            message: 'This business is no longer available.',
            onRetry: cubit.reload,
          )
        else ...[
          AppStatRow(
            children: [
              AppStatTile(
                icon: businessIcon(business.type),
                label: business.type.label,
                value: businessStatus(business),
                caption: s.data.organization?.name ?? 'Your workspace',
                highlight: true,
              ),
              AppStatTile(
                icon: Icons.grid_view_rounded,
                label: 'Configured spaces',
                value: '$spaces',
                caption: detail?.enabledCount == null
                    ? null
                    : '${detail!.enabledCount} enabled',
              ),
              AppStatTile(
                icon: Icons.sell_outlined,
                label: 'Saved prices',
                value: '$rates',
                caption: 'Across all spaces and options',
              ),
              AppStatTile(
                icon: Icons.format_list_numbered,
                label: 'Display position',
                value: '$position of ${s.data.businesses.length}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: (business.ready ? colors.primary : colors.onSurface)
                  .withValues(alpha: .07),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  business.ready
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  size: 20,
                  color: business.ready
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    readiness(business),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          if (s.error != null || s.message != null) ...[
            const SizedBox(height: 16),
            AppErrorWidget(
              message: s.message ?? s.error!,
              onRetry: cubit.reload,
            ),
          ],
          const SizedBox(height: 32),
          AppTwoPane(
            secondaryWidth: 360,
            primary: [
              if (detail?.notice != null) ...[
                Text(detail!.notice!),
                const SizedBox(height: 18),
              ],
              if (spaces == 0)
                const AppEmptyState(
                  title: 'No spaces configured',
                  message:
                      'Open configuration to add spaces and complete this business’s setup.',
                ),
              if (detail != null)
                for (final section in detail.sections.where(
                  (s) => s.entries.isNotEmpty,
                ))
                  BusinessDetailSectionView(
                    section: section,
                    businessId: business.id,
                    grid: true,
                  ),
            ],
            secondary: [
              AppPanel(
                title: 'Business information',
                child: AppCard(
                  child: BusinessDetailFields(
                    fields: [
                      BusinessDetailField('Business name', business.name),
                      BusinessDetailField('Business type', business.type.label),
                      BusinessDetailField(
                        'Organization',
                        s.data.organization?.name ?? 'Not provided',
                      ),
                      BusinessDetailField(
                        'Organization phone',
                        s.data.organization?.phone ?? 'Not provided',
                      ),
                      BusinessDetailField(
                        'Currency',
                        s.data.organization?.currency ?? 'Not provided',
                      ),
                      if (s.ownerName.isNotEmpty)
                        BusinessDetailField('Owner', s.ownerName),
                      if (s.ownerEmail.isNotEmpty)
                        BusinessDetailField('Owner email', s.ownerEmail),
                    ],
                  ),
                ),
              ),
              AppPanel(
                title: 'Location',
                child: AppCard(
                  child: BusinessDetailFields(
                    fields: [
                      BusinessDetailField(
                        'Venue',
                        location?.name ?? 'Not provided',
                      ),
                      BusinessDetailField(
                        'Address',
                        location?.address ?? 'Not provided',
                      ),
                      BusinessDetailField(
                        'Timezone',
                        location?.timezone ?? 'Not provided',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<BusinessManagementCubit, BusinessManagementModel>(
    bloc: cubit,
    builder: (context, s) {
      final business = s.data.businesses
          .where((b) => b.id == widget.id)
          .firstOrNull;
      final location = business == null ? null : s.locationFor(business);
      final detail = s.details[widget.id];
      final theme = Theme.of(context), colors = theme.colorScheme;
      if (isDesktopWidth(context)) {
        return desktop(context, s, business, location, detail);
      }
      return AppPage(
        back: true,
        title: business?.name ?? 'Business details',
        eyebrow: 'WORKSPACE MANAGEMENT',
        subtitle: 'Overview, spaces, opening hours and prices.',
        maxWidth: 1040,
        scrollId: 'business-details-${widget.id}',
        children: [
          if (!s.data.isOwner)
            const AppErrorWidget(
              message: 'Only the owner can manage businesses.',
            )
          else if (business == null)
            AppErrorWidget(
              message: 'This business is no longer available.',
              onRetry: cubit.reload,
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colors.primaryContainer, colors.surfaceContainerLow],
                ),
                border: Border.all(
                  color: colors.primary.withValues(alpha: .18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BusinessDetailIdentity(
                    icon: businessIcon(business.type),
                    type: business.type.label,
                    organization: s.data.organization?.name ?? 'Your workspace',
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ReviewTag(
                        businessStatus(business),
                        active: business.ready,
                      ),
                      ReviewTag(
                        '${detail?.spaceCount ?? business.resources.length} configured spaces',
                      ),
                      if (detail?.enabledCount != null)
                        ReviewTag('${detail!.enabledCount} enabled'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    business.ready
                        ? 'Ready for bookings. Review your spaces and current setup below.'
                        : business.status == 'paused'
                        ? 'This business is paused. Review its configuration before taking bookings.'
                        : 'Finish setting up spaces, hours and prices to start taking bookings.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: s.busy
                      ? null
                      : () => context.push(businessSettingsPath(business)),
                  icon: const Icon(Icons.tune),
                  label: Text(
                    business.ready ? 'Configure business' : 'Continue setup',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      context.push('/businesses/${business.id}/bookings'),
                  icon: const Icon(Icons.event_note_outlined),
                  label: const Text('View bookings'),
                ),
                TextButton.icon(
                  onPressed: s.busy
                      ? null
                      : () async {
                          final name = await editBusinessName(
                            context,
                            business,
                          );
                          if (name != null && mounted) {
                            await cubit.rename(business.id, name);
                          }
                        },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Rename business'),
                ),
                TextButton.icon(
                  onPressed: s.busy ? null : cubit.reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            if (s.error != null || s.message != null) ...[
              const SizedBox(height: 16),
              AppErrorWidget(
                message: s.message ?? s.error!,
                onRetry: cubit.reload,
              ),
            ],
            const SizedBox(height: 28),
            Text('Business information', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            AppCard(
              child: BusinessDetailFields(
                fields: [
                  BusinessDetailField('Business name', business.name),
                  BusinessDetailField('Business type', business.type.label),
                  BusinessDetailField(
                    'Organization',
                    s.data.organization?.name ?? 'Not provided',
                  ),
                  BusinessDetailField(
                    'Display position',
                    '${s.data.businesses.indexWhere((b) => b.id == business.id) + 1} of ${s.data.businesses.length} businesses',
                  ),
                  BusinessDetailField(
                    'Organization phone',
                    s.data.organization?.phone ?? 'Not provided',
                  ),
                  BusinessDetailField(
                    'Currency',
                    s.data.organization?.currency ?? 'Not provided',
                  ),
                  if (s.ownerName.isNotEmpty)
                    BusinessDetailField('Owner', s.ownerName),
                  if (s.ownerEmail.isNotEmpty)
                    BusinessDetailField('Owner email', s.ownerEmail),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Location', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            AppCard(
              child: BusinessDetailFields(
                fields: [
                  BusinessDetailField(
                    'Venue',
                    location?.name ?? 'Not provided',
                  ),
                  BusinessDetailField(
                    'Address',
                    location?.address ?? 'Not provided',
                  ),
                  BusinessDetailField(
                    'Timezone',
                    location?.timezone ?? 'Not provided',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Spaces & configuration',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Expand a space or option to see its saved hours, booking rules and prices.',
            ),
            const SizedBox(height: 18),
            if (detail?.notice != null) ...[
              Text(detail!.notice!),
              const SizedBox(height: 18),
            ],
            if ((detail?.spaceCount ?? business.resources.length) == 0)
              const AppEmptyState(
                showCard: false,
                title: 'No spaces configured',
                message:
                    'Open configuration to add spaces and complete this business’s setup.',
              ),
            if (detail != null)
              for (final section in detail.sections.where(
                (s) => s.entries.isNotEmpty,
              ))
                BusinessDetailSectionView(
                  section: section,
                  businessId: business.id,
                ),
          ],
        ],
      );
    },
  );
}
