import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../config/routes/routes.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../workspace/models/workspace.dart';
import '../cubit/business_management_cubit.dart';
import '../models/business_management_model.dart';
import '../widgets/business_icon.dart';
import '../widgets/business_desktop_widgets.dart';
import '../widgets/business_management_widgets.dart';

class BusinessManagementScreen extends StatefulWidget {
  const BusinessManagementScreen({super.key});
  @override
  State<BusinessManagementScreen> createState() =>
      _BusinessManagementScreenState();
}

class _BusinessManagementScreenState extends State<BusinessManagementScreen> {
  late final cubit = getIt<BusinessManagementCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Widget businessRow(
    BuildContext context,
    BusinessManagementModel s,
    int index,
  ) {
    final business = s.businesses[index];
    return Padding(
      key: ValueKey(business.id),
      padding: const EdgeInsets.only(bottom: 12),
      child: ReorderableDelayedDragStartListener(
        index: index,
        enabled: !s.busy && s.businesses.length > 1,
        child: AppCard(
          onTap: s.reordering
              ? null
              : () => context.push('/businesses/${business.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Icon(
                      businessIcon(business.type),
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          business.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(business.type.label),
                        const SizedBox(height: 4),
                        Text(
                          '${businessStatus(business)} · ${business.resources.length} ${business.resources.length == 1 ? 'space' : 'spaces'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: s.reordering
                        ? null
                        : () => context.push('/businesses/${business.id}'),
                    child: const Text('View details'),
                  ),
                  TextButton(
                    onPressed: s.busy || s.reordering
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
                    child: const Text('Rename'),
                  ),
                  TextButton.icon(
                    onPressed: s.busy || s.reordering
                        ? null
                        : () => context.push(businessSettingsPath(business)),
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(
                      business.ready ? 'Configure' : 'Continue setup',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> rename(Business business) async {
    final name = await editBusinessName(context, business);
    if (name != null && mounted) await cubit.rename(business.id, name);
  }

  // Desktop reorder row: drag handle plus explicit move buttons.
  Widget reorderRow(BuildContext context, BusinessManagementModel s, int i) {
    final business = s.businesses[i];
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey(business.id),
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: i,
              enabled: !s.busy,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.drag_indicator,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 32,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            BusinessIconBadge(business.type, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    business.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    business.type.label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            BusinessStatusPill(business),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Move up',
              onPressed: s.busy || i == 0
                  ? null
                  : () => cubit.moveBusiness(i, i - 1),
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              tooltip: 'Move down',
              onPressed: s.busy || i == s.businesses.length - 1
                  ? null
                  : () => cubit.moveBusiness(i, i + 1),
              icon: const Icon(Icons.arrow_downward),
            ),
          ],
        ),
      ),
    );
  }

  // Wide windows: header actions, overview tiles and a card grid. Reordering
  // switches to a list with drag handles and move buttons.
  Widget desktop(BuildContext context, BusinessManagementModel s) {
    final all = s.businesses;
    final ready = all.where((b) => b.ready).length;
    final spaces = all.fold<int>(0, (n, b) => n + b.resources.length);
    return AppPage(
      back: true,
      title: 'Businesses',
      eyebrow: 'WORKSPACE MANAGEMENT',
      subtitle: 'Manage your spaces, configuration and display order.',
      maxWidth: 1200,
      scrollId: 'business-management',
      actions: s.data.isOwner && !s.reordering
          ? [
              if (all.length > 1)
                OutlinedButton.icon(
                  key: const ValueKey('business-reorder'),
                  onPressed: s.busy ? null : cubit.startReorder,
                  icon: const Icon(Icons.swap_vert, size: 18),
                  label: const Text('Reorder'),
                ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: s.busy
                    ? null
                    : () => context.push(Routes.addBusiness),
                icon: const Icon(Icons.add),
                label: const Text('Add business'),
              ),
            ]
          : null,
      bottomBar: s.reordering
          ? Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 14, 14),
              child: Row(
                children: [
                  Icon(
                    Icons.swap_vert,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('The new order is not saved yet.'),
                  ),
                  TextButton(
                    onPressed: s.busy ? null : cubit.cancelReorder,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 200,
                    child: AppButton(
                      label: 'Save order',
                      busy: s.busy,
                      onPressed: s.busy ? null : cubit.saveOrder,
                    ),
                  ),
                ],
              ),
            )
          : null,
      slivers: s.data.isOwner && s.reordering
          ? [
              SliverReorderableList(
                itemCount: all.length,
                onReorderItem: cubit.moveBusiness,
                itemBuilder: (context, i) => reorderRow(context, s, i),
              ),
            ]
          : null,
      children: [
        if (!s.data.isOwner)
          const AppErrorWidget(message: 'Only the owner can manage businesses.')
        else ...[
          if (all.isNotEmpty) ...[
            AppStatRow(
              children: [
                AppStatTile(
                  icon: Icons.storefront_outlined,
                  label: 'Businesses',
                  value: '${all.length}',
                  caption: s.data.organization?.name,
                  highlight: true,
                ),
                AppStatTile(
                  icon: Icons.check_circle_outline,
                  label: 'Ready for bookings',
                  value: '$ready',
                ),
                AppStatTile(
                  icon: Icons.build_circle_outlined,
                  label: 'Setup needed or paused',
                  value: '${all.length - ready}',
                ),
                AppStatTile(
                  icon: Icons.grid_view_rounded,
                  label: 'Spaces',
                  value: '$spaces',
                ),
              ],
            ),
            const SizedBox(height: 28),
          ],
          if (s.busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
          ],
          if (s.error != null || s.message != null) ...[
            AppErrorWidget(message: s.message ?? s.error!),
            const SizedBox(height: 16),
          ],
          if (all.isEmpty)
            const AppEmptyState(
              title: 'No businesses yet',
              message:
                  'Add your first business to configure spaces and bookings.',
            )
          else if (s.reordering)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Drag a handle or use the arrows to change the display order, then save.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            AppPanel(
              title: 'Your businesses',
              subtitle: 'Shown in this order across bookings and reports.',
              child: AppGrid(
                minTileWidth: 340,
                maxColumns: 3,
                children: [
                  for (final (i, b) in all.indexed)
                    BusinessGridCard(
                      key: ValueKey(b.id),
                      business: b,
                      position: i + 1,
                      location: s.locationFor(b)?.name,
                      onOpen: () => context.push('/businesses/${b.id}'),
                      onRename: s.busy ? null : () => rename(b),
                      onConfigure: s.busy
                          ? null
                          : () => context.push(businessSettingsPath(b)),
                    ),
                ],
              ),
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
    builder: (context, s) => isDesktopWidth(context)
        ? desktop(context, s)
        : AppPage(
            back: true,
            title: 'Businesses',
            eyebrow: 'WORKSPACE MANAGEMENT',
            subtitle: 'Manage your spaces, configuration and display order.',
            maxWidth: 900,
            scrollId: 'business-management',
            bottomBar: s.reordering
                ? SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: s.busy ? null : cubit.cancelReorder,
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: AppButton(
                              label: 'Save order',
                              busy: s.busy,
                              onPressed: s.busy ? null : cubit.saveOrder,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
            slivers: s.data.isOwner
                ? [
                    SliverReorderableList(
                      itemCount: s.businesses.length,
                      onReorderStart: (_) => cubit.startReorder(),
                      onReorderItem: cubit.moveBusiness,
                      itemBuilder: (context, index) =>
                          businessRow(context, s, index),
                    ),
                  ]
                : null,
            children: [
              if (!s.data.isOwner)
                const AppErrorWidget(
                  message: 'Only the owner can manage businesses.',
                )
              else ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    onPressed: s.busy || s.reordering
                        ? null
                        : () => context.push(Routes.addBusiness),
                    icon: const Icon(Icons.add),
                    label: const Text('Add business'),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Long press a business and drag to change its order.',
                ),
                const SizedBox(height: 16),
                if (s.busy) const LinearProgressIndicator(),
                if (s.error != null || s.message != null)
                  AppErrorWidget(message: s.message ?? s.error!),
                if (s.businesses.isEmpty)
                  const AppEmptyState(
                    showCard: false,
                    title: 'No businesses yet',
                    message:
                        'Add your first business to configure spaces and bookings.',
                  ),
              ],
            ],
          ),
  );
}
