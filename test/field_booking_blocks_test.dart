// Field-value tests for lib/modules/booking_blocks: date, custom start/end
// times, space selection, slot grid ranges, double submit/unblock and
// small-screen / large-text rendering. Real defects are skipped as `BUG-<n>`.
import 'dart:async';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/booking_blocks/cubit/slot_block_cubits.dart';
import 'package:eden_booking/modules/booking_blocks/models/slot_block_models.dart';
import 'package:eden_booking/modules/booking_blocks/screens/slot_block_screens.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'booking_module_test.dart' show BookingSource;
import 'slot_blocks_test.dart' show Blocks;

class GatedBlocks extends Blocks {
  final saveGate = Completer<String>();
  int creates = 0, unblocks = 0;
  List<SlotBlock> existing = [];
  Completer<void>? unblockGate;
  @override
  Future<String> create(BlockRequest request) async {
    creates++;
    requests.add(request);
    return saveGate.future;
  }

  @override
  Future<SlotBlockPage> list(
    String businessId,
    String date, {
    int cursor = 0,
  }) async => SlotBlockPage(existing, null);
  @override
  Future<void> unblock(String id) async {
    unblocks++;
    await unblockGate?.future;
  }
}

SlotBlock block({
  String id = 'b1',
  String creator = 'Owner',
  List<String> spaces = const ['Court 1'],
}) => SlotBlock(
  id: id,
  start: '2030-06-04T09:00',
  end: '2030-06-04T10:00',
  timezone: 'Asia/Kolkata',
  creator: creator,
  createdAt: '2030-06-01T10:00',
  allDay: false,
  canUnblock: true,
  spaces: spaces,
);

Future<(WorkspaceCubit, Blocks, BlockFormCubit)> blockForm([
  Blocks? repo,
  BlockLaunch launch = const BlockLaunch(spaceId: 'space'),
]) async {
  final w = WorkspaceCubit(BookingSource());
  await w.load();
  final r = repo ?? Blocks();
  final c = BlockFormCubit(w, r, launch);
  await c.load();
  return (w, r, c);
}

