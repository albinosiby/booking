import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Packages the supplied artwork without stretching, cropping or redrawing it.
/// Run from the repository root, then run `dart run flutter_launcher_icons`.
void main() {
  final source = img.decodePng(
    File('assets/branding/booking_os_source.png').readAsBytesSync(),
  );
  if (source == null || !source.hasAlpha) {
    throw StateError('Expected the original RGBA PNG artwork.');
  }
  final mark = square(source, 1024);
  final launcher = img.Image(width: 1024, height: 1024, numChannels: 3);
  img.fill(launcher, color: img.ColorRgb8(15, 15, 15));
  img.compositeImage(launcher, mark);
  png('assets/branding/booking_os_mark.png', mark);
  png('assets/branding/booking_os_launcher.png', launcher);

  // Android tints these alpha masks. Keep the B/check silhouette, rather than
  // turning the enclosing dark tile into an unreadable solid white square.
  final monochrome = monogramMask(mark);
  png('assets/branding/booking_os_monochrome.png', square(monochrome, 1024));

  png('landing-page/public/_landing/images/bookingos-mark.png', mark);
  for (final path in [
    'landing-page/public/_landing/images/bookingos-app-icon.png',
    'admin-panel/public/booking-os-logo.png',
    'booking-website/assets/bookingos-icon.png',
  ]) {
    png(path, square(mark, 192));
  }

  final bounds = img.findTrim(monochrome, mode: img.TrimMode.transparent);
  final notification = square(
    img.copyCrop(
      monochrome,
      x: bounds[0],
      y: bounds[1],
      width: bounds[2],
      height: bounds[3],
    ),
    240,
    padding: 24,
  );
  for (final density in {
    'mdpi': 1.0,
    'hdpi': 1.5,
    'xhdpi': 2.0,
    'xxhdpi': 3.0,
    'xxxhdpi': 4.0,
  }.entries) {
    final base = 'android/app/src/main/res/drawable-${density.key}';
    png('$base/launch_logo.png', square(mark, (96 * density.value).round()));
    png(
      '$base/ic_stat_booking.png',
      square(notification, (24 * density.value).round()),
    );
  }
  final launch = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
  png('$launch/LaunchImage.png', square(mark, 96));
  png('$launch/LaunchImage@2x.png', square(mark, 192));
  png('$launch/LaunchImage@3x.png', square(mark, 288));
  stdout.writeln(
    'Prepared shared branding, web copies, launch images and Android alpha masks.',
  );
}

img.Image square(img.Image source, int size, {int padding = 0}) {
  final scale = (size - padding * 2) / math.max(source.width, source.height);
  final image = img.copyResize(
    source,
    width: (source.width * scale).round(),
    height: (source.height * scale).round(),
    interpolation: img.Interpolation.cubic,
  );
  return img.compositeImage(
    img.Image(width: size, height: size, numChannels: 4),
    image,
    dstX: (size - image.width) ~/ 2,
    dstY: (size - image.height) ~/ 2,
  );
}

void png(String path, img.Image image) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
}

/// The largest connected bright-green shape is the supplied B/check. The thin
/// green tile rim is separate. This conversion is only for OS-required masks;
/// the full-colour logo always uses the original artwork.
img.Image monogramMask(img.Image mark) {
  final small = square(mark, 256);
  final candidates = Uint8List(256 * 256);
  for (final pixel in small) {
    if (pixel.a > 128 &&
        ((pixel.g > 110 && pixel.b < pixel.g * .35) ||
            (pixel.g > 150 &&
                pixel.r + pixel.g > 190 &&
                pixel.b < pixel.g * .75))) {
      candidates[pixel.y * 256 + pixel.x] = 1;
    }
  }
  var largest = <int>[];
  for (var start = 0; start < candidates.length; start++) {
    if (candidates[start] == 0) continue;
    final component = <int>[start];
    candidates[start] = 0;
    for (var cursor = 0; cursor < component.length; cursor++) {
      final index = component[cursor];
      for (final next in [
        if (index % 256 > 0) index - 1,
        if (index % 256 < 255) index + 1,
        if (index >= 256) index - 256,
        if (index < 256 * 255) index + 256,
      ]) {
        if (candidates[next] == 0) continue;
        candidates[next] = 0;
        component.add(next);
      }
    }
    if (component.length > largest.length) largest = component;
  }
  if (largest.length < candidates.length ~/ 10) {
    throw StateError(
      'Could not isolate the supplied monogram for Android masks.',
    );
  }
  final mask = img.Image(width: 256, height: 256, numChannels: 4);
  for (final index in largest) {
    mask.setPixelRgba(index % 256, index ~/ 256, 255, 255, 255, 255);
  }
  return mask;
}
