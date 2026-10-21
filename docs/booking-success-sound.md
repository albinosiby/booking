# Booking success sound (Android)

The supplied new_booking_bell.mp3 was copied unchanged into
android/app/src/main/res/raw/new_booking_bell.mp3. Android plays it through the
booking_os/feedback method channel with notification-event audio attributes,
asynchronous preparation and completion/error cleanup. It does not loop, request
notification permission, post a notification banner or alter system volume.
It is an in-app booking confirmation sound, not remote push notification delivery.

BookingFormCubit receives an optional BookingFeedbackRepository through DI.
After the server returns a verified successful new booking ID (including command
recovery after a lost response), it emits success immediately and requests audio
without waiting. Failed or uncertain saves, rescheduling, payment collection and
viewing details do not trigger audio. Repeated confirmation is guarded; Cubit
and device adapter also deduplicate booking IDs. The adapter keeps at most 64
IDs in memory. Audio errors cannot change persistence or the success state.
Non-Android platforms safely skip this Android implementation.

The MP3 source supplied by the user was:
/Users/albinosiby/Tatos Dev/bookingos/mobile/android/app/src/main/res/raw/new_booking_bell.mp3

## Testing on a phone

Native Android resource/channel changes require a full app rebuild and restart.
Hot reload/hot restart alone cannot add them to an already installed old binary.
When you next run the Android app from source, stop the old run and run it again
normally with your existing project configuration. Notification volume/silent
settings can affect audibility. Confirm an unpaid booking as well as a paid one;
both should play once. Check that rescheduling and failed saves remain silent.

No database migration, API deployment or new Dart dependency is required.
No APK packaging or installation was requested/performed for this change.

## Implementation reference

Android MediaPlayer local-resource and asynchronous preparation guidance:
https://developer.android.com/media/platform/mediaplayer/basics
