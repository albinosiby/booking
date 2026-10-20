# Booking OS logo

Lime B monogram with a booking check, on the existing near-black brand background.

- `booking_os_mark.png`: original transparent foreground, generated with the built-in image-generation tool.
- `booking_os_launcher.png`: opaque 1024px master for legacy Android, iOS and web icons.
- `../../flutter_launcher_icons.yaml`: platform icon configuration, including adaptive foreground padding and Android monochrome/themed icons.

Regenerate platform assets from the repository root:

```sh
dart run scripts/prepare_branding.dart
dart run flutter_launcher_icons
```

The preparation script only resizes and composites the original onto #0F0F0F; it does not redraw the generated mark. The foreground is kept transparent for adaptive Android icons. iOS icons are opaque and OS masks provide the final rounded shape.

Generation prompt:

> Use case: logo-brand. Create one premium, exceptionally clean app logo mark for Booking OS, a mobile business booking and accounts app. Asset: square 1024x1024 transparent PNG, only the standalone foreground symbol. Design: a confident geometric uppercase B monogram with two generous rounded internal counters, subtly integrating a single bold booking-confirmation check into its lower bowl. Simple intentional geometry, rounded corners, even visual weight, strong recognisable silhouette at 32px. Flat solid bright lime green #5DD62C only, actual transparent background and transparent negative spaces. The mark will sit on a near-black #0F0F0F launcher background. Center the complete mark within the middle 60% of the image, generous transparent margins, no edge clipping. Professional brand identity, crisp vector-like edges. No words, no lettering other than the abstract B monogram, no watermark, no mockup, no phone, no shadows, no gradients, no 3D, no enclosing rounded-square tile.
