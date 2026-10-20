import 'dart:io';
import 'package:image/image.dart' as img;

/// Packages the generated transparent logo without changing its geometry.
/// Run before `dart run flutter_launcher_icons` when replacing the source mark.
void main() {
  final source = img.decodePng(
    File('assets/branding/booking_os_mark.png').readAsBytesSync(),
  );
  if (source == null || source.width != source.height || !source.hasAlpha) {
    throw StateError('Expected a square PNG with transparency.');
  }
  final foreground = img.copyResize(
    source,
    width: 1024,
    height: 1024,
    interpolation: img.Interpolation.cubic,
  );
  final launcher = img.Image(width: 1024, height: 1024, numChannels: 3);
  img.fill(launcher, color: img.ColorRgb8(15, 15, 15));
  img.compositeImage(launcher, foreground);
  File(
    'assets/branding/booking_os_launcher.png',
  ).writeAsBytesSync(img.encodePng(launcher));
  stdout.writeln('Prepared opaque 1024px launcher master.');
}
