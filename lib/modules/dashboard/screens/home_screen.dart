import '../../workspace/models/workspace_navigation.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../widgets/home_greeting_card.dart';
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
import '../../coaching/widgets/today_students_section.dart';
import '../widgets/home_workboard.dart';
import '../../admissions/repositories/admission_repository.dart';
import '../../workspace/models/workspace_access.dart';
import '../../booking_website/repositories/booking_website_link_repository.dart';
import '../../booking_website/widgets/booking_website_link_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.memberships, this.websiteLinks});
  final MembershipActions? memberships;
  final BookingWebsiteLinkRepository Function()? websiteLinks;
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
      final showStatus =
          ready.isNotEmpty &&
          (WorkspaceNavigation(workspace).bookings ||
              WorkspaceNavigation(workspace).finance);
      return AppPage(
        title: workspace.organization?.name ?? 'Your organization',
        header: HomeGreetingCard(
          name: context.watch<AuthCubit?>()?.state.user?.name ?? '',
          organization: workspace.organization?.name ?? 'Your organization',
          logo: workspace.logo,
          heroImage: s.heroImage,
        ),
        maxWidth: 1200,
        scrollId: 'home-dashboard',
        onRefresh: cubit.refreshBookings,
        floatingActionButton: workspace.hasPermission('manage_bookings')
            ? NewBookingFab(onPressed: () => context.push('/booking/new'))
            : null,
        children: [
          if (s.error != null && workspace.organization != null) ...[
            AppSectionFallback(
              message: s.error!,
              onRetry: cubit.refreshBookings,
            ),
            const SizedBox(height: 12),
          ],
          if (widget.websiteLinks != null &&
              workspace.organization != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('home-booking-website'),
                onPressed: () => showBookingWebsiteLink(
                  context,
                  context.read<WorkspaceCubit>(),
                  widget.websiteLinks!(),
                ),
                icon: const Icon(Icons.language_outlined),
                label: const Text('Booking website'),
              ),
            ),
            const SizedBox(height: 16),
          ],
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
          if (showStatus) ...[
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
          ],
          if (workspace.isCoach) ...[
            const TodayStudentsSection(),
            const SizedBox(height: 28),
          ],
          HomeWorkboard(
            key: ValueKey('home-workboard-${workspaceAccessScope(workspace)}'),
            model: s,
            cubit: cubit,
            memberships: widget.memberships,
          ),
          if (pending.isNotEmpty) ...[
            Text(
              ready.isEmpty ? 'Your businesses' : 'Finish your setup',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            ...pending.map((b) => _business(context, b, workspace.isOwner)),
          ],

          // Home keeps what it has; only an empty page gets a fallback.
          if (s.error != null && workspace.organization == null)
            const AppSectionFallback(
              message: 'Couldn’t load your workspace right now.',
            ),
        ],
      );
    },
  );
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
