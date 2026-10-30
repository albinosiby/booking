import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/models/booking_form_model.dart';
import 'package:eden_booking/modules/bookings/models/booking_space_group.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_form_sections.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_space_selection.dart';

BookingBusiness turf() => BookingBusiness(
  id: 'turf',
  name: 'Eden Sports Arena',
  type: 'turf',
  timezone: 'Asia/Kolkata',
  today: '2030-06-04',
  spaces: [
    for (final id in ['a', 'b', 'full'])
      BookingSpace(
        id: id,
        name: id == 'full'
            ? 'Full Ground'
            : id == 'a'
            ? 'Half A'
            : 'Half B',
        capacity: 1,
        options: [
          for (final sport in ['football', 'cricket'])
            BookingOption(
              id: '$id-$sport',
              name: sport,
              kind: 'hourly',
              sport: sport,
              durations: [60],
              defaultDuration: 60,
            ),
        ],
      ),
  ],
);
void main() {
  for (final dark in [false, true]) {
    for (final width in [320.0, 900.0, 1200.0]) {
      testWidgets(
        'pool booking choices stay inside Space as full-width elevated buttons at $width; dark=$dark',
        (tester) async {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          const business = BookingBusiness(
            id: 'pool-business',
            name: 'Swimming',
            type: 'pool',
            timezone: 'Asia/Kolkata',
            today: '2030-06-04',
            spaces: [
              BookingSpace(
                id: 'pool',
                name: 'Pool 1',
                capacity: 20,
                options: [
                  BookingOption(
                    id: 'regular',
                    name: 'Single visit',
                    kind: 'hourly',
                    durations: [60],
                    defaultDuration: 60,
                  ),
                  BookingOption(
                    id: 'group',
                    name: 'School group',
                    kind: 'group',
                    durations: [60],
                    defaultDuration: 60,
                    groupMode: 'at_least',
                    groupPeople: 15,
                  ),
                ],
              ),
            ],
          );
          final model = BookingFormModel(
            catalog: const BookingCatalog(businesses: [business]),
            draft: BookingDraft(
              businessId: business.id,
              spaceId: 'pool',
              optionId: 'regular',
            ),
            poolMode: PoolBookingMode.swimming,
            loading: false,
          );
          String? option;
          PoolBookingMode? mode;
          Future<void> pump(BookingFormModel value) => tester.pumpWidget(
            ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, _) => MaterialApp(
                theme: dark ? darkTheme() : lightTheme(),
                home: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(width == 320 ? 1.7 : 1),
                  ),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: BookingSpaceSelection(
                          model: value,
                          businesses: const [business],
                          onBusiness: (_) {},
                          onSport: (_) {},
                          onSpace: (_) {},
                          onOption: (id) => option = id,
                          onPoolMode: (value) => mode = value,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await pump(model);
          final buttons = [
            for (final label in [
              'Regular admission',
              'Group offer',
              'Swimming plan',
              'Coaching',
            ])
              find.widgetWithText(ElevatedButton, label),
          ];
          expect(find.text('Single visit'), findsNothing);
          expect(find.byType(ChoiceChip), findsNothing);
          expect(find.text('Booking option'), findsOneWidget);
          expect(
            find.text(
              'School group\n${model.visibleOptions.last.groupExplanation}',
            ),
            findsOneWidget,
          );
          for (final (i, button) in buttons.indexed) {
            expect(button, findsOneWidget);
            expect(
              find.ancestor(
                of: button,
                matching: find.byType(BookingFormSection),
              ),
              findsOneWidget,
            );
            expect(tester.getSize(button).width, closeTo(width - 64, .01));
            if (i > 0) {
              expect(
                tester.getTopLeft(button).dy,
                greaterThan(tester.getBottomLeft(buttons[i - 1]).dy),
              );
            }
            final colors = (dark ? darkTheme() : lightTheme()).colorScheme;
            final color = tester
                .widget<ElevatedButton>(button)
                .style!
                .backgroundColor!
                .resolve({});
            expect(color == colors.primary, i == 2);
          }
          await tester.ensureVisible(buttons[1]);
          await tester.tap(buttons[1]);
          expect(option, 'group');
          await tester.ensureVisible(buttons[0]);
          await tester.tap(buttons[0]);
          expect(option, 'regular');
          await tester.ensureVisible(buttons[3]);
          await tester.tap(buttons[3]);
          expect(mode, PoolBookingMode.coaching);
          await pump(model.copyWith(saving: true));
          for (final button in buttons) {
            expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  test(
    'ground names are shown once, full ground follows halves, and stored names are retained',
    () {
      final source = turf();
      final spaces = [
        for (final space in source.spaces.reversed)
          BookingSpace(
            id: space.id,
            name: 'Main Ground · Main Ground · ${space.name}',
            capacity: space.capacity,
            options: space.options,
          ),
      ];
      final groups = BookingSpaceGroup.turf(spaces);
      expect(groups.single.name, 'Main Ground');
      expect(groups.single.choices.map((c) => c.title), [
        'Half A',
        'Half B',
        'Full Ground',
      ]);
      expect(spaces.first.name, 'Main Ground · Main Ground · Full Ground');
      final other = BookingSpace(
        id: 'other',
        name: 'Second Ground · Half A',
        capacity: 1,
        options: source.spaces.first.options,
      );
      expect(BookingSpaceGroup.turf([...spaces, other]).length, 2);
      expect(BookingSpaceGroup.turf([spaces.first]).single.choices.length, 1);
    },
  );

  testWidgets(
    'equal business cards scroll directly and ground layout keeps selection callbacks intact',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = turf();
      final business = BookingBusiness(
        id: source.id,
        name: source.name,
        type: source.type,
        timezone: source.timezone,
        today: source.today,
        spaces: [
          for (final space in source.spaces.reversed)
            BookingSpace(
              id: space.id,
              name: 'Main Ground · Main Ground · ${space.name}',
              capacity: space.capacity,
              options: space.options,
            ),
        ],
      );
      final other = BookingBusiness(
        id: 'court',
        name: 'Eden Badminton',
        type: 'badminton',
        timezone: source.timezone,
        today: source.today,
        spaces: [],
      );
      final model = BookingFormModel(
        catalog: BookingCatalog(businesses: [business, other]),
        draft: BookingDraft(
          businessId: 'turf',
          spaceId: 'a',
          optionId: 'a-football',
          sport: 'football',
        ),
        loading: false,
      );
      String? selectedBusiness, selectedSpace;
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            theme: darkTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: BookingSpaceSelection(
                    model: model,
                    businesses: [business, other],
                    onBusiness: (id) => selectedBusiness = id,
                    onSport: (_) {},
                    onSpace: (id) => selectedSpace = id,
                    onOption: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Main Ground'), findsOneWidget);
      expect(find.text('Main Ground · Main Ground · Half A'), findsNothing);
      final a = find.byKey(const ValueKey('booking-space-a'));
      final b = find.byKey(const ValueKey('booking-space-b'));
      final full = find.byKey(const ValueKey('booking-space-full'));
      expect(tester.getTopLeft(a).dy, tester.getTopLeft(b).dy);
      expect(
        tester.getTopLeft(full).dy,
        greaterThan(tester.getBottomLeft(a).dy),
      );
      expect(tester.getSize(full).width, greaterThan(tester.getSize(a).width));
      await tester.tap(full);
      expect(selectedSpace, 'full');
      final turfCard = find.byKey(const ValueKey('booking-business-turf'));
      final size = tester.getSize(turfCard);
      final courtCard = find.byKey(const ValueKey('booking-business-court'));
      await tester.ensureVisible(courtCard);
      expect(tester.getSize(courtCard), size);
      await tester.tap(courtCard);
      await tester.pumpAndSettle();
      expect(selectedBusiness, 'court');
      expect(find.text('Choose business'), findsNothing);
      expect(
        find.byKey(const ValueKey('booking-change-business')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets('Space cards fit narrow enlarged text; dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final business = turf();
      final model = BookingFormModel(
        catalog: BookingCatalog(businesses: [business]),
        draft: BookingDraft(
          businessId: 'turf',
          spaceId: 'a',
          optionId: 'a-football',
          sport: 'football',
        ),
        loading: false,
      );
      String? sport, space;
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            theme: dark ? darkTheme() : lightTheme(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.7)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: BookingSpaceSelection(
                      model: model,
                      businesses: [business],
                      onBusiness: (_) {},
                      onSport: (v) => sport = v,
                      onSpace: (v) => space = v,
                      onOption: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('booking-space-summary')), findsNothing);
      expect(find.text('Booking option'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('booking-sport-cricket')),
      );
      await tester.tap(find.byKey(const ValueKey('booking-sport-cricket')));
      expect(sport, 'cricket');
      await tester.ensureVisible(find.byKey(const ValueKey('booking-space-b')));
      await tester.tap(find.byKey(const ValueKey('booking-space-b')));
      expect(space, 'b');
      expect(
        tester
            .widget<BookingChoiceCard>(
              find.byKey(const ValueKey('booking-space-a')),
            )
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }
  test('rescheduling derives the sport from the selected offering', () {
    final model = BookingFormModel(
      catalog: BookingCatalog(businesses: [turf()]),
      draft: BookingDraft(
        businessId: 'turf',
        spaceId: 'a',
        optionId: 'a-cricket',
      ),
    );
    expect(model.selectedSport, 'cricket');
    expect(model.visibleOptions.single.id, 'a-cricket');
    expect(model.spaceSummary, 'Cricket · Half A');
  });
}
