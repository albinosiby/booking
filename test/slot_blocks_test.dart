import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/booking_blocks/screens/slot_block_screens.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/booking_blocks/cubit/slot_block_cubits.dart';
import 'package:eden_booking/modules/booking_blocks/models/slot_block_models.dart';
import 'package:eden_booking/modules/booking_blocks/repositories/slot_block_repository.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;

class Blocks implements SlotBlockRepository {
  final requests = <BlockRequest>[];
  Object? failure;
  Completer<SlotBlockPage>? gate;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<BookingCatalog> catalog() => FakeBookingRepository().catalog();
  @override
  Future<SlotBlockPage> list(
    String businessId,
    String date, {
    int cursor = 0,
  }) async => gate == null ? SlotBlockPage([], null) : await gate!.future;
  List<BlockSlot> grid = [
    for (var h = 0; h < 24; h++)
      for (final m in ['00', '30'])
        BlockSlot(
          '${h.toString().padLeft(2, '0')}:$m',
          h == 9 ? 'booked' : (h == 14 ? 'blocked' : 'available'),
        ),
  ];
  @override
  Future<({List<BlockSlot> slots, int step})> slots(
    String businessId,
    String date,
    Iterable<String> spaces,
  ) async => (slots: grid, step: 30);
  @override
  Future<String> create(BlockRequest request) async {
    requests.add(request);
    if (failure != null) throw failure!;
    return 'saved';
  }

  @override
  Future<void> unblock(String id) async {
    if (failure != null) throw failure!;
  }
}

