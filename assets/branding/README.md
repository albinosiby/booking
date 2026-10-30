# BookingOS logo

The green B/check tile supplied by the user on 30 October 2026 is the project logo.

- `booking_os_source.png`: unchanged original attachment (1286 × 1223 RGBA).
- `booking_os_mark.png`: transparent 1024px square, with the complete artwork centred at its original aspect ratio.
- `booking_os_launcher.png`: opaque 1024px master composited on #0F0F0F for iOS, legacy Android and web installation icons.
- `booking_os_monochrome.png`: B/check alpha silhouette for Android themed icons. Notification icons use a tightly framed version of this silhouette because Android tints their alpha channel.
- The other numbered design explorations are historical assets and are not referenced by the application.

Regenerate every copy from the repository root, in this order:

```sh
dart run scripts/prepare_branding.dart
dart run flutter_launcher_icons
```

The preparation script preserves the full-colour artwork without stretching, cropping or redrawing it. It prepares the masters, website copies, native splash images and notification masks. The launcher generator then writes the Android/iOS launcher and web installation icons using `flutter_launcher_icons.yaml`. No new package is needed.

## Branding locations

| Surface | Shared asset / integration |
| --- | --- |
| Flutter authentication and app navigation | `AssetPath.bookingLogo` → `booking_os_mark.png` |
| Flutter web loading screen, favicon and installed PWA | `web/index.html`, `web/favicon.png`, `web/icons/`, `web/manifest.json` |
| Android launcher and themed launcher | `mipmap-*/ic_launcher.png`, adaptive foreground and monochrome resources |
| Android notifications and native startup | `drawable-*/ic_stat_booking.png`, `launch_logo.png`, launch backgrounds and Android 12+ launch themes |
| iOS launcher and native startup | `AppIcon.appiconset`, `LaunchImage.imageset`, `LaunchScreen.storyboard` |
| Marketing header, footer and product mockups | `BookosLogo` / `BookosMark` → `landing-page/public/_landing/images/bookingos-mark.png` |
| Marketing favicon / Apple touch icon | `landing-page/public/_landing/images/bookingos-app-icon.png` |
| Admin login/navigation and browser icons | `admin-panel/public/booking-os-logo.png`, shared `Brand` and layout metadata |
| Booking website generic, loading, error and unavailable pages | shared `BookingOsMark` |
| Venue header without a published custom logo | shared `BookingOsMark` fallback |
| Venue homepage and booking-page product attribution | shared `PoweredByBookingOs` |
| Booking website default browser icon | `booking-website/assets/bookingos-icon.png` |

Venue/organisation profile logos, published website logos, invoice identity and customer-uploaded photos retain their own branding. A published venue logo continues to take precedence over the BookingOS browser-icon fallback. Functional booking/calendar icons are not product logos.

## Release and recovery

Rebuild and deploy the existing Railway frontend service to publish the web changes. Static marketing/admin logo references use a new version query to refresh cached copies; the public booking asset import receives a content hash. Native app icons and startup screens require a new Android/iOS build and normal distribution. Nothing is installed automatically. There is no API deployment or database migration for this branding change.

To recover, redeploy the preceding frontend release and distribute the preceding native app build. Keep the supplied original in version control so future asset regeneration remains reproducible.

## Verification

All 17 focused Flutter branding/authentication tests passed, including phone, tablet, desktop, light/dark and large-text layouts. Targeted Flutter analysis is clean. All three web projects passed TypeScript checking; all 19 public booking website tests passed. Local HTTP checks confirmed rendered logo references, favicon metadata and successful image responses on marketing, admin login and generic booking pages. Android resources compiled with AAPT2, and the iOS launch storyboard passed XML validation. Generated colour and monochrome icons were inspected at small sizes. Full native app builds and physical-device startup/notification checks are not included in these results.
