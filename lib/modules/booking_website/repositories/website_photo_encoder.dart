import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../../../utils/exceptions/app_exception.dart';
import '../../../utils/services/logo_picker_service.dart';

/// Runs in a worker isolate on native platforms. Only one static frame is accepted.
Uint8List encodeWebsitePhoto(LogoSelection selected) {
  try {
    final img.Decoder decoder = switch (selected.contentType) {
      'image/jpeg' => img.JpegDecoder(maxPixels: 24000000),
      'image/png' => img.PngDecoder(maxPixels: 24000000),
      'image/webp' => img.WebPDecoder()..maxPixels = 24000000,
      _ => throw const AppException('Choose a JPEG, PNG or WebP photo.'),
    };
    final info = decoder.startDecode(selected.bytes);
    if (info == null ||
        info.width * info.height > 24000000 ||
        info.numFrames > 1) {
      throw const AppException('Choose a static photo up to 24 megapixels.');
    }
    final decoded = decoder.decodeFrame(0);
    if (decoded == null) {
      throw const AppException(
        'This image could not be read. Choose another photo.',
      );
    }
    final oriented = img.bakeOrientation(decoded);
    final resized = oriented.width > 1920 || oriented.height > 1920
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height ? 1920 : null,
            height: oriented.height > oriented.width ? 1920 : null,
          )
        : oriented;
    resized.exif = img.ExifData();
    resized.iccProfile = null;
    resized.textData = null;
    final bytes = Uint8List.fromList(img.encodeJpg(resized, quality: 82));
    if (bytes.length > 1024 * 1024) {
      throw const AppException(
        'This photo is too large. Choose a smaller image.',
      );
    }
    return bytes.asUnmodifiableView();
  } on AppException {
    rethrow;
  } catch (_) {
    throw const AppException(
      'This image could not be read. Choose a JPEG, PNG or WebP photo.',
    );
  }
}
