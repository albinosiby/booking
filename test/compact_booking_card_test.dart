import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/modules/bookings/models/compact_booking_model.dart';
import 'package:eden_booking/modules/bookings/widgets/compact_booking_card.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final scenario in [
      (status: 'confirmed', balance: 50000, permission: true, collect: true),
      (status: 'confirmed', balance: 15000, permission: true, collect: true),
      (status: 'confirmed', balance: 0, permission: true, collect: false),
      (status: 'cancelled', balance: 50000, permission: true, collect: false),
      (status: 'confirmed', balance: 50000, permission: false, collect: false),
    ]) {
      testWidgets(
        'shared card collection follows balance and permission: $scenario $brightness',
        (tester) async {
          tester.view.physicalSize = const Size(320, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final router = GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => Scaffold(
                  body: SingleChildScrollView(
                    child: CompactBookingCard(
                      model: CompactBookingModel(
                        id: 'one',
                        reference: 'BK-123',
                        customer: 'Customer',
                        phone: '9876543210',
                        business: 'Eden Sports Arena',
                        space: 'Main Ground · Half A',
                        option: 'Football',
                        start: '2030-06-04T23:00',
                        end: '2030-06-05T00:00',
                        status: scenario.status,
                        balance: scenario.balance,
                        total: 50000,
                      ),
                      currency: 'INR',
                      canCollect: scenario.permission,
                    ),
                  ),
                ),
              ),
              GoRoute(
                path: '/booking/:id',
                builder: (_, state) => Scaffold(
                  body: Text(
                    state.uri.queryParameters['action'] == 'collect'
                        ? 'collect destination'
                        : 'details destination',
                  ),
                ),
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, _) => MaterialApp.router(
                routerConfig: router,
                theme: ThemeData(useMaterial3: true, brightness: brightness),
                builder: (_, child) => MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.3),
                  ),
                  child: child!,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('Collect'),
            scenario.collect ? findsOneWidget : findsNothing,
          );
          expect(find.textContaining('5 Jun 2030, 24:00'), findsOneWidget);
          expect(find.text('9876543210'), findsOneWidget);
          expect(find.text('4 Jun 2030'), findsOneWidget);
          expect(
            tester.getSize(find.byType(CompactBookingCard)).height,
            lessThan(240),
          );
          expect(tester.takeException(), isNull);
          await tester.tap(
            find.text(scenario.collect ? 'Collect' : 'Customer'),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(
              scenario.collect ? 'collect destination' : 'details destination',
            ),
            findsOneWidget,
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
