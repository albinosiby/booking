import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/accounts/repositories/accounts_repository.dart';
import 'package:eden_booking/modules/accounts/screens/accounts_screen.dart';
import 'package:eden_booking/modules/accounts/widgets/accounts_overview_widgets.dart';
import 'package:eden_booking/modules/bookings/models/booking_list_model.dart';
import 'package:eden_booking/modules/bookings/repositories/booking_repository.dart';
import 'package:eden_booking/modules/bookings/screens/booking_list_screen.dart';
import 'package:eden_booking/modules/income/repositories/income_repository.dart';
import 'package:eden_booking/modules/staff_cash/repositories/staff_cash_repository.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'accounts_module_test.dart' show FakeAccountsRepository;
import 'booking_module_test.dart' show BookingSource;
import 'booking_payments_layout_test.dart' show PaymentsRepository;
import 'income_module_test.dart' show IncomeRepo;
import 'staff_cash_test.dart' show FakeStaffCash;

void main() {
  for (final back in ['toolbar', 'system']) {
    for (final opens in [1, 2]) {
      testWidgets(
        '$back Back returns from Payments once after $opens entry taps',
        (tester) async {
          tester.view.physicalSize = const Size(390, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await getIt.reset();
          registerFeatureDependencies(getIt);
          final workspace = WorkspaceCubit(BookingSource());
          await workspace.load();
          final accounts = FakeAccountsRepository(),
              bookings = PaymentsRepository();
          getIt.unregister<AccountsRepository>();
          getIt.registerSingleton<AccountsRepository>(accounts);
          getIt.unregister<BookingRepository>();
          getIt.registerSingleton<BookingRepository>(bookings);
          getIt.unregister<IncomeRepository>();
          getIt.registerSingleton<IncomeRepository>(IncomeRepo());
          getIt.unregister<IStaffCashRepository>();
          getIt.registerSingleton<IStaffCashRepository>(FakeStaffCash());
          final router = GoRouter(
            initialLocation: '/payments',
            routes: [
              StatefulShellRoute.indexedStack(
                builder: (_, _, shell) => AdaptiveScaffold(shell: shell),
                branches: [
                  for (final path in [
                    '/home',
                    '/calendar',
                    '/bookings',
                    '/payments',
                    '/profile',
                  ])
                    StatefulShellBranch(
                      routes: [
                        GoRoute(
                          path: path,
                          builder: (_, _) => path == '/payments'
                              ? const AccountsScreen()
                              : Text(path),
                        ),
                      ],
                    ),
                ],
              ),
              GoRoute(
                path: '/accounts/booking-dues',
                builder: (_, _) => const BookingListScreen(
                  mode: BookingListMode.payments,
                  initialDueView: true,
                ),
              ),
            ],
          );
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            router.dispose();
            await workspace.close();
            await accounts.events.close();
            await bookings.events.close();
            await getIt.reset();
          });
          await tester.pumpWidget(
            BlocProvider.value(
              value: workspace,
              child: ScreenUtilInit(
                designSize: const Size(390, 844),
                builder: (_, _) => MaterialApp.router(
                  theme: darkTheme(),
                  routerConfig: router,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final firstLoads = accounts.filters.length;
          final banner = tester.widget<FinanceDuesBanner>(
            find.byType(FinanceDuesBanner),
          );
          // Model taps reaching the entry point before the route transition ends.
          for (var i = 0; i < opens; i++) {
            banner.onTap!();
          }
          await tester.pumpAndSettle();
          expect(find.byType(BookingListScreen), findsOneWidget);
          if (back == 'toolbar') {
            await tester.tap(find.byTooltip('Back'));
          } else {
            await tester.binding.handlePopRoute();
          }
          await tester.pumpAndSettle();
          expect(find.byType(BookingListScreen), findsNothing);
          expect(find.byType(FinanceDuesBanner), findsOneWidget);
          expect(accounts.filters.length, firstLoads + 1);
          // The guard must release when the page closes, so it can be reopened.
          tester
              .widget<FinanceDuesBanner>(find.byType(FinanceDuesBanner))
              .onTap!();
          await tester.pumpAndSettle();
          expect(find.byType(BookingListScreen), findsOneWidget);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byType(BookingListScreen), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
