import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/admissions/cubit/admission_cubit.dart';
import 'package:eden_booking/modules/admissions/cubit/admission_slot_chart_cubit.dart';
import 'package:eden_booking/modules/admissions/cubit/admission_state.dart';
import 'package:eden_booking/modules/admissions/models/admission_slot_chart.dart';
import 'package:eden_booking/modules/admissions/widgets/admission_form_fields.dart';
import 'package:eden_booking/modules/admissions/widgets/admission_slot_chart.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/models/slot_holder.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_form_sections.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'admissions_test.dart' show AdmissionsFake, workspace;

final chartJson = {
  'timezone': 'Asia/Kolkata',
  'expires_on': '2030-07-31',
  'dates': ['2030-06-05', '2030-06-07'],
  'slots': [
    {
      'time': '06:00',
      'end_time': '07:00',
      'session_count': 2,
      'capacity': 1,
      'status': 'taken',
      'remaining_capacity': 0,
      'clash_count': 1,
      'clashes': [
        {
          'date': '2030-06-05',
          'label': 'Wed, 5 Jun 2030 at 6:00 AM',
          'starts_at': '2030-06-05T00:30:00.000Z',
          'ends_at': '2030-06-05T01:30:00.000Z',
          'reason': 'This space is no longer available. Choose another slot.',
          'holder_count': 1,
          'holders': [
            {
              'source': 'b1',
              'kind': 'admission',
              'booking_id': 'b1',
              'admission_id': 'a1',
              'reference': 'AD-RAHUL',
              'name': 'Rahul',
              'plan_name': 'Morning swim',
              'weekdays': [1, 3, 5],
              'expires_on': '2030-06-30',
              'starts_at': '2030-06-05T00:30:00.000Z',
              'ends_at': '2030-06-05T01:30:00.000Z',
              'local_start': '2030-06-05T06:00',
              'local_end': '2030-06-05T07:00',
            },
          ],
        },
      ],
    },
    {
      'time': '07:00',
      'end_time': '08:00',
      'session_count': 2,
      'capacity': 1,
      'status': 'available',
      'remaining_capacity': 1,
      'clash_count': 0,
      'clashes': [],
    },
    {
      'time': '08:00',
      'end_time': '09:00',
      'session_count': 2,
      'capacity': 10,
      'status': 'available',
      'remaining_capacity': 7,
      'clash_count': 0,
      'clashes': [],
    },
  ],
};

class ChartFake extends AdmissionsFake {
  final requests = <SlotChartRequest>[];
  bool fail = false;
  @override
  Future<AdmissionSlotChart> slotChart(SlotChartRequest request) async {
    requests.add(request);
    if (fail) throw const AppException('Offline', code: 'NETWORK');
    return AdmissionSlotChart.fromJson(chartJson);
  }
}

const request = SlotChartRequest(
  businessId: 'business',
  poolId: 'pool',
  planId: 'plan',
  start: '2030-06-04',
  weekdays: [3, 5],
  duration: 60,
);

