# Android layout after switching apps

Symptom: after leaving a focused input and returning to Booking OS, content can
remain shortened with a keyboard-sized blank region at the bottom. The image
suggests stale Android IME insets; this has not yet been confirmed on the device.

`AppResumeLayout` is mounted once in the MaterialApp builder so it covers all
routes, dialogs and tabs. On hidden/paused it drops the old keyboard focus and
requests IME dismissal. Until fresh editable focus, it discards the old keyboard
inset and restores safe-area padding. New input focus immediately restores normal
keyboard resizing. It does not replace routes, reset scroll/forms, or reload data.
Transient inactive states (notification shade/permission prompts) do not dismiss
focus. The workaround is limited to native Android; web and iOS remain unchanged.

Validation: regression supplies a persistent 300-pixel Android inset, backgrounds
and resumes the app, and checks full-height recovery, retained field text and
scroll position, and keyboard resizing after refocusing. Run with:

```sh
flutter test test/app_resume_layout_test.dart test/retained_page_state_test.dart
```

On a device running the updated source, focus a price field, type a value, open
another app, return and check the full page is visible. Repeat with the keyboard
closed, rotate the phone, and open the keyboard again. Confirm form values and
scroll position remain. If the gap persists, capture actual view size/insets and
Android IME visibility on the device before making further platform changes.
No database migration/API deployment is required. No APK was built or installed.
