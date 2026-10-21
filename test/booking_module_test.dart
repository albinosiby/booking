import 'package:eden_booking/modules/bookings/models/booking_discount.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_widgets.dart'
    show bookingLocal;
import 'dart:async';
import 'package:eden_booking/modules/bookings/widgets/booking_form_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/models/booking_detail_model.dart';
import 'package:eden_booking/modules/bookings/models/booking_list_model.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_form_cubit.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_detail_cubit.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_list_cubit.dart';
import 'package:eden_booking/modules/bookings/screens/booking_form_screen.dart';
import 'package:eden_booking/modules/bookings/screens/booking_detail_screen.dart';
import 'package:eden_booking/modules/bookings/repositories/booking_repository.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';

class BookingSource extends Fake implements WorkspaceRepository {
  Workspace value = const Workspace(
    organization: Organization(
      id: 'org',
      name: 'Eden',
      phone: '9876543210',
      currency: 'INR',
    ),
    membership: {'role': 'owner'},
    businesses: [
      Business(
        id: 'business',
        name: 'Badminton',
        type: BusinessType.badminton,
        status: 'ready',
        locationId: 'location',
        version: 1,
        resources: [Resource(id: 'space', name: 'Court 1', capacity: 1)],
      ),
    ],
  );
  @override
  Future<Workspace> load() async => value;
}

