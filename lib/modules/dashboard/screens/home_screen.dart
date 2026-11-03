import '../../workspace/models/workspace_navigation.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../widgets/home_greeting_card.dart';
import '../../bookings/widgets/booking_widgets.dart';
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
import '../widgets/home_parts.dart' show homeMoney;
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
  final workboardAnchor = GlobalKey();

  void showCollections() {
    final target = workboardAnchor.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 320),
        alignment: .08,
      );
    }
  }

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
          onWebsite:
              widget.websiteLinks != null && workspace.organization != null
              ? () => showBookingWebsiteLink(
                  context,
                  context.read<WorkspaceCubit>(),
                  widget.websiteLinks!(),
                )
              : null,
          onAlerts: workspace.hasPermission('view_finance')
              ? showCollections
              : null,
          hasAlerts: (s.dueTotal ?? s.dashboard?.outstanding ?? 0) > 0,
          onProfile: () => context.go('/profile'),
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
              builder: (c, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(1);
                final count =
                    1 + (workspace.hasPermission('view_finance') ? 2 : 0);
                final columns = constraints.maxWidth >= 340 && scale <= 1.25
                    ? count
                    : constraints.maxWidth >= 300 && scale <= 1.4
                    ? count.clamp(1, 2)
                    : 1;
                final cardWidth =
                    (constraints.maxWidth - 12 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (WorkspaceNavigation(workspace).bookings)
                      _metric(
                        'Bookings today',
                        metricsUnavailable ? '—' : '${s.dashboard?.today ?? 0}',
                        cardWidth,
                        icon: Icons.event_available_outlined,
                      ),
                    if (workspace.hasPermission('view_finance'))
                      _metric(
                        'Received today',
                        metricsUnavailable
                            ? '—'
                            : homeMoney(
                                s.dashboard?.collected ?? 0,
                                workspace.organization?.currency ?? 'INR',
                              ),
                        cardWidth,
                        icon: Icons.account_balance_wallet_outlined,
                        positive: (s.dashboard?.collected ?? 0) > 0,
                      ),
                    if (workspace.hasPermission('view_finance'))
                      _metric(
                        'Outstanding',
                        s.dueTotal == null &&
                                (s.dueError != null ||
                                    s.dashboard?.outstanding == null)
                            ? '—'
                            : homeMoney(
                                s.dueTotal ?? s.dashboard?.outstanding ?? 0,
                                workspace.organization?.currency ?? 'INR',
                              ),
                        cardWidth,
                        icon: Icons.payments_outlined,
                        onTap: showCollections,
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
          ],
          if (workspace.isCoach) ...[
            const TodayStudentsSection(),
            const SizedBox(height: 28),
          ],
          KeyedSubtree(
            key: workboardAnchor,
            child: HomeWorkboard(
              key: ValueKey(
                'home-workboard-${workspaceAccessScope(workspace)}',
              ),
              model: s,
              cubit: cubit,
              memberships: widget.memberships,
            ),
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
    required IconData icon,
    bool positive = false,
    VoidCallback? onTap,
  }) => SizedBox(
    width: width,
    child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: onTap != null
              ? const [Color(0xFF122D19), Color(0xFF1B581A)]
              : positive
              ? const [Color(0xFF10291C), Color(0xFF103F22)]
              : const [Color(0xFF0C2C19), Color(0xFF074414)],
        ),
        border: Border.all(
          color: const Color(0xFF7DC45E).withValues(alpha: .44),
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _StatusWavePainter()),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 142),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          icon,
                          size: 25,
                          color: onTap != null
                              ? const Color(0xFFFFC45F)
                              : AppColors.lime,
                        ),
                        if (onTap != null) ...[
                          const Spacer(),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 20,
                            color: const Color(0xFFFFDC82),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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

class _StatusWavePainter extends CustomPainter {
  const _StatusWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final wave = Path()
      ..moveTo(0, size.height * .89)
      ..cubicTo(
        size.width * .27,
        size.height * .81,
        size.width * .52,
        size.height * .99,
        size.width,
        size.height * .73,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      wave,
      Paint()..color = const Color(0xFF55F21F).withValues(alpha: .15),
    );
    final edge = Path()
      ..moveTo(0, size.height * .89)
      ..cubicTo(
        size.width * .27,
        size.height * .81,
        size.width * .52,
        size.height * .99,
        size.width,
        size.height * .73,
      );
    canvas.drawPath(
      edge,
      Paint()
        ..color = const Color(0xFF8BFF3A).withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
