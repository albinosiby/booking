import '../../workspace/models/workspace_navigation.dart';
import '../../bookings/widgets/compact_booking_card.dart';
import '../../bookings/models/compact_booking_model.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../widgets/home_greeting_card.dart';
import '../../workspace/models/business_order.dart';
import '../../bookings/widgets/booking_widgets.dart';
import '../../bookings/models/booking_models.dart';
import '../cubit/home_cubit.dart';
import '../models/home_screen_model.dart';
import '../../../di/injection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../workspace/models/workspace.dart';
import '../../businesses/widgets/business_icon.dart';
import '../../../config/routes/routes.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final cubit = getIt<HomeCubit>(param1: context.read<WorkspaceCubit>());
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<HomeCubit, HomeScreenModel>(
    bloc: cubit,
    builder: (context, s) {
      final workspace = s.data;
      final metricsUnavailable =
          s.dashboard == null && (s.bookingLoading || s.bookingError != null);
      final businesses = workspace.businesses;
      final ready = businesses.where((b) => b.ready).toList(),
          pending = businesses.where((b) => !b.ready).toList();
      return AppPage(
        title: workspace.organization?.name ?? 'Your organization',
        header: HomeGreetingCard(
          name: context.watch<AuthCubit?>()?.state.user?.name ?? '',
          organization: workspace.organization?.name ?? 'Your organization',
          logo: workspace.logo,
        ),
        maxWidth: 1200,
        scrollId: 'home-dashboard',
        floatingActionButton: workspace.hasPermission('manage_bookings')
            ? NewBookingFab(onPressed: () => context.push('/booking/new'))
            : null,
        children: [
          if (s.status == LoadStatus.loading) const AppLoadingState(),
          if (s.needsAccountSetup)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16.r),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16.w,
                  vertical: 6.h,
                ),
                leading: Icon(
                  Icons.account_balance_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('Set up your accounts'),
                subtitle: const Text('Add a bank account for digital payments'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await context.push('/accounts/settings');
                  if (!cubit.isClosed) await cubit.loadAccountSetup();
                },
              ),
            ),
          if (s.needsAccountSetup) SizedBox(height: 16.h),
          if (workspace.isCoach) ...[
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16.r),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16.w,
                  vertical: 6.h,
                ),
                leading: Icon(
                  Icons.sports_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('My classes'),
                subtitle: const Text('Today’s coaching classes and attendance'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.myClasses),
              ),
            ),
            SizedBox(height: 16.h),
          ],
          if (ready.isEmpty)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workspace.isOwner
                        ? 'Let’s get you ready.'
                        : 'Your assigned businesses',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    workspace.isOwner
                        ? 'Configure a business to start managing its bookings, customers and collections.'
                        : 'Your owner will complete business setup. Contact them if you need more access.',
                  ),
                ],
              ),
            ),
          if (ready.isNotEmpty &&
              (WorkspaceNavigation(workspace).bookings ||
                  WorkspaceNavigation(workspace).finance)) ...[
            LayoutBuilder(
              builder: (c, constraints) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (WorkspaceNavigation(workspace).bookings)
                    _metric(
                      'Today’s bookings',
                      metricsUnavailable ? '—' : '${s.dashboard?.today ?? 0}',
                      constraints.maxWidth,
                    ),
                  if (workspace.hasPermission('view_finance'))
                    _metric(
                      'Collected today',
                      metricsUnavailable
                          ? '—'
                          : bookingMoney(
                              s.dashboard?.collected ?? 0,
                              workspace.organization?.currency ?? 'INR',
                            ),
                      constraints.maxWidth,
                    ),
                  if (workspace.hasPermission('view_finance'))
                    _metric(
                      'Due amount to collect',
                      s.dueTotal == null &&
                              (s.dueError != null ||
                                  s.dashboard?.outstanding == null)
                          ? '—'
                          : bookingMoney(
                              s.dueTotal ?? s.dashboard?.outstanding ?? 0,
                              workspace.organization?.currency ?? 'INR',
                            ),
                      constraints.maxWidth,
                      fullRow:
                          constraints.maxWidth <
                          780 *
                              (MediaQuery.textScalerOf(context).scale(12) / 12),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            LayoutBuilder(
              builder: (context, constraints) {
                final showDue =
                    workspace.hasPermission('view_finance') ||
                    workspace.hasPermission('collect_payments');
                final upcoming = WorkspaceNavigation(workspace).bookings
                    ? _upcoming(context, s)
                    : const SizedBox.shrink();
                if (!showDue) return upcoming;
                final due = _due(context, s);
                if (constraints.maxWidth >= 900 &&
                    MediaQuery.textScalerOf(context).scale(14) <= 21) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: upcoming),
                      const SizedBox(width: 28),
                      Expanded(flex: 2, child: due),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [upcoming, const SizedBox(height: 28), due],
                );
              },
            ),
            const SizedBox(height: 24),
          ],
          if (pending.isNotEmpty) ...[
            Text(
              ready.isEmpty ? 'Your businesses' : 'Finish your setup',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            ...pending.map((b) => _business(context, b, workspace.isOwner)),
          ],

          if (s.error != null)
            AppErrorWidget(message: s.error!, onRetry: cubit.reload),
        ],
      );
    },
  );
  Widget _upcoming(BuildContext context, HomeScreenModel s) {
    final bookings = s.dashboard?.upcoming ?? const <BookingRecord>[];
    final currency = s.data.organization?.currency ?? 'INR';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Upcoming space bookings',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Today’s schedule, grouped by space.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        if (s.bookingLoading)
          AppLoadingState(
            initial: s.dashboard == null,
            label: s.dashboard == null ? 'Loading bookings…' : null,
          ),
        if (s.bookingError != null)
          AppErrorWidget(
            message: s.bookingError!,
            onRetry: cubit.loadDashboard,
          ),
        if (s.dashboard != null && s.bookingError == null && bookings.isEmpty)
          const AppEmptyState(
            showCard: false,
            title: 'No bookings yet',
            message: 'Upcoming bookings for your assigned spaces appear here.',
            icon: Icons.calendar_month_outlined,
          ),
        for (final id in orderByBusiness(
          bookings,
          (b) => b.selection.businessId,
          s.data.businesses.map((b) => b.id),
        ).map((b) => b.selection.resourceId).toSet()) ...[
          Text(
            '${bookings.firstWhere((b) => b.selection.resourceId == id).businessName} · ${bookings.firstWhere((b) => b.selection.resourceId == id).spaceName}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final booking in bookings.where(
            (b) => b.selection.resourceId == id,
          ))
            BookingCard(
              booking: booking,
              currency: currency,
              canCollect: s.data.hasPermission('collect_payments'),
            ),
        ],
      ],
    );
  }

  Widget _due(BuildContext context, HomeScreenModel s) {
    final currency = s.data.organization?.currency ?? 'INR';
    final canCollect = s.data.hasPermission('collect_payments');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Payments to collect',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Unpaid balances across all dates.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        if (s.dueLoading)
          AppLoadingState(
            initial: s.dueTotal == null,
            label: s.dueTotal == null ? 'Loading balances…' : null,
          ),
        if (s.dueError != null)
          AppErrorWidget(message: s.dueError!, onRetry: () => cubit.loadDue()),
        if (s.dueTotal != null &&
            s.dueError == null &&
            s.dueBookings.isEmpty &&
            s.dueNext == null)
          const AppEmptyState(
            showCard: false,
            title: 'No payments to collect',
            message: 'Bookings with an unpaid balance will appear here.',
            icon: Icons.task_alt_outlined,
          ),
        for (final booking in s.dueBookings)
          CompactBookingCard(
            model: CompactBookingModel.outstanding(booking),
            currency: currency,
            canCollect: canCollect,
          ),
        if (s.dueNext != null)
          TextButton(
            onPressed: s.dueLoading ? null : () => cubit.loadDue(more: true),
            child: const Text('Load more balances'),
          ),
      ],
    );
  }

  Widget _metric(
    String label,
    String value,
    double width, {
    bool fullRow = false,
  }) => SizedBox(
    width: fullRow
        ? width
        : width >= 780 * (MediaQuery.textScalerOf(context).scale(12) / 12)
        ? (width - 24) / 3
        : width >= 300 * (MediaQuery.textScalerOf(context).scale(12) / 12) + 12
        ? (width - 12) / 2
        : width,
    child: AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
  Widget _business(BuildContext context, Business b, bool owner) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(businessIcon(b.type), color: AppColors.lime),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(b.type.label, style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 5),
                    Text(
                      b.ready ? 'Ready' : 'Setup needed',
                      style: TextStyle(
                        fontSize: 11,
                        color: b.ready ? AppColors.lime : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (owner && !b.ready) ...[
            const SizedBox(height: 16),
            AppButton(
              label: b.resources.isEmpty && b.configuration == null
                  ? 'Configure'
                  : 'Continue setup',
              icon: Icons.tune,
              onPressed: () => context.push('/businesses/${b.id}/setup'),
            ),
          ],
        ],
      ),
    ),
  );
}
