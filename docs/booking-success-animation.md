# Booking success animation

After a verified new booking succeeds, the booking form shows the supplied
ticket/check artwork centered at 240 logical pixels over a lightly dimmed form.
The overlay blocks taps and back actions, plays once for 2.8 seconds, then opens
the existing booking details route with `created=1`. The existing success sound
continues independently.

`BookingSuccess` lives in the design system and paints with Flutter Canvas, with
no new asset or package dependency. It respects reduced motion (completed static
artwork) and ancestor TickerMode. Small viewports scale the illustration down.
The form is excluded from accessibility semantics while the confirmation is
announced as a live region.

The screen listens only for a changed verified result ID. Failed or uncertain
saves show no animation; a verified recovered save shows it once. Rescheduling
and admissions retain their existing navigation. The navigation timer is disposed
with the form and checks the current route and result before opening details.

No database migration, API change, native rebuild, or additional setup is required.
Hot reload can load the widget code; use a fresh new booking to trigger playback.

Validation: `flutter analyze` and
`flutter test test/booking_success_animation_test.dart test/booking_success_sound_test.dart test/booking_module_test.dart test/pool_booking_options_test.dart`.
The animation tests cover phone/desktop centering, timing, duplicate confirmation,
blocked dismissal, unverified-save recovery, disposal, rescheduling, and reduced
motion.
