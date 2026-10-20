import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../config/routes/routes.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/business_management_cubit.dart';
import '../models/business_management_model.dart';
import '../widgets/business_icon.dart';
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

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<BusinessManagementCubit, BusinessManagementModel>(
    bloc: cubit,
    builder: (context, s) => AppPage(
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
                itemBuilder: (context, index) => businessRow(context, s, index),
              ),
            ]
          : null,
      children: [
        if (!s.data.isOwner)
          const AppErrorWidget(message: 'Only the owner can manage businesses.')
        else ...[
          FilledButton.icon(
            onPressed: s.busy || s.reordering
                ? null
                : () => context.push(Routes.addBusiness),
            icon: const Icon(Icons.add),
            label: const Text('Add business'),
          ),
          const SizedBox(height: 12),
          const Text('Long press a business and drag to change its order.'),
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
