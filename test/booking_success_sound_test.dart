import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_form_cubit.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/repositories/booking_feedback_repository.dart';
import 'package:eden_booking/modules/bookings/repositories/device_booking_feedback_repository.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'booking_module_test.dart'
    show BookingSource, FakeBookingRepository, customer;

class FeedbackSpy implements BookingFeedbackRepository {
  final ids = <String>[];
  bool fail = false;
  @override
  Future<void> created(String id) async {
    ids.add(id);
    if (fail) throw StateError('Audio unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final recovered in [false, true]) {
    test(
      'success sound once per new confirmed command; recovered=$recovered',
      () async {
        final w = WorkspaceCubit(BookingSource());
        await w.load();
        final r = FakeBookingRepository()..loseResponse = recovered;
        final feedback = FeedbackSpy();
        final c = BookingFormCubit(
          w,
          r,
          const BookingLaunch(date: '2030-06-04'),
          feedback: feedback,
        );
        await c.load();
        customer(c);
        await c.review();
        await c.confirm();
        expect(c.state.resultId, isNotNull);
        expect(feedback.ids, [c.state.resultId]);
        await c.confirm();
        expect(feedback.ids.length, 1);
        expect(r.records.length, 1);
        final reschedule = BookingFormCubit(
          w,
          r,
          BookingLaunch(rescheduleId: c.state.resultId),
          feedback: feedback,
        );
        await reschedule.load();
        reschedule.reason('Customer request');
        reschedule.time('19:00');
        await reschedule.review();
        await reschedule.confirm();
        expect(reschedule.state.resultId, isNotNull);
        expect(feedback.ids.length, 1);
        await reschedule.close();
        await c.close();
        await w.close();
      },
    );
  }
  test(
    'unverified response is silent; verified retry plays; sound failure keeps booking successful',
    () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final r = FakeBookingRepository()
        ..loseResponse = true
        ..lookupFails = true;
      final feedback = FeedbackSpy()..fail = true;
      final c = BookingFormCubit(
        w,
        r,
        const BookingLaunch(date: '2030-06-04'),
        feedback: feedback,
      );
      await c.load();
      customer(c);
      await c.review();
      await c.confirm();
      expect(c.state.resultId, isNull);
      expect(feedback.ids, isEmpty);
      r.lookupFails = false;
      await c.confirm();
      await Future<void>.delayed(Duration.zero);
      expect(c.state.resultId, isNotNull);
      expect(c.state.error, isNull);
      expect(feedback.ids.length, 1);
      await c.close();
      await w.close();
    },
  );
  test(
    'Android feedback calls native playback once and ignores device audio errors',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('booking_os/feedback_test');
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'playBookingSuccess');
            calls++;
            throw PlatformException(code: 'AUDIO_UNAVAILABLE');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final feedback = DeviceBookingFeedbackRepository(channel: channel);
      await feedback.created('one');
      await feedback.created('one');
      await feedback.created('two');
      expect(calls, 2);
    },
  );
}