class FakeBookingRepository implements BookingRepository {
  FakeBookingRepository({this.flexible = false});
  final bool flexible;
  bool noBookableBusinesses = false;
  BookingCatalog? catalogOverride;
  @override
  Future<Map<String, int>> dateCounts({
    required String date,
    required String dateUntil,
    String? businessId,
    String? spaceId,
    String? query,
    String? status,
  }) async => {};
  final events = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => events.stream;
  final records = <String, Map<String, dynamic>>{},
      commands = <String, String>{};
  final submitted = <BookingCommand>[];
  bool loseResponse = false, lookupFails = false;
  Completer<BookingQuote>? delayedQuote;
  Completer<List<BookingSlot>>? delayedSlots;
  Completer<List<BookingSlot>>? delayedEnds;
  bool availabilityFails = false;
  bool preloadEnds = false;
  int availabilityCalls = 0;
  int quoteCalls = 0;
  @override
  Future<BookingCatalog> catalog() async =>
      catalogOverride ??
      (noBookableBusinesses
          ? BookingCatalog(canView: true, canManage: true)
          : BookingCatalog(
              canView: true,
              canManage: true,
              canCollect: true,
              canRefund: true,
              canFinance: true,
              businesses: [
                BookingBusiness(
                  id: 'business',
                  name: 'Badminton',
                  type: 'badminton',
                  timezone: 'Asia/Kolkata',
                  today: '2030-06-04',
                  spaces: [
                    BookingSpace(
                      id: 'space',
                      name: 'Court 1',
                      capacity: 1,
                      options: [
                        BookingOption(
                          id: 'hourly',
                          name: 'Court booking',
                          kind: 'hourly',
                          durations: [60],
                          defaultDuration: 60,
                          minimumDuration: flexible ? 60 : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ));
  BookingQuote makeQuote(BookingSelection s) => BookingQuote(
    token: 'token-${s.time}',
    total: s.time == '19:00' ? 60000 : 50000,
    start: '${s.date}T${s.time}:00Z',
    end: '${s.date}T10:00:00Z',
    localStart: '${s.date}T${s.time}',
    localEnd: '${s.date}T10:00',
    timezone: 'Asia/Kolkata',
    businessName: 'Badminton',
    spaceName: 'Court 1',
    optionName: 'Court booking',
  );
  @override
  Future<BookingQuote> quote(BookingSelection s, {String? excludeId}) async {
    quoteCalls++;
    return delayedQuote == null ? makeQuote(s) : await delayedQuote!.future;
  }

  @override
  Future<List<BookingSlot>> availability(
    BookingSelection s, {
    String? excludeId,
    bool endTimes = false,
  }) async {
    availabilityCalls++;
    if (availabilityFails) throw const AppException('Offline', code: 'NETWORK');
    if (endTimes) {
      if (delayedEnds != null) return delayedEnds!.future;
      return [
        BookingSlot('09:30', false, 0, null, false, 30, 'minimum'),
        BookingSlot('10:00', true, 50000, null, false, 60),
        BookingSlot('10:15', true, 62500, null, false, 75),
        BookingSlot('10:45', true, 87500, null, false, 105),
        BookingSlot('11:00', true, 100000, null, false, 120),
        BookingSlot('12:00', false, 150000, null, false, 180, 'booked'),
      ];
    }
    if (delayedSlots != null) return delayedSlots!.future;
    if (preloadEnds) {
      return [
        BookingSlot('09:00', true, 50000, null, false, null, null, null, const [
          BookingSlot(
            '10:00',
            true,
            0,
            null,
            false,
            60,
            'available',
            '2030-06-04',
          ),
          BookingSlot(
            '10:15',
            true,
            0,
            null,
            false,
            75,
            'available',
            '2030-06-04',
          ),
        ]),
        const BookingSlot('10:00', false, 50000),
        const BookingSlot('10:15', true, 50000),
      ];
    }
    return const [
      BookingSlot('09:00', true, 50000),
      BookingSlot('10:00', false, 50000),
    ];
  }

  @override
  Future<List<BookingCustomer>> customers(String p) async => [
    const BookingCustomer(
      id: 'customer',
      name: 'Existing customer',
      phone: '9876543210',
    ),
  ];
  Map<String, dynamic> row(String id, BookingSelection s, BookingCustomer c) =>
      {
        'id': id,
        'reference': 'BK-TEST',
        'status': 'confirmed',
        'version': 1,
        'selection': s.toJson(),
        'customer_id': c.id ?? 'customer',
        'customer_snapshot': c.toJson(),
        'notes': '',
        'total_minor': makeQuote(s).total,
        'starts_at': '${s.date}T${s.time}:00Z',
        'ends_at': '${s.date}T10:00:00Z',
        'local_start': '${s.date}T${s.time}',
        'local_end': '${s.date}T10:00',
        'price_snapshot': {
          'timezone': 'Asia/Kolkata',
          'business_name': 'Badminton',
          'space_name': 'Court 1',
          'option_name': 'Court booking',
        },
        'payments': <Map<String, dynamic>>[],
        'history': <Map<String, dynamic>>[],
      };
  @override
  Future<String> submit(BookingCommand c) async {
    submitted.add(c);
    if (commands.containsKey(c.key)) return commands[c.key]!;
    final data = c.body;
    String id;
    if (c.endpoint == '/bookings') {
      id = 'booking-${records.length}';
      final s = BookingSelection.fromJson(
        Map<String, dynamic>.from(data['selection']),
      );
      records[id] = row(
        id,
        s,
        BookingCustomer.fromJson(Map<String, dynamic>.from(data['customer'])),
      );
      records[id]!['notes'] = data['notes'];
      for (final p in data['payments']) {
        _payment(records[id]!, Map<String, dynamic>.from(p), 'collection');
      }
    } else {
      id = c.endpoint.split('/')[2];
      final r = records[id]!;
      if (data['version'] != r['version']) {
        throw const AppException('Version conflict.', code: 'CONFLICT');
      }
      if (c.endpoint.endsWith('/reschedule')) {
        final s = BookingSelection.fromJson(
          Map<String, dynamic>.from(data['selection']),
        );
        r['selection'] = s.toJson();
        r['total_minor'] = makeQuote(s).total;
        r['local_start'] = '${s.date}T${s.time}';
        r['starts_at'] = '${s.date}T${s.time}:00Z';
      } else if (c.endpoint.endsWith('/payments')) {
        for (final p in data['payments']) {
          _payment(r, Map<String, dynamic>.from(p), data['kind']);
        }
      } else if (c.endpoint.endsWith('/status')) {
        if (data['status'] == 'checked_in') {
          (r['history'] as List).add({
            'action': 'checked_in',
            'actor_name': 'Owner',
            'local_created': '2030-06-04T09:00',
            'details': {'reason': data['reason']},
          });
        } else {
          r['status'] = data['status'];
        }
      } else {
        r['customer_snapshot'] = data['customer'];
        r['notes'] = data['notes'];
      }
      r['version']++;
    }
    commands[c.key] = id;
    if (loseResponse) {
      loseResponse = false;
      throw const AppException('Connection lost.', code: 'NETWORK');
    }
    return id;
  }

  void _payment(Map<String, dynamic> r, Map<String, dynamic> p, String kind) {
    (r['payments'] as List).add({
      ...p,
      'id': 'payment-${r['payments'].length}',
      'kind': kind,
      'collector_name': 'Owner',
      'reason': '',
    });
  }

  @override
  Future<String?> commandResult(String key) async {
    if (lookupFails) throw const AppException('Offline', code: 'NETWORK');
    return commands[key];
  }

  @override
  Future<BookingRecord> detail(String id) async {
    final r = records[id]!,
        net = (r['payments'] as List).fold<int>(
          0,
          (n, p) =>
              n +
              (p['kind'] == 'collection'
                  ? p['amount_minor'] as int
                  : -(p['amount_minor'] as int)),
        );
    final total = r['status'] == 'cancelled' ? 0 : r['total_minor'] as int;
    return BookingRecord.fromJson({
      ...r,
      'net_paid_minor': net,
      'balance_minor': (total - net).clamp(0, 1000000000),
      'refund_due_minor': (net - total).clamp(0, 1000000000),
      'payment_status': net > total
          ? 'refund_due'
          : net == total
          ? 'paid'
          : net == 0
          ? 'unpaid'
          : 'partial',
    });
  }

  @override
  Future<BookingPageResult> list({
    String? date,
    String? dateUntil,
    bool overlap = false,
    String? spaceId,
    String? businessId,
    String? query,
    String? status,
    int cursor = 0,
  }) async =>
      BookingPageResult(await Future.wait(records.keys.map(detail)), null);
  @override
  Future<CollectionPage> collections({
    String? date,
    String? businessId,
    int cursor = 0,
  }) async => const CollectionPage([], null, []);
  @override
  Future<OutstandingPage> outstanding({
    String? date,
    String? businessId,
    int cursor = 0,
  }) async => const OutstandingPage([], null, 0, 0);
  @override
  Future<BookingDashboard> dashboard({String? businessId}) async =>
      const BookingDashboard(
        today: 0,
        upcomingCount: 0,
        value: 0,
        collected: 0,
        refunded: 0,
        outstanding: 0,
        upcoming: [],
      );
}

Future<(WorkspaceCubit, FakeBookingRepository, BookingFormCubit)> form({
  bool flexible = false,
}) async {
  final w = WorkspaceCubit(BookingSource());
  await w.load();
  final r = FakeBookingRepository(flexible: flexible),
      c = BookingFormCubit(w, r, const BookingLaunch(date: '2030-06-04'));
  await c.load();
  return (w, r, c);
}

void customer(BookingFormCubit c) {
  c.customerName('Customer One');
  c.customerPhone('9876543210');
}

void split(BookingFormCubit c) {
  for (final v in [('cash', '100'), ('upi', '200'), ('card', '200')]) {
    c.addPayment();
    c.updatePayment(
      c.state.draft.payments.last.id,
      (p) => p.copyWith(method: v.$1, amount: v.$2),
    );
  }
}

class GatedBookingDetailRepository extends FakeBookingRepository {
  final catalogGate = Completer<BookingCatalog>();
  final detailGate = Completer<BookingRecord>();
  bool catalogStarted = false, detailStarted = false;
  @override
  Future<BookingCatalog> catalog() {
    catalogStarted = true;
    return catalogGate.future;
  }

  @override
  Future<BookingRecord> detail(String id) {
    detailStarted = true;
    return detailGate.future;
  }
}

void main() {
  test(
    'history Collect is hidden and blocked for paid, cancelled or unauthorized bookings',
    () async {
      final (w, r, c) = await form();
      customer(c);
      await c.review();
      await c.confirm();
      final id = c.state.resultId!;
      await c.close();
      final d = BookingDetailCubit(w, r, id);
      await d.load();
      expect(d.state.canCollectPending, isTrue);
      r.records[id]!['status'] = 'cancelled';
      await d.load();
      expect(d.state.canCollectPending, isFalse);
      d.begin(BookingDetailAction.collection);
      expect(d.state.action, BookingDetailAction.none);
      r.records[id]!['status'] = 'confirmed';
      r._payment(r.records[id]!, {
        'method': 'cash',
        'amount_minor': 10000,
        'reference': '',
        'received_at': '2030-06-04T10:00:00Z',
      }, 'collection');
      r._payment(r.records[id]!, {
        'method': 'upi',
        'amount_minor': 40000,
        'reference': '',
        'received_at': '2030-06-04T11:00:00Z',
      }, 'collection');
      r.records[id]!['history'] = [
        {
          'action': 'created',
          'actor_name': 'Owner',
          'created_at': '2030-06-04T09:00:00Z',
          'details': <String, dynamic>{},
        },
        {
          'action': 'payment_recorded',
          'actor_name': 'Staff',
          'created_at': '2030-06-04T11:00:00Z',
          'details': <String, dynamic>{},
        },
      ];
      await d.load();
      expect(d.state.paymentHistory.first.method, 'upi');
      expect(d.state.bookingHistory.first.action, 'payment_recorded');
      expect(() => d.state.paymentHistory.clear(), throwsUnsupportedError);
      expect(d.state.canCollectPending, isFalse);
      d.begin(BookingDetailAction.collection);
      expect(d.state.action, BookingDetailAction.none);
      r.catalogOverride = const BookingCatalog(
        canManage: true,
        canView: true,
        canCollect: false,
      );
      await d.load();
      expect(d.state.canCollectPending, isFalse);
      await d.close();
      await w.close();
    },
  );
  test(
    'shared payment editor uses the refundable balance and requires payment and reason',
    () async {
      final (w, r, c) = await form();
      customer(c);
      c.addPayment();
      c.updatePayment(
        c.state.draft.payments.single.id,
        (p) => p.copyWith(amount: '100'),
      );
      await c.review();
      await c.confirm();
      final id = c.state.resultId!;
      await c.close();
      r.records[id]!['status'] = 'cancelled';
      final d = BookingDetailCubit(w, r, id);
      await d.load();
      d.begin(BookingDetailAction.refund);
      expect(d.state.paymentEntry.remaining, 10000);
      expect(d.state.payments.single.isBlank, isTrue);
      final commands = r.submitted.length;
      await d.submit();
      expect(r.submitted.length, commands);
      d.payBalance(d.state.payments.single.id);
      expect(d.state.payments.single.amount, '100.00');
      await d.submit();
      expect(d.state.error, contains('reason'));
      d.reason('Cancelled booking');
      await d.submit();
      expect(d.state.record!.refundDue, 0);
      expect(r.submitted.last.body['kind'], 'refund');
      await d.close();
      await w.close();
    },
  );
  test(
    'payment shortcuts stay local, balance split entries and omit empty rows',
    () async {
      final (w, r, c) = await form();
      customer(c);
      await c.slots();
      await c.checkQuote();
      final quoteCalls = r.quoteCalls, slotsCalls = r.availabilityCalls;
      expect(c.state.draft.payments, isEmpty);
      final initial = c.state.draft.editablePayments.single;
      expect(initial.method, 'cash');
      expect(initial.amount, '');
      c.payBalance(initial.id);
      expect(c.state.draft.received, 50000);
      c.updatePayment(initial.id, (p) => p.copyWith(amount: '100'));
      c.addPayment('upi');
      final second = c.state.draft.payments.last;
      expect(second.amount, '400.00');
      expect(c.state.remainingPayment, 0);
      c.updatePayment(second.id, (p) => p.copyWith(amount: '401'));
      expect(
        c.state.paymentError(c.state.draft.payments.last),
        contains('remaining'),
      );
      c.payBalance(second.id);
      expect(c.state.draft.received, 50000);
      c.removePayment(second.id);
      c.removePayment(initial.id);
      c.updatePayment(
        c.state.draft.editablePayments.single.id,
        (p) => p.copyWith(method: 'upi'),
      );
      expect(c.state.draft.recordedPayments, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(r.quoteCalls, quoteCalls);
      expect(r.availabilityCalls, slotsCalls);
      await c.review();
      expect(c.state.review, isTrue);
      await c.confirm();
      expect(r.records.values.single['payments'], isEmpty);
      await c.close();
      await w.close();
    },
  );
  test(
    'discount previews update immediately and invalid discounts cannot be reviewed',
    () async {
      final (w, r, c) = await form(flexible: true);
      r.preloadEnds = true;
      await c.slots();
      customer(c);
      c.chooseSlot(c.state.slots.first);
      c.chooseSlot(c.state.endSlots.first);
      c.discount(
        const BookingDiscount(type: 'percent', value: '10', reason: 'Member'),
      );
      expect(c.state.estimatedTotal, 45000);
      expect(c.state.draft.selection!.toJson()['discount'], {
        'type': 'percent',
        'value': 1000,
        'reason': 'Member',
      });
      c.discount(const BookingDiscount(value: '501'));
      await c.review();
      expect(c.state.review, isFalse);
      expect(c.state.error, contains('subtotal'));
      c.discount(null);
      expect(c.state.estimatedTotal, 50000);
      c.addPayment('upi');
      expect(c.state.draft.payments.single.method, 'upi');
      expect(
        const BookingDiscount(type: 'percent', value: '100.01').validate(50000),
        isNotNull,
      );
      expect(const BookingDiscount(value: '-1').validate(50000), isNotNull);
      expect(
        const BookingDiscount(value: '999999999999999999999').units,
        isNull,
      );
      await c.close();
      await w.close();
    },
  );
  test(
    'review opens while quote is pending but cannot submit until verified',
    () async {
      final (w, r, c) = await form(flexible: true);
      r.preloadEnds = true;
      r.delayedQuote = Completer<BookingQuote>();
      await c.slots();
      customer(c);
      c.chooseSlot(c.state.slots.first);
      c.chooseSlot(c.state.endSlots.last);
      await c.review();
      expect(c.state.review, isTrue);
      expect(c.state.checking, isTrue);
      expect(c.state.quote, isNull);
      await c.confirm();
      expect(r.submitted, isEmpty);
      r.delayedQuote!.complete(r.makeQuote(c.state.draft.selection!));
      await Future<void>.delayed(Duration.zero);
      expect(c.state.review, isTrue);
      expect(c.state.quote, isNotNull);
      await c.close();
      await w.close();
    },
  );
  test(
    'preloaded ends enable immediately without another availability request',
    () async {
      final (w, r, c) = await form(flexible: true);
      r.preloadEnds = true;
      await c.slots();
      final requests = r.availabilityCalls;
      c.chooseSlot(c.state.slots.first);
      expect(c.state.slotsLoading, isFalse);
      expect(c.state.endSlots.length, 2);
      expect(
        c.state.timeCells
            .firstWhere((cell) => cell.slot.time == '10:15')
            .enabled,
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      expect(r.availabilityCalls, requests);
      c.chooseSlot(c.state.endSlots.last);
      expect(c.state.rangeComplete, isTrue);
      // Visible synchronously, before the quote request gets an event-loop turn.
      expect(c.state.quote, isNull);
      expect(c.state.estimatedTotal, 62500);
      expect(c.state.displayedTotal, 62500);
      c.clearEnd();
      expect(c.state.estimatedTotal, isNull);
      c.chooseStartAgain();
      c.chooseSlot(c.state.slots.first);
      expect(r.availabilityCalls, requests);
      expect(c.state.slotsLoading, isFalse);
      await c.close();
      await w.close();
    },
  );

  test('preloaded endpoint tuples map into immutable domain slots', () {
    final slot = BookingSlot.fromJson({
      'time': '23:00',
      'available': true,
      'total_minor': 50000,
      'end_options': [
        [60, '2030-06-05T00:00'],
        [75, '2030-06-05T00:15'],
      ],
    });
    expect(slot.endOptions!.last.time, '00:15');
    expect(slot.endOptions!.last.date, '2030-06-05');
    expect(slot.endOptions!.last.duration, 75);
    expect(() => slot.endOptions!.clear(), throwsUnsupportedError);
  });

  test('quarter-hour ends can be selected from the persistent grid', () async {
    final (w, r, c) = await form(flexible: true);
    await c.slots();
    c.chooseSlot(c.state.slots.first);
    await Future<void>.delayed(Duration.zero);
    final cell = c.state.timeCells.firstWhere(
      (cell) => cell.slot.time == '10:15',
    );
    expect(cell.enabled, isTrue);
    c.chooseSlot(cell.slot);
    expect(c.state.rangeComplete, isTrue);
    expect(c.state.draft.duration, 75);
    expect(c.state.draft.endTime, '10:15');
    await c.close();
    await w.close();
  });

  test(
    'one grid keeps starts, highlights the range and toggles selected boundaries',
    () async {
      final (w, r, c) = await form(flexible: true);
      await c.slots();
      final base = c.state.slots;
      c.chooseSlot(base.first);
      await Future<void>.delayed(Duration.zero);
      expect(c.state.slots, base);
      expect(
        c.state.timeCells.where((cell) => cell.start).single.slot.time,
        '09:00',
      );
      final end = c.state.endSlots.firstWhere((s) => s.duration == 60);
      // 10:00 is blocked as a start, but valid as the preceding booking's end.
      expect(base.firstWhere((s) => s.time == '10:00').available, isFalse);
      expect(
        c.state.timeCells
            .firstWhere((cell) => cell.slot.time == '10:00')
            .enabled,
        isTrue,
      );
      c.chooseSlot(end);
      expect(c.state.rangeComplete, isTrue);
      expect(c.state.timeCells.any((cell) => cell.inRange), isTrue);
      c.chooseSlot(end);
      expect(c.state.rangeComplete, isFalse);
      expect(c.state.choosingEnd, isTrue);
      expect(c.state.quote, isNull);
      final start = c.state.timeCells.singleWhere((cell) => cell.start).slot;
      c.chooseSlot(start);
      expect(c.state.choosingEnd, isFalse);
      expect(c.state.endSlots, isEmpty);
      expect(c.state.slots, base);
      await c.close();
      await w.close();
    },
  );

  test(
    'clearing the start while end validation is pending ignores the late response',
    () async {
      final (w, r, c) = await form(flexible: true);
      await c.slots();
      final base = c.state.slots;
      r.delayedEnds = Completer<List<BookingSlot>>();
      c.chooseSlot(base.first);
      c.chooseSlot(c.state.timeCells.singleWhere((cell) => cell.start).slot);
      r.delayedEnds!.complete([
        const BookingSlot('10:00', true, 50000, null, false, 60),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(c.state.choosingEnd, isFalse);
      expect(c.state.endSlots, isEmpty);
      expect(c.state.slots, base);
      await c.close();
      await w.close();
    },
  );

  test(
    'midnight end is a separate next-day boundary in the same grid',
    () async {
      final (w, r, c) = await form(flexible: true);
      final model = c.state.copyWith(
        draft: c.state.draft.copyWith(time: '23:00'),
        choosingEnd: true,
        slots: [
          const BookingSlot('00:00', true, 50000),
          const BookingSlot('23:00', true, 50000),
        ],
        endSlots: [
          const BookingSlot(
            '00:00',
            true,
            50000,
            null,
            false,
            60,
            'available',
            '2030-06-05',
          ),
        ],
      );
      final midnight = model.timeCells
          .where((cell) => cell.slot.time == '00:00')
          .toList();
      expect(midnight.length, 2);
      expect(midnight.map((cell) => cell.date).toSet(), {
        '2030-06-04',
        '2030-06-05',
      });
      expect(midnight.last.enabled, isTrue);
      await c.close();
      await w.close();
    },
  );

  test(
    'slot selections run on the next event and identical taps keep the grid',
    () async {
      final (w, r, c) = await form(flexible: true);
      await c.slots();
      final calls = r.availabilityCalls;
      final loaded = c.state.slots;
      c.date(c.state.draft.date);
      c.chooseBusiness(c.state.draft.businessId!);
      c.chooseSpace(c.state.draft.spaceId!);
      c.chooseOption(c.state.draft.optionId!);
      await Future<void>.delayed(Duration.zero);
      expect(r.availabilityCalls, calls);
      expect(c.state.slots, loaded);
      c.date('2030-06-05');
      c.date('2030-06-06');
      await Future<void>.delayed(Duration.zero);
      expect(r.availabilityCalls, calls + 1);
      expect(c.state.draft.date, '2030-06-06');
      expect(c.state.slotsLoaded, isTrue);
      await c.close();
      await w.close();
    },
  );

  test(
    'booking detail starts independent reads together without serial latency',
    () async {
      final (w, source, formCubit) = await form();
      const selection = BookingSelection(
        businessId: 'business',
        resourceId: 'space',
        optionId: 'court',
        date: '2030-06-04',
        time: '09:00',
        duration: 60,
        people: 1,
      );
      source.records['booking'] = source.row(
        'booking',
        selection,
        const BookingCustomer(name: 'Customer', phone: '9876543210'),
      );
      final catalog = await source.catalog();
      final record = await source.detail('booking');
      final repository = GatedBookingDetailRepository();
      final detail = BookingDetailCubit(w, repository, 'booking');
      final pending = detail.load();
      expect(repository.catalogStarted, isTrue);
      expect(repository.detailStarted, isTrue);
      repository.catalogGate.complete(catalog);
      repository.detailGate.complete(record);
      await pending;
      expect(detail.state.record, record);
      expect(detail.state.loading, isFalse);
      await detail.close();
      await repository.events.close();
      await formCubit.close();
      await w.close();
    },
  );

  test(
    'Time grid requires a finish and never reviews a short interval',
    () async {
      final (w, r, c) = await form(flexible: true);
      await c.slots();
      c.chooseSlot(c.state.slots.first);
      await Future<void>.delayed(Duration.zero);
      expect(c.state.choosingEnd, isTrue);
      expect(c.state.rangeComplete, isFalse);
      expect(c.state.quote, isNull);
      await c.review();
      expect(c.state.review, isFalse);
      final short = c.state.endSlots.firstWhere((s) => s.duration == 30);
      c.chooseSlot(short);
      expect(c.state.rangeComplete, isFalse);
      c.chooseSlot(c.state.endSlots.firstWhere((s) => s.duration == 120));
      await c.checkQuote();
      expect(c.state.draft.duration, 120);
      expect(c.state.rangeComplete, isTrue);
      c.chooseStartAgain();
      expect(c.state.rangeComplete, isFalse);
      expect(c.state.draft.duration, 60);
      await c.close();
      await w.close();
    },
  );
  test(
    'Start and end selection supports longer bookings and rejects short or off-step lengths',
    () async {
      final (w, r, c) = await form(flexible: true);
      c.time('06:00');
      c.endTime('09:00');
      expect(c.state.draft.duration, 180);
      expect(c.state.draft.endTime, '09:00');
      c.endTime('09:30');
      expect(c.state.draft.duration, 210);
      c.endTime('06:30');
      expect(c.state.error, contains('at least 60'));
      expect(c.state.draft.duration, 210);
      c.endTime('07:15');
      expect(c.state.draft.duration, 75);
      expect(c.state.error, isNull);
      c.endTime('07:45');
      expect(c.state.draft.duration, 105);
      c.endTime('07:05');
      expect(c.state.error, contains('15-minute'));
      c.time('23:00');
      c.endTime('24:00');
      expect(c.state.draft.duration, 60);
      expect(c.state.draft.endTime, '00:00');
      expect(c.state.draft.endsNextDay, isTrue);
      c.endTime('01:30');
      expect(c.state.draft.duration, 150);
      await c.close();
      await w.close();
    },
  );
  test('booking date/time labels retain the midnight UI alias', () {
    expect(bookingLocal('2030-06-05T00:00'), '2030-06-05 24:00');
    expect(bookingLocal('2030-06-05T12:00'), '2030-06-05 12:00');
  });
  setUpAll(() async {
    if (!const bool.fromEnvironment('BOOKING_PREVIEWS')) return;
    final fontDir = Platform.environment['REVIEW_FONT_DIR']!;
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File('$fontDir/${entry.value}').readAsBytes();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  tearDown(() => getIt.reset());
  test(
    'availability survives customer and time edits but discards changed dates',
    () async {
      final (w, r, c) = await form();
      r.delayedSlots = Completer<List<BookingSlot>>();
      final first = c.slots();
      c.customerName('New customer');
      c.time('19:00');
      r.delayedSlots!.complete(const [BookingSlot('19:00', true, 60000)]);
      await first;
      expect(c.state.slots.single.time, '19:00');
      expect(c.state.draft.customer.name, 'New customer');
      r.delayedSlots = Completer<List<BookingSlot>>();
      final stale = c.slots();
      c.date('2030-06-05');
      r.delayedSlots!.complete(const [BookingSlot('08:00', true, 50000)]);
      await stale;
      expect(c.state.slots, isEmpty);
      expect(c.state.slotsLoading, isFalse);
      await c.close();
      await w.close();
    },
  );
  test(
    'availability failure can retry; blocked and past starts cannot be selected',
    () async {
      final (w, r, c) = await form();
      r.availabilityFails = true;
      await c.slots();
      expect(c.state.slotsError, 'Offline');
      expect(c.state.error, isNull);
      r.availabilityFails = false;
      await c.slots();
      expect(c.state.slotsError, isNull);
      expect(c.state.slotsLoaded, isTrue);
      c.chooseSlot(c.state.slots.last);
      expect(c.state.draft.time, '09:00');
      c.chooseSlot(const BookingSlot('07:00', false, 50000, null, true));
      expect(c.state.draft.time, '09:00');
      await c.close();
      await w.close();
    },
  );
  testWidgets('time grid distinguishes past and booked with disabled actions', (
    tester,
  ) async {
    final chosen = <BookingSlot>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingTimeGrid(
            slots: const [
              BookingSlot('07:00', false, 50000, null, true),
              BookingSlot('08:00', false, 50000),
              BookingSlot('09:00', true, 50000),
            ],
            onSelected: chosen.add,
          ),
        ),
      ),
    );
    for (final time in ['07:00', '08:00', '09:00']) {
      await tester.tap(find.byKey(ValueKey('booking-time-$time')));
    }
    expect(find.text('Past'), findsOneWidget);
    expect(find.text('Booked'), findsOneWidget);
    expect(chosen.single.time, '09:00');
    expect(tester.takeException(), isNull);
  });
  test(
    'split payments are individual entries and full payment is confirmed with one booking command',
    () async {
      final (w, r, c) = await form();
      customer(c);
      split(c);
      await c.review();
      expect(c.state.review, isTrue);
      expect(c.state.draft.received, 50000);
      expect(c.state.balance, 0);
      await c.confirm();
      final b = await r.detail(c.state.resultId!);
      expect(b.netPaid, 50000);
      expect(b.payments.map((p) => p.method), ['cash', 'upi', 'card']);
      expect(r.submitted.length, 1);
      await c.close();
      await w.close();
    },
  );
  test(
    'uncertain confirmation retains its exact key and locks edits until recovered',
    () async {
      final (w, r, c) = await form();
      customer(c);
      await c.review();
      r.loseResponse = true;
      r.lookupFails = true;
      await c.confirm();
      expect(c.state.pending, isNotNull);
      final key = c.state.pending!.key;
      c.time('19:00');
      expect(c.state.draft.time, '09:00');
      r.lookupFails = false;
      await c.confirm();
      expect(c.state.resultId, isNotNull);
      expect(r.records.length, 1);
      expect(r.submitted.map((c) => c.key).toSet(), {key});
      await c.close();
      await w.close();
    },
  );
  test(
    'selection changes discard stale availability/quote responses',
    () async {
      final (w, r, c) = await form();
      r.delayedQuote = Completer<BookingQuote>();
      final request = c.checkQuote(), old = c.state.draft.selection!;
      c.time('19:00');
      r.delayedQuote!.complete(r.makeQuote(old));
      await request;
      expect(c.state.quote, isNull);
      expect(c.state.draft.time, '19:00');
      await c.close();
      await w.close();
    },
  );
  test(
    'rescheduling requires a reason and preserves existing payments/reference',
    () async {
      final (w, r, c) = await form();
      customer(c);
      split(c);
      await c.review();
      await c.confirm();
      final id = c.state.resultId!;
      await c.close();
      final reschedule = BookingFormCubit(
        w,
        r,
        BookingLaunch(rescheduleId: id),
      );
      await reschedule.load();
      reschedule.time('19:00');
      await reschedule.review();
      expect(reschedule.state.review, isFalse);
      reschedule.reason('Customer requested evening');
      await reschedule.review();
      expect(reschedule.state.balance, 10000);
      await reschedule.confirm();
      final b = await r.detail(id);
      expect(b.reference, 'BK-TEST');
      expect(b.payments.length, 3);
      expect(b.balance, 10000);
      expect(r.submitted.last.body.containsKey('payments'), isFalse);
      await reschedule.close();
      await w.close();
    },
  );
  test(
    'detail collects split balance and customer edits do not rewrite prior payments',
    () async {
      final (w, r, c) = await form();
      customer(c);
      c.addPayment();
      c.updatePayment(
        c.state.draft.payments.single.id,
        (p) => p.copyWith(amount: '300'),
      );
      await c.review();
      await c.confirm();
      final id = c.state.resultId!;
      await c.close();
      final d = BookingDetailCubit(w, r, id);
      await d.load();
      expect(d.state.record!.cleanupMinutes, 5);
      r.records[id]!['price_snapshot'] = <String, dynamic>{
        ...Map<String, dynamic>.from(r.records[id]!['price_snapshot']),
        'cleanup_minutes': 12,
      };
      await d.load();
      expect(d.state.record!.cleanupMinutes, 12);
      d.begin(BookingDetailAction.collection);
      expect(d.state.payments.single.amount, '');
      expect(d.state.paymentEntry.remaining, 20000);
      d.payBalance(d.state.payments.single.id);
      expect(d.state.payments.single.amount, '200.00');
      d.updatePayment(
        d.state.payments.single.id,
        (p) => p.copyWith(amount: '100', method: 'upi'),
      );
      d.addPayment();
      expect(d.state.payments.last.amount, '100.00');
      d.updatePayment(
        d.state.payments.last.id,
        (p) => p.copyWith(amount: '101'),
      );
      expect(
        d.state.paymentError(d.state.payments.last),
        contains('remaining'),
      );
      d.updatePayment(
        d.state.payments.last.id,
        (p) => p.copyWith(amount: '100', method: 'card'),
      );
      d.addPayment();
      expect(d.state.payments.last.isBlank, isTrue);
      await d.submit();
      expect(d.state.record!.balance, 0);
      expect(d.state.record!.payments.length, 3);
      d.begin(BookingDetailAction.customer);
      d.notes('Updated note');
      await d.submit();
      expect(d.state.record!.notes, 'Updated note');
      expect(d.state.record!.payments.length, 3);
      await d.close();
      await w.close();
    },
  );
  test(
    'overpayment and invalid customer details cannot enter review',
    () async {
      final (w, r, c) = await form();
      await c.review();
      expect(c.state.review, isFalse);
      customer(c);
      c.addPayment();
      c.updatePayment(
        c.state.draft.payments.single.id,
        (p) => p.copyWith(amount: '501'),
      );
      await c.review();
      expect(c.state.review, isFalse);
      expect(c.state.error, contains('exceed'));
      expect(r.submitted, isEmpty);
      await c.close();
      await w.close();
    },
  );
  test('workspace identity changes clear booking lists and drafts', () async {
    final source = BookingSource(), w = WorkspaceCubit(source);
    await w.load();
    final r = FakeBookingRepository(),
        c = BookingFormCubit(w, r, const BookingLaunch(date: '2030-06-04')),
        list = BookingListCubit(w, r, BookingListMode.bookings);
    await c.load();
    customer(c);
    await list.load();
    source.value = const Workspace();
    await w.load();
    await Future<void>.delayed(Duration.zero);
    expect(c.state.draft.customer.name, '');
    expect(c.state.catalog.businesses, isEmpty);
    expect(list.state.bookings, isEmpty);
    await c.close();
    await list.close();
    await w.close();
  });
  testWidgets(
    'no configured spaces shows guidance without a review or payment footer',
    (tester) async {
      final source = BookingSource();
      final repository = FakeBookingRepository()..noBookableBusinesses = true;
      getIt.registerSingleton<WorkspaceRepository>(source);
      registerFeatureDependencies(getIt);
      await getIt.unregister<BookingRepository>();
      getIt.registerSingleton<BookingRepository>(repository);
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      addTearDown(workspace.close);
      final router = GoRouter(
        initialLocation: '/booking/new',
        routes: [
          GoRoute(
            path: '/booking/new',
            builder: (c, s) => const BookingFormScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        BlocProvider.value(
          value: workspace,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (context, child) =>
                MaterialApp.router(theme: darkTheme(), routerConfig: router),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No bookable businesses'), findsOneWidget);
      expect(find.text('Review booking'), findsNothing);
      expect(find.text('Total: Check price'), findsNothing);
      expect(repository.submitted, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'reference form renders sport cards, dates and slots in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = BookingSource(), r = FakeBookingRepository(flexible: true);
      r.catalogOverride = BookingCatalog(
        canView: true,
        canManage: true,
        canCollect: true,
        businesses: [
          BookingBusiness(
            id: 'business',
            name: 'Eden Turf',
            type: 'turf',
            timezone: 'Asia/Kolkata',
            today: '2030-06-04',
            spaces: [
              for (final id in ['full', 'a', 'b'])
                BookingSpace(
                  id: id,
                  name: id == 'full'
                      ? 'Main Ground · Main Ground · Full Ground'
                      : id == 'a'
                      ? 'Main Ground · Main Ground · Half A'
                      : 'Main Ground · Main Ground · Half B',
                  capacity: 1,
                  options: [
                    for (final sport in ['football', 'cricket'])
                      BookingOption(
                        id: '$id-$sport',
                        name: sport,
                        sport: sport,
                        format: '5s',
                        kind: 'hourly',
                        durations: [60, 90, 120],
                        defaultDuration: 60,
                        minimumDuration: 60,
                      ),
                  ],
                ),
            ],
          ),
        ],
      );
      getIt.registerSingleton<WorkspaceRepository>(source);
      registerFeatureDependencies(getIt);
      await getIt.unregister<BookingRepository>();
      getIt.registerSingleton<BookingRepository>(r);
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      addTearDown(workspace.close);
      final router = GoRouter(
        initialLocation: '/booking/new',
        routes: [
          GoRoute(
            path: '/booking/new',
            builder: (c, s) => const BookingFormScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);
      final boundaryKey = GlobalKey();
      Future<void> capture(String name) async {
        if (!const bool.fromEnvironment('BOOKING_PREVIEWS')) return;
        final repaint =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        repaint.markNeedsPaint();
        await tester.pump();
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('.local/booking-previews/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      ThemeData previewTheme(bool dark) {
        var theme = dark ? darkTheme() : lightTheme();
        if (const bool.fromEnvironment('BOOKING_PREVIEWS')) {
          theme = theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
            filledButtonTheme: FilledButtonThemeData(
              style: theme.filledButtonTheme.style?.copyWith(
                textStyle: const WidgetStatePropertyAll(
                  TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }
        return theme;
      }

      for (final dark in [false, true]) {
        await tester.pumpWidget(
          BlocProvider.value(
            value: workspace,
            child: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (c, _) => MaterialApp.router(
                theme: previewTheme(dark),
                routerConfig: router,
                builder: (c, child) =>
                    RepaintBoundary(key: boundaryKey, child: child!),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        scroll.position.jumpTo(0);
        await tester.pumpAndSettle();
        await capture(dark ? 'dark-form' : 'light-form');
        await tester.ensureVisible(
          find.byKey(const ValueKey('booking-sport-cricket')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('booking-sport-cricket')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Semantics>(
                find.byKey(const ValueKey('booking-sport-cricket')),
              )
              .properties
              .selected,
          isTrue,
        );
        await capture(dark ? 'dark-spaces' : 'light-spaces');
        await tester.ensureVisible(find.text('Choose start & end'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('booking-time-09:00')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        await capture(dark ? 'dark-slots' : 'light-slots');
        expect(find.text('Booked'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('booking-time-10:00')));
        await tester.pumpAndSettle();
        expect(find.text('End · tap to clear'), findsOneWidget);
        await capture(dark ? 'dark-range' : 'light-range');
        await tester.tap(find.byKey(const ValueKey('booking-time-10:00')));
        await tester.pumpAndSettle();
        expect(find.text('End · tap to clear'), findsNothing);
        expect(find.text('Start · tap to clear'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('booking-time-09:00')));
        await tester.pumpAndSettle();
        expect(find.text('Start · tap to clear'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'full-screen booking supports three payment methods at 320px with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = BookingSource(), r = FakeBookingRepository(flexible: true);
      getIt.registerSingleton<WorkspaceRepository>(source);
      registerFeatureDependencies(getIt);
      await getIt.unregister<BookingRepository>();
      getIt.registerSingleton<BookingRepository>(r);
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      addTearDown(workspace.close);
      final router = GoRouter(
        initialLocation: '/booking/new',
        routes: [
          GoRoute(
            path: '/booking/new',
            builder: (c, s) => const BookingFormScreen(
              launch: BookingLaunch(date: '2030-06-04'),
            ),
          ),
          GoRoute(
            path: '/booking/:id',
            builder: (c, s) => BookingDetailScreen(id: s.pathParameters['id']!),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        BlocProvider.value(
          value: workspace,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (context, child) => MaterialApp.router(
              theme: darkTheme(),
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      Future<void> tapFinder(Finder f) async {
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Future<void> tap(String text) => tapFinder(find.text(text));
      Finder field(String label, int index) => find.descendant(
        of: find
            .byWidgetPredicate(
              (w) => w is ConfigurationField && w.label == label,
            )
            .at(index),
        matching: find.byType(TextFormField),
      );
      Future<void> enter(String label, String text, [int index = 0]) async {
        final f = field(label, index);
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.enterText(f, text);
        await tester.pumpAndSettle();
      }

      await enter('Full name', 'Customer One');
      await enter('Phone number', '9876543210');
      await tap('Date & time');
      await tapFinder(find.byKey(const ValueKey('booking-time-09:00')));
      expect(find.text('Choose start & end'), findsWidgets);
      expect(find.text('Minimum 60 min'), findsWidgets);
      await tapFinder(find.byKey(const ValueKey('booking-time-10:00')));
      await tap('Payments');
      await tap('Add discount');
      await tap('Percentage');
      await enter('Discount percentage', '10');
      expect(find.text('Discount reason · optional'), findsOneWidget);
      await tap('Remove');
      for (var i = 0; i < 3; i++) {
        await tap('Add other payment');
        if (i > 0) {
          await tapFinder(
            find
                .byWidgetPredicate(
                  (w) => w is AppPicker && w.label == 'Payment method',
                )
                .at(i),
          );
          await tap(['Cash', 'UPI', 'Card'][i]);
        }
        await enter('Amount · INR', i == 0 ? '100' : '200', i);
      }
      await tap('Review booking');
      expect(find.text('Confirm booking'), findsOneWidget);
      await tap('Confirm booking');
      expect(find.text('BK-TEST'), findsOneWidget);
      expect(r.records.length, 1);
      expect((r.records.values.single['payments'] as List).length, 3);
      expect(tester.takeException(), isNull);
    },
  );
}
