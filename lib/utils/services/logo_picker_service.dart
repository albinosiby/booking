import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../../constants/app_constants.dart';
import '../exceptions/app_exception.dart';

class LogoSelection {
  const LogoSelection(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
}

class LogoPickerService {
  Future<LogoSelection?> pick({int maxBytes = AppConstants.logoLimit}) async {
    final sizeLabel = maxBytes % (1024 * 1024) == 0
        ? '${maxBytes ~/ (1024 * 1024)} MB'
        : '$maxBytes bytes';
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      );
      if (file == null) return null;
      if ((file.lengthSync() ?? 0) > maxBytes) {
        throw AppException('Choose an image up to $sizeLabel.');
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > maxBytes) {
        throw AppException('Choose an image up to $sizeLabel.');
      }
      final contentType = switch (file.extension?.toLowerCase()) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'jpg' || 'jpeg' => 'image/jpeg',
        _ => throw const AppException('Choose a PNG, JPEG or WebP image.'),
      };
      return LogoSelection(bytes, contentType);
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException(
        'Could not open the image picker. Please try again.',
      );
    }
  }
}