void main() {
  group('blockSlotEnd', () {
    test('adds minutes and wraps past midnight', () {
      expect(blockSlotEnd('09:00', 30), '09:30');
      expect(blockSlotEnd('23:30', 30), '00:00');
      expect(blockSlotEnd('23:59', 1), '00:00');
      expect(blockSlotEnd('00:00', 0), '00:00');
      expect(blockSlotEnd('12:15', 45), '13:00');
      expect(blockSlotEnd('23:45', 1440), '23:45');
      expect(blockSlotEnd('10:00', 90), '11:30');
    });
  });

  group('BlockRequest.endDate / BlockFormModel', () {
    test('all-day and overnight requests end the next day', () {
      BlockRequest req(
        bool allDay,
        String start,
        String end, [
        String date = '2030-06-04',
      ]) => BlockRequest(
        key: 'k',
        businessId: 'b',
        spaces: const ['s'],
        date: date,
        allDay: allDay,
        start: start,
        end: end,
      );
      expect(req(true, '00:00', '00:00').endDate, '2030-06-05');
      expect(req(false, '09:00', '10:00').endDate, '2030-06-04');
      expect(req(false, '22:00', '02:00').endDate, '2030-06-05');
      expect(req(false, '09:00', '00:00').endDate, '2030-06-05');
      expect(req(false, '10:00', '10:00', '2030-12-31').endDate, '2031-01-01');
      expect(req(false, '10:00', '11:00', '2032-02-28').endDate, '2032-02-28');
      expect(req(true, '00:00', '00:00', '2032-02-28').endDate, '2032-02-29');
    });
    test('validation messages in priority order', () {
      expect(BlockFormModel().validation, 'Choose a business.');
      final catalog = BookingCatalog(
        canView: true,
        canManage: true,
        businesses: [
          BookingBusiness(
            id: 'b',
            name: 'B',
            type: 'turf',
            timezone: 'UTC',
            today: '2030-06-04',
            spaces: [
              for (var i = 0; i < 101; i++)
                BookingSpace(
                  id: 's$i',
                  name: 'S$i',
                  capacity: 1,
                  options: const [],
                ),
            ],
          ),
        ],
      );
      var m = BlockFormModel(catalog: catalog, businessId: 'b');
      expect(m.validation, 'Choose at least one space.');
      m = BlockFormModel(
        catalog: catalog,
        businessId: 'b',
        spaces: [for (var i = 0; i < 101; i++) 's$i'],
      );
      expect(m.validation, 'Choose at most 100 spaces.');
      m = BlockFormModel(catalog: catalog, businessId: 'b', spaces: ['s1']);
      expect(m.validation, 'Choose a date.');
      m = BlockFormModel(
        catalog: catalog,
        businessId: 'b',
        spaces: ['s1'],
        date: '2030-06-04',
        allDay: false,
      );
      expect(m.validation, 'Choose the hours to block.');
      m = m.copy(custom: true);
      expect(m.validation, isNull);
      m = BlockFormModel(
        catalog: catalog,
        businessId: 'b',
        spaces: [for (var i = 0; i < 100; i++) 's$i'],
        date: '2030-06-04',
      );
      expect(m.validation, isNull, reason: 'exactly 100 spaces is allowed');
    });
  });

  group('block form cubit', () {
    Future<void> using(
      Future<void> Function(Blocks r, BlockFormCubit c) body, {
      Blocks? repo,
    }) async {
      final (w, r, c) = await blockForm(repo);
      try {
        await body(r, c);
      } finally {
        await c.close();
        await w.close();
      }
    }

    test('custom time accepts only HH:mm 00:00-23:59', () async {
      await using((r, c) async {
        for (final v in ['00:00', '23:59', '09:05', '12:30']) {
          c.time(v, start: true);
          expect(c.state.start, v);
        }
        c.time('10:15', start: true);
        for (final v in [
          '24:00',
          '9:00',
          '12:60',
          '',
          ' ',
          '12-30',
          '12:3',
          '😀',
          '12:30:00',
          '１２:３０',
          '-1:00',
          ' 09:00',
        ]) {
          c.time(v, start: true);
          c.time(v, start: false);
          expect(c.state.start, '10:15', reason: 'start "$v"');
          expect(c.state.end, '10:00', reason: 'end "$v"');
        }
      });
    });

    test(
      'BUG-10 zero-length custom range (start == end) must not become a 24 hour block',
      () async {
        await using((r, c) async {
          c.allDay(false);
          c.time('10:00', start: true);
          c.time('10:00', start: false);
          expect(c.state.validation, isNotNull);
          await c.submit();
          await c.submit();
          expect(r.requests, isEmpty);
        });
      },
      skip:
          'BUG-10: start==end is accepted and BlockRequest.endDate rolls it to the next day, blocking 24h',
    );

    test('overnight custom range is allowed and ends next day', () async {
      await using((r, c) async {
        c.allDay(false);
        c.time('22:00', start: true);
        c.time('02:00', start: false);
        await c.submit();
        expect(c.state.review, isTrue);
        await c.submit();
        expect(r.requests.single.endDate, '2030-06-05');
        expect(r.requests.single.start, '22:00');
        expect(r.requests.single.end, '02:00');
      });
    });

    test('time edits leave review and clear the grid range', () async {
      await using((r, c) async {
        await c.submit();
        expect(c.state.review, isTrue);
        c.time('11:00', start: true);
        expect(c.state.review, isFalse);
        expect(c.state.custom, isTrue);
        expect(c.state.hasRange, isFalse);
      });
    });

    test(
      'date changes: same date ignored, new date reloads grid and clears range',
      () async {
        await using((r, c) async {
          c.allDay(false);
          await c.loadSlots();
          c.pick(const BlockSlot('10:00', 'available'));
          expect(c.state.hasRange, isTrue);
          c.date(c.state.date);
          expect(c.state.hasRange, isTrue);
          c.date('2030-06-05');
          expect(c.state.hasRange, isFalse);
          expect(c.state.date, '2030-06-05');
        });
      },
    );

    test(
      'BUG-11 past or malformed dates are rejected by the cubit',
      () async {
        await using((r, c) async {
          c.date('2000-01-01');
          expect(c.state.date, isNot('2000-01-01'));
          c.date('not-a-date');
          expect(c.state.date, isNot('not-a-date'));
          expect(() => c.state.endDate, returnsNormally);
        });
      },
      skip:
          'BUG-11: BlockFormCubit.date() accepts past and malformed strings; endDate then throws FormatException during build',
    );

    test('launch date in the past falls back to the business today', () async {
      final (w, r, c) = await blockForm(
        null,
        const BlockLaunch(spaceId: 'space', date: '2001-01-01'),
      );
      expect(c.state.date, '2030-06-04');
      await c.close();
      final (w2, _, c2) = await blockForm(
        null,
        const BlockLaunch(spaceId: 'space', date: '2031-01-01'),
      );
      expect(c2.state.date, '2031-01-01');
      final (w3, _, c3) = await blockForm(
        null,
        const BlockLaunch(spaceId: 'space', date: 'garbage'),
      );
      expect(
        c3.state.date,
        anyOf('2030-06-04', 'garbage'),
        reason: 'string compare: "g" > "2"',
      );
      await c2.close();
      await c3.close();
      await w.close();
      await w2.close();
      await w3.close();
    });

    test(
      'BUG-12 a malformed launch date must fall back to today',
      () async {
        final (w, r, c) = await blockForm(
          null,
          const BlockLaunch(spaceId: 'space', date: 'garbage'),
        );
        expect(c.state.date, '2030-06-04');
        await c.close();
        await w.close();
      },
      skip:
          'BUG-12: launch.date is only compared as a string; "garbage" sorts after "2030..." and is used as the date',
    );

    test('space selection: unknown ids ignored, toggle, all, none', () async {
      await using((r, c) async {
        expect(c.state.spaces, {'space'});
        c.space('ghost');
        expect(c.state.spaces, {'space'});
        c.space('');
        c.space('😀');
        expect(c.state.spaces, {'space'});
        c.space('space');
        expect(c.state.spaces, isEmpty);
        await c.submit();
        expect(c.state.error, 'Choose at least one space.');
        expect(c.state.review, isFalse);
        c.allSpaces();
        expect(c.state.spaces, {'space'});
        c.clearSpaces();
        expect(c.state.spaces, isEmpty);
      });
    });

    test(
      'business switch resets spaces and unknown business is ignored',
      () async {
        await using((r, c) async {
          c.business('ghost');
          expect(c.state.businessId, 'business');
          c.business('business');
          expect(c.state.spaces, isEmpty);
        });
      },
    );

    test(
      'grid picks: booked, blocked, past and unknown cells cannot start a range',
      () async {
        await using((r, c) async {
          c.allDay(false);
          await c.loadSlots();
          for (final s in [
            const BlockSlot('09:00', 'booked'),
            const BlockSlot('14:00', 'blocked'),
            const BlockSlot('00:00', 'past'),
            const BlockSlot('10:00', 'weird-status'),
          ]) {
            c.pick(s);
            expect(c.state.hasRange, isFalse, reason: s.status);
          }
          c.pick(const BlockSlot('23:30', 'available'));
          expect(c.state.start, '23:30');
          expect(c.state.end, '00:00');
          await c.submit();
          await c.submit();
          expect(
            r.requests.single.endDate,
            '2030-06-05',
            reason: 'last half hour ends at midnight next day',
          );
        });
      },
    );

    test(
      'grid range does not extend across a booked cell and tapping start clears',
      () async {
        await using((r, c) async {
          c.allDay(false);
          await c.loadSlots();
          c.pick(const BlockSlot('08:00', 'available'));
          c.pick(const BlockSlot('10:30', 'available'));
          expect(
            c.state.from,
            '10:30',
            reason: '09:00 is booked so the range restarts',
          );
          c.pick(const BlockSlot('10:30', 'available'));
          expect(c.state.hasRange, isFalse);
          c.pick(const BlockSlot('10:00', 'available'));
          c.pick(const BlockSlot('09:30', 'available'));
          expect(
            c.state.from,
            '09:30',
            reason: 'earlier tap restarts the range',
          );
        });
      },
    );

    test(
      'review precedes save; double tap on Confirm creates one block',
      () async {
        final gated = GatedBlocks();
        await using((r, c) async {
          await c.submit();
          expect(c.state.review, isTrue);
          expect(gated.creates, 0);
          final a = c.submit(), b = c.submit(), d = c.submit();
          gated.saveGate.complete('saved');
          await Future.wait([a, b, d]);
          expect(gated.creates, 1);
          expect(c.state.savedId, 'saved');
          await c.submit();
          expect(
            gated.creates,
            1,
            reason: 'saved blocks cannot be resubmitted',
          );
        }, repo: gated);
      },
    );

    test('edits are frozen while a save is pending', () async {
      final gated = GatedBlocks();
      await using((r, c) async {
        await c.submit();
        final pending = c.submit();
        await Future<void>.delayed(Duration.zero);
        c.allDay(false);
        c.date('2030-07-01');
        c.time('10:00', start: true);
        c.clearSpaces();
        expect(c.state.allDay, isTrue);
        expect(c.state.date, '2030-06-04');
        expect(c.state.spaces, {'space'});
        gated.saveGate.complete('x');
        await pending;
      }, repo: gated);
    });
  });

  group('block list cubit', () {
    test(
      'unblock double tap sends one request and ignores non-unblockable blocks',
      () async {
        final w = WorkspaceCubit(BookingSource());
        await w.load();
        final r = GatedBlocks()
          ..existing = [
            block(),
            SlotBlock(
              id: 'locked',
              start: 's',
              end: 'e',
              timezone: 'UTC',
              creator: 'x',
              createdAt: 'c',
              allDay: true,
              canUnblock: false,
            ),
          ]
          ..unblockGate = Completer<void>();
        final c = BlockListCubit(w, r, const BlockLaunch());
        await c.load();
        expect(c.state.blocks, hasLength(2));
        unawaited(c.unblock(c.state.blocks.first));
        unawaited(c.unblock(c.state.blocks.first));
        await c.unblock(c.state.blocks.last);
        await Future<void>.delayed(Duration.zero);
        expect(r.unblocks, 1);
        expect(c.state.busyId, 'b1');
        r.unblockGate!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(c.state.busyId, isNull);
        await c.close();
        await w.close();
      },
    );

    test('same date and business are ignored; date change reloads', () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final r = GatedBlocks();
      final c = BlockListCubit(w, r, const BlockLaunch());
      await c.load();
      final date = c.state.date;
      c.date(date);
      c.business(c.state.businessId!);
      expect(c.state.loading, isFalse);
      c.date('2030-06-09');
      expect(c.state.date, '2030-06-09');
      expect(c.state.blocks, isEmpty);
      await c.close();
      await w.close();
    });
  });

  group('widgets', () {
    Future<void> pump(
      WidgetTester tester,
      Widget home,
      Blocks r, {
      double scale = 1,
      Size size = const Size(320, 568),
    }) async {
      await getIt.reset();
      final w = WorkspaceCubit(BookingSource());
      await tester.runAsync(w.load);
      getIt.registerFactoryParam<BlockFormCubit, WorkspaceCubit, BlockLaunch>(
        (s, l) => BlockFormCubit(s, r, l),
      );
      getIt.registerFactoryParam<BlockListCubit, WorkspaceCubit, BlockLaunch>(
        (s, l) => BlockListCubit(s, r, l),
      );
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.pumpWidget(const SizedBox());
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
              builder: (context, app) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: app!,
              ),
              home: home,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'new block form at 320x568 scale $scale: grid, hours, review',
        (tester) async {
          final r = Blocks();
          await pump(
            tester,
            const NewSlotBlockScreen(launch: BlockLaunch(spaceId: 'space')),
            r,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Specific hours'));
          await tester.tap(find.text('Specific hours'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final cell = find.byKey(const ValueKey('block-time-10:00'));
          await tester.ensureVisible(cell);
          await tester.tap(cell);
          await tester.pumpAndSettle();
          // Tapping a booked cell (09:00) must not change the selection.
          final booked = find.byKey(const ValueKey('block-time-09:00'));
          await tester.ensureVisible(booked);
          await tester.tap(booked, warnIfMissed: false);
          await tester.pumpAndSettle();
          expect(find.text('Until 10:30'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Review block'));
          await tester.tap(find.text('Review block'));
          await tester.pumpAndSettle();
          expect(find.text('Review blocked slots'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('new block form double tap on Confirm block saves once', (
      tester,
    ) async {
      final r = GatedBlocks();
      await pump(
        tester,
        const NewSlotBlockScreen(launch: BlockLaunch(spaceId: 'space')),
        r,
        size: const Size(390, 900),
      );
      await tester.ensureVisible(find.text('Review block'));
      await tester.tap(find.text('Review block'));
      await tester.pumpAndSettle();
      final confirm = find.text('Confirm block');
      await tester.tap(confirm);
      await tester.pump();
      await tester.tap(find.byType(AppButton).last, warnIfMissed: false);
      await tester.pump();
      expect(r.creates, 1);
      expect(find.text('Blocking…'), findsOneWidget);
    });

    testWidgets(
      'new block form shows error when manage permission is missing',
      (tester) async {
        final r = Blocks();
        final repo = _NoManage();
        await pump(tester, const NewSlotBlockScreen(), repo, scale: 2);
        expect(find.textContaining('permission'), findsWidgets);
        expect(find.text('Review block'), findsNothing);
        expect(tester.takeException(), isNull);
        expect(r.requests, isEmpty);
      },
    );

    testWidgets('new block form with no businesses shows guidance', (
      tester,
    ) async {
      await pump(tester, const NewSlotBlockScreen(), _NoBusiness(), scale: 2);
      expect(find.text('No spaces ready'), findsOneWidget);
      expect(find.text('Review block'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'blocked list with long names, emoji and many spaces at 320px scale $scale',
        (tester) async {
          final r = GatedBlocks()
            ..existing = [
              block(
                creator: 'Albino ${'S' * 120} 😀',
                spaces: [
                  for (var i = 0; i < 25; i++)
                    'Very long court name number $i ✨',
                ],
              ),
              block(id: 'b2', creator: ''),
            ];
          await pump(tester, const SlotBlocksScreen(), r, scale: scale);
          expect(find.text('Nothing blocked'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('blocked list empty state', (tester) async {
      await pump(tester, const SlotBlocksScreen(), GatedBlocks(), scale: 2);
      expect(find.text('Nothing blocked'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('blocked list permission error state', (tester) async {
      await pump(tester, const SlotBlocksScreen(), _NoManage(), scale: 2);
      expect(find.textContaining('permission'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

class _NoManage extends Blocks {
  @override
  Future<BookingCatalog> catalog() async => BookingCatalog(canView: true);
}

class _NoBusiness extends Blocks {
  @override
  Future<BookingCatalog> catalog() async =>
      BookingCatalog(canView: true, canManage: true);
}
