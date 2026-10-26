import '../../modules/workspace/models/workspace_navigation.dart';
import '../../modules/booking_website/screens/website_settings_screen.dart';
import '../../modules/coaching/screens/coach_classes_screen.dart';
import '../../modules/booking_blocks/models/slot_block_models.dart';
import '../../modules/booking_blocks/screens/slot_block_screens.dart';
import '../../modules/admissions/screens/admissions_screen.dart';
import '../../modules/admissions/screens/admission_form_screen.dart';
import '../../modules/admissions/screens/admission_detail_screen.dart';
import '../../modules/admissions/repositories/admission_repository.dart';
import '../../di/injection.dart';
import '../../modules/messages/screens/templates_screen.dart';
import '../../modules/messages/screens/template_editor_screen.dart';
import '../../modules/messages/screens/message_preview_screen.dart';
import '../../modules/messages/models/message_template.dart';
import '../../modules/profile/screens/organization_edit_screen.dart';
import '../../modules/customers/screens/customers_screen.dart';
import '../../modules/customers/screens/customer_detail_screen.dart';
import '../../modules/expenses/screens/expenses_screen.dart';
import '../../modules/expenses/screens/expense_form_screen.dart';
import '../../modules/expenses/screens/expense_detail_screen.dart';
import '../../modules/income/screens/income_screen.dart';
import '../../modules/businesses/screens/business_management_screen.dart';
import '../../modules/businesses/screens/business_detail_screen.dart';
import '../../modules/profile/screens/organization_details_screen.dart';
import '../../modules/accounts/screens/accounts_screen.dart';
import '../../modules/accounts/screens/account_settings_screen.dart';
import '../../modules/accounts/screens/finance_entry_screen.dart';
import '../../modules/accounts/screens/accounts_reports_screen.dart';
import '../../modules/accounts/screens/accounts_transactions_screen.dart';
import '../../modules/accounts/models/accounts_models.dart';
import '../../modules/bookings/screens/booking_form_screen.dart';
import '../../modules/bookings/screens/booking_detail_screen.dart';
import '../../modules/bookings/screens/booking_list_screen.dart';
import '../../modules/bookings/models/booking_models.dart';
import '../../modules/bookings/models/booking_list_model.dart';
import '../../modules/hall/screens/hall_setup_screen.dart';
import '../../modules/court/screens/court_setup_screen.dart';
import '../../modules/pool/screens/pool_setup_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../modules/workspace/models/workspace.dart';
import '../../modules/turf/screens/turf_setup_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../app_config.dart';
import '../../modules/auth/cubit/auth_cubit.dart';
import '../../modules/auth/screens/auth_screen.dart';
import '../../modules/auth/screens/verification_screen.dart';
import '../../modules/workspace/cubit/workspace_cubit.dart';
import '../../modules/organization/screens/organization_screen.dart';
import '../../modules/businesses/screens/businesses_screen.dart';
import '../../modules/businesses/screens/resource_setup_screen.dart';
import '../../modules/dashboard/screens/home_screen.dart';
import '../../modules/dashboard/screens/startup_screen.dart';
import '../../modules/profile/screens/profile_screen.dart';
import '../../modules/team/screens/team_screen.dart';
import '../../modules/team/screens/staff_assignment_screen.dart';
import '../../modules/team/screens/invitation_screen.dart';
import 'routes.dart';
import '../../modules/auth/screens/password_update_screen.dart';
import 'route_guard.dart';
import '../../modules/agent_calls/screens/agent_service_screen.dart';
import '../../modules/support/screens/support_screens.dart';
import '../../modules/agent_calls/screens/call_logs_screen.dart';

class RouterRefresh extends ChangeNotifier {
  RouterRefresh(List<Stream<Object?>> streams) {
    for (final stream in streams) {
      subscriptions.add(stream.listen((_) => notifyListeners()));
    }
  }
  final subscriptions = <StreamSubscription<Object?>>[];
  @override
  void dispose() {
    for (final s in subscriptions) {
      s.cancel();
    }
    super.dispose();
  }
}

