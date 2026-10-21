import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_form_sections.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/repositories/booking_opening_mapper.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';

Workspace workspace(Map<String, dynamic> configuration) => Workspace(
  businesses: [
    Business(
      id: 'business',
      name: 'Court',
      type: BusinessType.tennis,
      status: 'ready',
      locationId: 'location',
      version: 1,
      resources: const [],
      configuration: configuration,
    ),
  ],
);
void main() {
  test('24 hour label follows opening hours, not pricing rules', () {
    final allDay = workspace({
      'kind': 'court_v1',
      'courts': [
        {
          'id': 'court',
          'operating': {'all_day': true},
        },
      ],
    });
    expect(bookingOpensAllDay(allDay, 'business', 'court', 'hourly'), isTrue);
    final scheduled = workspace({
      'kind': 'court_v1',
      'courts': [
        {
          'id': 'court',
          'operating': {'all_day': false},
          'rates': [
            {'all_day': true},
          ],
        },
      ],
    });
    expect(
      bookingOpensAllDay(scheduled, 'business', 'court', 'hourly'),
      isFalse,
    );
    final turf = workspace({
      'kind': 'turf_v1',
      'operating': {'all_day': true},
      'offerings': [
        {
          'id': 'football',
          'hours_override': {'all_day': false},
        },
      ],
    });
    expect(bookingOpensAllDay(turf, 'business', 'ground', 'football'), isFalse);
  });
  for (final showOffset in [false, true]) {
    testWidgets(
      'midnight offset visibility $showOffset retains next-day slot identity',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BookingTimeGrid(
                slots: const [
                  BookingSlot(
                    '00:00',
                    false,
                    0,
                    null,
                    false,
                    null,
                    'end_only',
                    '2030-06-05',
                  ),
                ],
                selectedDate: '2030-06-04',
                showDayOffset: showOffset,
                onSelected: (_) {},
              ),
            ),
          ),
        );
        expect(
          find.text(showOffset ? '24:00 +1 day' : '24:00'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('booking-time-00:00')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
