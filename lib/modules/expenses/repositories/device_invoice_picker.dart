import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../models/expense_models.dart';
import 'expenses_repository.dart';

class DeviceInvoicePicker implements InvoicePicker {
  @override
  Future<List<ExpensePickedInvoice>> pick({
    bool camera = false,
    bool photos = false,
  }) async {
    final result = <ExpensePickedInvoice>[];
    Future<void> add(
      String name,
      int size,
      Future<List<int>> Function() read,
    ) async {
      if (size <= 0 || size > 15 * 1024 * 1024) {
        throw const AppException('Each invoice must be no larger than 15 MB.');
      }
      final ext = name.split('.').last.toLowerCase(),
          type = {
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'png': 'image/png',
            'webp': 'image/webp',
            'pdf': 'application/pdf',
          }[ext];
      if (type == null) {
        throw const AppException('Choose JPEG, PNG, WebP images or PDF files.');
      }
      final bytes = await read();
      // Retain at most ten bounded files; uploads run sequentially.
      result.add(
        ExpensePickedInvoice(
          ExpenseInvoice(
            id: const Uuid().v4(),
            name: name.length > 180 ? name.substring(name.length - 180) : name,
            type: type,
            size: bytes.length,
          ),
          Uint8List.fromList(bytes),
        ),
      );
    }

    if (camera || photos) {
      final picker = ImagePicker();
      final files = camera
          ? [
              ?await picker.pickImage(
                source: ImageSource.camera,
                maxWidth: 2000,
                maxHeight: 2000,
                imageQuality: 85,
              ),
            ]
          : await picker.pickMultiImage(
              maxWidth: 2000,
              maxHeight: 2000,
              imageQuality: 85,
              limit: 10,
            );
      for (final f in files) {
        await add(f.name, await f.length(), f.readAsBytes);
      }
    } else {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      );
      if (files.length > 10) {
        throw const AppException('Choose up to 10 invoices.');
      }
      for (final f in files) {
        await add(f.name, await f.length() ?? 0, f.readAsBytes);
      }
    }
    return result;
  }
}
