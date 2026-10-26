import 'dart:ui' as ui;
import 'package:image/image.dart' as image_data;
import '../../../utils/exceptions/app_exception.dart';
import '../../../utils/services/logo_picker_service.dart';

abstract interface class WebsitePaymentQrRepository {
  Future<LogoSelection?> pick();
}

/// Reads and checks the image locally; selection never publishes payment details.
class DeviceWebsitePaymentQrRepository implements WebsitePaymentQrRepository {
  DeviceWebsitePaymentQrRepository({Future<LogoSelection?> Function()? picker})
    : _picker = picker ?? LogoPickerService().pick;
  final Future<LogoSelection?> Function() _picker;
  @override
  Future<LogoSelection?> pick() async {
    final image = await _picker();
    if (image == null) return null;
    if (image.bytes.isEmpty || image.bytes.length > 1024 * 1024) {
      throw const AppException('Choose a QR image up to 1 MB.');
    }
    if (![
      'image/png',
      'image/jpeg',
      'image/webp',
    ].contains(image.contentType)) {
      throw const AppException('Choose a PNG, JPEG or WebP QR image.');
    }
    ui.Codec? codec;
    try {
      // Encoded ImageDescriptor dimensions are unsupported on Flutter web.
      // Read portable header metadata first, then verify with Flutter's codec.
      final decoder = switch (image.contentType) {
        'image/png' => image_data.PngDecoder(),
        'image/jpeg' => image_data.JpegDecoder(),
        _ => image_data.WebPDecoder(),
      };
      final info = decoder.startDecode(image.bytes);
      if (info == null || info.width < 1 || info.height < 1) {
        throw const AppException(
          'Cannot preview this image. Choose a valid PNG, JPEG or WebP QR image.',
        );
      }
      if (info.width > 4096 || info.height > 4096) {
        throw const AppException(
          'Choose a QR image no larger than 4096 × 4096 pixels.',
        );
      }
      codec = await ui.instantiateImageCodec(
        image.bytes,
        targetWidth: info.width > 512 ? 512 : info.width,
        targetHeight: info.height > 512 ? 512 : info.height,
      );
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      return image;
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException(
        'Cannot preview this image. Choose a valid PNG, JPEG or WebP QR image.',
      );
    } finally {
      codec?.dispose();
    }
  }
}