GoRouter createRouter(
  AuthCubit auth,
  WorkspaceCubit workspace,
  RouterRefresh refresh,
) {
  // Keep browser refresh/share links on pushed setup and team pages.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  return GoRouter(
    initialLocation: Routes.register,
    refreshListenable: refresh,
    redirect: (c, s) {
      final next = routeRedirect(
        auth.state,
        workspace.state,
        s.uri,
        requireVerification: AppConfig.requireEmailVerification,
        continuation: auth.continuation,
      );
      final target = next == null ? s.uri.path : Uri.parse(next).path;
      if (auth.continuation != null &&
          auth.state.status == AuthStatus.signedIn &&
          !auth.state.busy &&
          auth.state.user?.passwordRecovery != true &&
          (!AppConfig.requireEmailVerification ||
              auth.state.user?.verified == true) &&
          !const {
            '/loading',
            '/verify',
            '/sign-in',
            '/register',
            '/auth-callback',
            '/auth-callback/',
            '/update-password',
          }.contains(target)) {
        auth.consumeContinuation();
      }
      return next;
    },
    errorBuilder: (c, s) => const AppPage(
      title: 'Page not found',
      children: [
        AppEmptyState(
          title: 'This page is unavailable',
          message: 'Use Home to return to your workspace.',
        ),
      ],
    ),
    routes: [
      GoRoute(
        path: Routes.bookingWebsite,
        builder: (c, s) => const WebsiteSettingsScreen(),
      ),
      GoRoute(
        path: Routes.agentCalls,
        builder: (c, s) => const AgentServiceScreen(),
      ),
      GoRoute(path: Routes.support, builder: (c, s) => const SupportScreen()),
      GoRoute(
        path: '${Routes.support}/:id',
        builder: (c, s) => SupportThreadScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: Routes.callLogs, builder: (c, s) => const CallLogsScreen()),
      GoRoute(
        path: '/profile/message-templates',
        builder: (c, s) => const TemplatesScreen(),
      ),
      GoRoute(
        path: '/profile/message-templates/edit',
        builder: (c, s) =>
            TemplateEditorScreen(source: s.extra as MessageTemplate?),
      ),
      GoRoute(
        path: '/booking/:id/share',
        builder: (c, s) =>
            MessagePreviewScreen(bookingId: s.pathParameters['id']!),
      ),
      GoRoute(path: Routes.expenses, builder: (c, s) => const ExpensesScreen()),
      GoRoute(path: Routes.income, builder: (c, s) => const IncomeScreen()),
      GoRoute(
        path: Routes.addExpense,
        builder: (c, s) => const ExpenseFormScreen(),
      ),
      GoRoute(
        path: '/expenses/:id',
        builder: (c, s) => ExpenseDetailScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/auth-callback', builder: (c, s) => const StartupScreen()),
      GoRoute(
        path: '/update-password',
        builder: (c, s) => const AuthSplitLayout(child: PasswordUpdateScreen()),
      ),
      GoRoute(
        path: Routes.register,
        builder: (c, s) => AuthSplitLayout(
          child: AuthScreen(
            invitationToken: s.uri.queryParameters['invite'],
            returnTo: s.uri.queryParameters['from'],
          ),
        ),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (c, s) => AuthSplitLayout(
          child: AuthScreen(
            register: false,
            returnTo: s.uri.queryParameters['from'],
            invitationToken: s.uri.queryParameters['invite'],
          ),
        ),
      ),
      GoRoute(path: Routes.loading, builder: (c, s) => const StartupScreen()),
      GoRoute(
        path: '/verify',
        builder: (c, s) => const AuthSplitLayout(child: VerificationScreen()),
      ),
      GoRoute(
        path: Routes.organization,
        builder: (c, s) => const OrganizationScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (c, s) => const BusinessesScreen(onboarding: true),
      ),
      GoRoute(
        path: Routes.invite,
        builder: (c, s) =>
            InvitationScreen(token: s.uri.queryParameters['token'] ?? ''),
      ),
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => BlocBuilder<WorkspaceCubit, WorkspaceState>(
          bloc: workspace,
          builder: (context, snapshot) => AdaptiveScaffold(
            shell: shell,
            branches: WorkspaceNavigation(snapshot.data).branches,
            onTabSelected: workspace.revalidateRetainedPages,
          ),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (c, s) {
                  final admissions = getIt<AdmissionRepository>();
                  return HomeScreen(
                    memberships: admissions is MembershipActions
                        ? admissions as MembershipActions
                        : null,
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.calendar,
                builder: (c, s) =>
                    const BookingListScreen(mode: BookingListMode.calendar),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.bookings,
                builder: (c, s) =>
                    const BookingListScreen(mode: BookingListMode.bookings),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.payments,
                builder: (c, s) => const AccountsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (c, s) => const ProfileScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.myClasses,
                builder: (c, s) => const CoachClassesScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.bookingBlocks,
        builder: (c, s) => SlotBlocksScreen(
          launch: s.extra is BlockLaunch
              ? s.extra as BlockLaunch
              : const BlockLaunch(),
        ),
      ),
      GoRoute(
        path: Routes.newBookingBlock,
        builder: (c, s) => NewSlotBlockScreen(
          launch: s.extra is BlockLaunch
              ? s.extra as BlockLaunch
              : const BlockLaunch(),
        ),
      ),
      GoRoute(
        path: '/accounts/settings',
        builder: (c, s) => const AccountSettingsScreen(),
      ),
      GoRoute(
        path: '/accounts/cash/opening',
        builder: (c, s) => const BankAccountScreen(cash: true),
      ),
      GoRoute(
        path: '/accounts/bank/new',
        builder: (c, s) => const BankAccountScreen(),
      ),
      GoRoute(
        path: '/accounts/entry/:kind',
        builder: (c, s) =>
            ['income', 'expense', 'transfer'].contains(s.pathParameters['kind'])
            ? s.pathParameters['kind'] == 'expense'
                  ? const ExpenseFormScreen()
                  : FinanceEntryScreen(kind: s.pathParameters['kind']!)
            : const AppPage(
                title: 'Invalid entry type',
                back: true,
                children: [],
              ),
      ),
      GoRoute(
        path: '/accounts/reports',
        builder: (c, s) => AccountsReportsScreen(
          filter: s.extra is FinanceFilter
              ? s.extra as FinanceFilter
              : FinanceFilter.month(DateTime.now()),
        ),
      ),
      GoRoute(
        path: '/accounts/transactions',
        builder: (c, s) => AccountsTransactionsScreen(
          filter: s.extra is FinanceFilter
              ? s.extra as FinanceFilter
              : FinanceFilter.month(DateTime.now()),
        ),
      ),
      GoRoute(
        path: '/accounts/transaction',
        builder: (c, s) => s.extra is FinanceTransaction
            ? AccountsTransactionScreen(entry: s.extra as FinanceTransaction)
            : const AppPage(
                title: 'Open a transaction from Accounts',
                back: true,
                children: [],
              ),
      ),

      GoRoute(path: '/admissions', builder: (c, s) => const AdmissionsScreen()),
      GoRoute(
        path: '/admissions/new',
        builder: (c, s) => AdmissionFormScreen(
          formKind:
              const {
                'plans',
                'coaching',
              }.contains(s.uri.queryParameters['kind'])
              ? s.uri.queryParameters['kind']
              : null,
          renewalId: s.uri.queryParameters['renewal_id'],
          businessId: s.uri.queryParameters['business_id'],
          poolId: s.uri.queryParameters['space_id'],
          planId: s.uri.queryParameters['plan_id'],
          date: s.uri.queryParameters['date'],
        ),
      ),
      GoRoute(
        path: '/admissions/:id',
        builder: (c, s) => AdmissionDetailScreen(
          id: s.pathParameters['id']!,
          collectOnOpen: s.uri.queryParameters['collect'] == 'true',
        ),
      ),
      GoRoute(
        path: '/booking/new',
        builder: (c, s) => BookingFormScreen(
          launch: BookingLaunch(
            businessId: s.uri.queryParameters['business_id'],
            spaceId: s.uri.queryParameters['space_id'],
            date: s.uri.queryParameters['date'],
            time: s.uri.queryParameters['time'],
          ),
        ),
      ),
      GoRoute(
        path: '/booking/:id/reschedule',
        builder: (c, s) => BookingFormScreen(
          launch: BookingLaunch(rescheduleId: s.pathParameters['id']),
        ),
      ),
      GoRoute(
        path: '/booking/:id',
        builder: (c, s) => BookingDetailScreen(
          id: s.pathParameters['id']!,
          justCreated: s.uri.queryParameters['created'] == '1',
          collectOnOpen: s.uri.queryParameters['action'] == 'collect',
        ),
      ),
      GoRoute(
        path: Routes.customers,
        builder: (c, s) => const CustomersScreen(),
      ),
      GoRoute(
        path: '/customers/:id',
        builder: (c, s) => CustomerDetailScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.businesses,
        builder: (c, s) => const BusinessManagementScreen(),
      ),
      GoRoute(
        path: Routes.addBusiness,
        builder: (c, s) => const BusinessesScreen(),
      ),
      GoRoute(
        path: Routes.organizationEdit,
        builder: (c, s) => const OrganizationEditScreen(),
      ),
      GoRoute(
        path: Routes.organizationDetails,
        builder: (c, s) => const OrganizationDetailsScreen(),
      ),
      GoRoute(
        path: '/businesses/:id',
        builder: (c, s) => BusinessDetailScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/businesses/:id/bookings',
        builder: (c, s) =>
            BookingListScreen(initialBusinessId: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/businesses/:id/setup',
        builder: (c, s) {
          final id = s.pathParameters['id']!;
          final business = c
              .read<WorkspaceCubit>()
              .state
              .data
              .businesses
              .where((b) => b.id == id)
              .firstOrNull;
          if (business?.type == BusinessType.hall) {
            return HallSetupScreen(businessId: id);
          }
          if ([
            BusinessType.badminton,
            BusinessType.tennis,
            BusinessType.basketball,
          ].contains(business?.type)) {
            return CourtSetupScreen(businessId: id);
          }
          if (business?.type == BusinessType.pool) {
            return PoolSetupScreen(businessId: id);
          }
          return business?.type == BusinessType.turf
              ? TurfSetupScreen(businessId: id)
              : ResourceSetupScreen(businessId: id);
        },
      ),
      GoRoute(
        path: '/businesses/:id/settings',
        builder: (c, s) {
          final id = s.pathParameters['id']!;
          final business = c
              .read<WorkspaceCubit>()
              .state
              .data
              .businesses
              .where((b) => b.id == id)
              .firstOrNull;
          if (business?.type == BusinessType.hall) {
            return HallSetupScreen(businessId: id);
          }
          if ([
            BusinessType.badminton,
            BusinessType.tennis,
            BusinessType.basketball,
          ].contains(business?.type)) {
            return CourtSetupScreen(businessId: id);
          }
          return business?.type == BusinessType.pool
              ? PoolSetupScreen(businessId: id)
              : TurfSetupScreen(businessId: id, editMode: true);
        },
      ),
      GoRoute(path: Routes.team, builder: (c, s) => const TeamScreen()),
      GoRoute(path: Routes.teamCoaches, redirect: (c, s) => Routes.team),
      GoRoute(
        path: '/team/invite',
        builder: (c, s) => const StaffAssignmentScreen(),
      ),
      GoRoute(
        path: '/team/edit',
        builder: (c, s) => s.extra is Map<String, dynamic>
            ? StaffAssignmentScreen(member: s.extra as Map<String, dynamic>)
            : const AppPage(
                back: true,
                title: 'Open a staff member from Team',
                children: [],
              ),
      ),
    ],
  );
}