void main() {
  test('slot chart and holders parse from the API', () {
    final chart = AdmissionSlotChart.fromJson(chartJson);
    expect(chart.dates, ['2030-06-05', '2030-06-07']);
    expect(chart.times.length, 3);
    final taken = chart.at('06:00')!;
    expect(taken.taken, isTrue);
    expect(taken.clashCount, 1);
    final holder = taken.clashes.single.holders.single;
    expect(holder.title, 'Rahul');
    expect(
      holder.details,
      'Morning swim · Mon/Wed/Fri · till 2030-06-30 · AD-RAHUL',
    );
    expect(holder.time, '06:00–07:00');
    expect(chart.at('08:00')!.remaining, 7);
    expect(weekdayNames([7, 1, 2, 3, 4, 5, 6]), 'Daily');
    expect(
      const SlotHolder(
        kind: 'booking',
        reference: 'BK-1',
        localStart: '2030-06-05T17:00',
        localEnd: '2030-06-05T18:00',
      ).details,
      'Booking · 17:00–18:00 · BK-1',
    );
    expect(const SlotHolder(kind: 'block').title, 'Blocked slot');
  });

  test(
    'chart cubit loads once per request, refreshes and keeps errors',
    () async {
      final r = ChartFake();
      final c = AdmissionSlotChartCubit(r, delay: Duration.zero);
      c.load(null);
      expect(c.state.request, isNull);
      c.load(request);
      expect(c.state.loading, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(c.state.chart?.times.length, 3);
      expect(c.state.loading, isFalse);
      c.load(request);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(r.requests.length, 1);
      r.fail = true;
      await c.refresh();
      expect(r.requests.length, 2);
      expect(c.state.error, 'Offline');
      expect(c.state.chart, isNull);
      c.load(null);
      expect(c.state, const AdmissionSlotChartState());
      await c.close();
    },
  );

  testWidgets(
    'fixed schedule shows free times, selects one and names who holds a taken time',
    (tester) async {
      final w = await workspace(), r = ChartFake(), c = AdmissionCubit(w, r);
      await c.loadForm();
      c.update(
        c.state.draft.copyWith(
          planId: 'plan',
          mode: 'fixed',
          weekdays: [3, 5],
          time: '06:00',
        ),
      );
      expect(slotChartRequest(c.state), isNotNull);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            theme: AppTheme.build(Brightness.light),
            home: Scaffold(
              body: SingleChildScrollView(
                child: BlocBuilder<AdmissionCubit, AdmissionState>(
                  bloc: c,
                  builder: (context, s) =>
                      AdmissionScheduleFields(cubit: c, state: s),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(r.requests.single.weekdays, [3, 5]);
      expect(find.text('Choose start & end · Wed/Fri'), findsOneWidget);
      expect(find.text('Booked · 1 of 2 dates'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('7 of 10 left'), findsOneWidget);
      expect(
        find.textContaining('06:00–07:00 is booked on 1 of 2 dates'),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('booking-time-07:00')),
      );
      await tester.tap(find.byKey(const ValueKey('booking-time-07:00')));
      await tester.pumpAndSettle();
      expect(c.state.draft.time, '07:00');
      // Like booking: the start waits for an end; 08:00 ends a 1 h visit.
      expect(find.text('Start · tap to clear'), findsOneWidget);
      expect(find.text('1 h'), findsOneWidget);
      expect(find.text('Not a valid end'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('booking-time-08:00')));
      await tester.pumpAndSettle();
      expect(c.state.draft.duration, 60);
      expect(find.text('End · tap to clear'), findsOneWidget);
      expect(find.textContaining('is booked on'), findsNothing);
      // Tapping the start clears it, so any free start can be chosen.
      await tester.tap(find.byKey(const ValueKey('booking-time-07:00')));
      await tester.pumpAndSettle();
      expect(find.text('Start · tap to clear'), findsNothing);

      await tester.ensureVisible(
        find.byKey(const ValueKey('booking-time-06:00')),
      );
      await tester.tap(find.byKey(const ValueKey('booking-time-06:00')));
      await tester.pumpAndSettle();
      expect(find.text('06:00–07:00 is taken'), findsOneWidget);
      expect(find.text('Wed, 5 Jun 2030 at 6:00 AM'), findsOneWidget);
      expect(find.text('Rahul'), findsOneWidget);
      expect(
        find.text('Morning swim · Mon/Wed/Fri · till 2030-06-30 · AD-RAHUL'),
        findsOneWidget,
      );
      // Taken times never become the selected start.
      expect(c.state.draft.time, '07:00');

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await c.close();
        await w.close();
      });
    },
  );

  test('subscription start then end offers each hour option that is free', () {
    SlotChartTime at(String time, {bool taken = false}) => SlotChartTime(
      time: time,
      endTime: time,
      status: taken ? 'taken' : 'available',
      sessionCount: 8,
      clashCount: taken ? 2 : 0,
    );
    final chart = AdmissionSlotChart(
      expiresOn: '2030-07-01',
      times: [
        at('17:00'),
        at('18:00'),
        at('19:00', taken: true),
        at('20:00'),
        at('21:00'),
      ],
    );
    Map<String, String?> labels(PlanPick pick, {int duration = 60}) => {
      for (final c in planCells(
        chart,
        start: '17:00',
        duration: duration,
        durations: const [60, 120, 180],
        step: 60,
        pick: pick,
      ))
        c.time: c.cell.label,
    };
    expect(labels(PlanPick.end), {
      '17:00': 'Start · tap to clear',
      '18:00': '1 h',
      '19:00': '2 h',
      '20:00': 'Booked',
      '21:00': 'Not a valid end',
    });
    expect(labels(PlanPick.done, duration: 120), {
      '17:00': 'Start · tap to clear',
      '18:00': 'Selected range',
      '19:00': 'End · tap to clear',
      '20:00': 'Available',
      '21:00': 'Available',
    });
    expect(rangeClash(chart, '17:00', 120, 60), isNull);
    expect(rangeClash(chart, '18:00', 120, 60), (2, 8));
  });

  testWidgets('booked booking slots open who holds them; free slots select', (
    tester,
  ) async {
    BookingSlot? held, chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingTimeGrid(
            slots: const [
              BookingSlot('17:00', false, 0, null, false, 60, 'booked'),
              BookingSlot('18:00', true, 1000, null, false, 60, 'available'),
              BookingSlot('06:00', false, 0, null, true, 60, 'past'),
            ],
            onSelected: (s) => chosen = s,
            onUnavailable: (s) => held = s,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('booking-time-17:00')));
    expect(held?.time, '17:00');
    expect(chosen, isNull);
    expect(find.byIcon(Icons.person_search_outlined), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('booking-time-06:00')));
    expect(held?.time, '17:00');
    await tester.tap(find.byKey(const ValueKey('booking-time-18:00')));
    expect(chosen?.time, '18:00');
  });
}
