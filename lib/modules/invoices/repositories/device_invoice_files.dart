import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'invoice_repository.dart';

class DeviceInvoiceFiles implements InvoiceFileGateway {
  @override
  Future<bool> save(List<int> bytes, String filename) async =>
      await FilePicker.saveFile(
        fileName: filename,
        bytes: Uint8List.fromList(bytes),
        mimeType: 'application/pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      ) !=
      null;
  @override
  Future<void> share(List<int> bytes, String filename) =>
      SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(bytes),
              mimeType: 'application/pdf',
              name: filename,
            ),
          ],
          fileNameOverrides: [filename],
          subject: filename,
        ),
      );
}