void main() {
  testWidgets(
    'block form has no reason field and renders review on narrow screens',
    (tester) async {
      await getIt.reset();
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final r = Blocks();
      getIt.registerFactoryParam<BlockFormCubit, WorkspaceCubit, BlockLaunch>(
        (session, launch) => BlockFormCubit(session, r, launch),
      );
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await getIt.reset();
        await w.close();
      });
      for (final brightness in [Brightness.dark, Brightness.light]) {
        await tester.pumpWidget(
          BlocProvider.value(
            value: w,
            child: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, _) => MaterialApp(
                theme: AppTheme.build(brightness),
                home: const NewSlotBlockScreen(
                  launch: BlockLaunch(spaceId: 'space'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Select spaces'), findsOneWidget);
        expect(find.textContaining('Reason'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Review block'));
        await tester.tap(find.text('Review block'));
        await tester.pumpAndSettle();
        expect(find.text('Review blocked slots'), findsOneWidget);
        expect(find.text('Confirm block'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );
  testWidgets('specific hours shows the slot grid and selects a range', (
    tester,
  ) async {
    await getIt.reset();
    final w = WorkspaceCubit(BookingSource());
    await w.load();
    final r = Blocks();
    getIt.registerFactoryParam<BlockFormCubit, WorkspaceCubit, BlockLaunch>(
      (session, launch) => BlockFormCubit(session, r, launch),
    );
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await getIt.reset();
      await w.close();
    });
    await tester.pumpWidget(
      BlocProvider.value(
        value: w,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: AppTheme.build(Brightness.light),
            home: const NewSlotBlockScreen(
              launch: BlockLaunch(spaceId: 'space'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Specific hours'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('block-time-10:00')), findsOneWidget);
    expect(find.text('Booked'), findsWidgets);
    expect(find.text('Blocked'), findsWidgets);
    await tester.ensureVisible(find.byKey(const ValueKey('block-time-10:00')));
    await tester.tap(find.byKey(const ValueKey('block-time-10:00')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('block-time-11:30')));
    await tester.tap(find.byKey(const ValueKey('block-time-11:30')));
    await tester.pumpAndSettle();
    expect(find.text('Until 12:00'), findsOneWidget);
    expect(find.text('10:00 – 12:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  test('grid ranges stop at booked slots and set request times', () async {
    final w = WorkspaceCubit(BookingSource());
    await w.load();
    final r = Blocks(),
        c = BlockFormCubit(w, r, const BlockLaunch(spaceId: 'space'));
    await c.load();
    c.allDay(false);
    await c.submit();
    expect(c.state.error, 'Choose the hours to block.');
    BlockSlot at(String t) => c.state.slots.firstWhere((s) => s.time == t);
    c.pick(at('09:00'));
    expect(c.state.hasRange, isFalse);
    c.pick(at('08:00'));
    c.pick(at('10:00'));
    expect(c.state.from, '10:00');
    expect(c.state.until, '10:00');
    c.pick(at('11:30'));
    expect((c.state.start, c.state.end), ('10:00', '12:00'));
    c.pick(at('10:00'));
    expect(c.state.hasRange, isFalse);
    c.pick(at('23:30'));
    expect(c.state.end, '00:00');
    expect(c.state.endDate, '2030-06-05');
    await c.submit();
    await c.submit();
    expect(r.requests.single.start, '23:30');
    expect(r.requests.single.end, '00:00');
    await c.close();
    await w.close();
  });
  test(
    'review precedes save, overnight dates roll forward and selection toggles',
    () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final r = Blocks(),
          c = BlockFormCubit(w, r, const BlockLaunch(spaceId: 'space'));
      await c.load();
      c.space('space');
      expect(c.state.spaces, isEmpty);
      await c.submit();
      expect(c.state.error, isNotNull);
      c.space('space');
      c.allDay(false);
      c.time('23:00', start: true);
      c.time('03:00', start: false);
      expect(c.state.endDate, '2030-06-05');
      await c.submit();
      expect(c.state.review, isTrue);
      expect(r.requests, isEmpty);
      await c.submit();
      expect(c.state.savedId, 'saved');
      expect(r.requests.single.endDate, '2030-06-05');
      await c.close();
      await w.close();
    },
  );
  test(
    'unknown result retries same command and freezes edits; definite conflict permits editing',
    () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final r = Blocks()..failure = Exception('timeout'),
          c = BlockFormCubit(w, r, const BlockLaunch(spaceId: 'space'));
      await c.load();
      await c.submit();
      await c.submit();
      final request = r.requests.single;
      expect(c.state.locked, isTrue);
      c.space('space');
      c.date('2030-06-06');
      expect(c.state.date, '2030-06-04');
      r.failure = const AppException('Conflict', code: 'CONFLICT');
      await c.submit();
      expect(r.requests.last.key, request.key);
      expect(c.state.locked, isFalse);
      await c.close();
      await w.close();
    },
  );
  test('permission failure clears previously loaded form data', () async {
    final w = WorkspaceCubit(BookingSource());
    await w.load();
    final r = Blocks()
          ..failure = const AppException('Denied', code: 'FORBIDDEN'),
        c = BlockFormCubit(w, r, const BlockLaunch(spaceId: 'space'));
    await c.load();
    await c.submit();
    await c.submit();
    expect(c.state.catalog.businesses, isEmpty);
    expect(c.state.spaces, isEmpty);
    await c.close();
    await w.close();
  });
  test(
    'refresh keeps loaded blocks visible until the replacement arrives',
    () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final r = Blocks(), c = BlockListCubit(w, r, const BlockLaunch());
      await c.load();
      final item = SlotBlock(
        id: 'one',
        start: '2030-06-04T09:00',
        end: '2030-06-04T10:00',
        timezone: 'Asia/Kolkata',
        creator: 'Owner',
        createdAt: '2030-06-01T09:00',
        allDay: false,
        canUnblock: true,
      );
      r.gate = Completer<SlotBlockPage>()
        ..complete(SlotBlockPage([item], null));
      await c.load();
      r.gate = Completer<SlotBlockPage>();
      final loading = c.load();
      await Future<void>.delayed(Duration.zero);
      expect(c.state.blocks.single.id, 'one');
      expect(c.state.loading, isTrue);
      r.gate!.complete(SlotBlockPage([], null));
      await loading;
      expect(c.state.blocks, isEmpty);
      await c.close();
      await w.close();
    },
  );
  test(
    'full-day requests preserve next-day date through month/year boundaries',
    () {
      final request = BlockRequest(
        key: 'key',
        businessId: 'business',
        spaces: ['space'],
        date: '2030-12-31',
        allDay: true,
        start: '09:00',
        end: '10:00',
      );
      expect(request.endDate, '2031-01-01');
      expect(() => request.spaces.clear(), throwsUnsupportedError);
    },
  );
}
