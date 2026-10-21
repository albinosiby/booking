import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../models/sarvam_models.dart';

abstract interface class SarvamRepository {
  Future<SarvamSettings> settings();

  /// [apiKey] null keeps the saved Sarvam key.
  Future<SarvamSettings> save({
    required int version,
    required bool enabled,
    required Set<String> businessIds,
    required String orgId,
    required String workspaceId,
    required String appId,
    String? apiKey,
  });

  /// Returns the new tool key; it cannot be read again later.
  Future<String> rotateToolKey();

  /// Number of calls in the last 24 hours.
  Future<int> test();
  Future<SarvamCallPage> calls(DateTime start, DateTime end);
  Future<List<TranscriptLine>> transcript(String interactionId);
  Future<List<int>> recording(String interactionId);
}

abstract interface class RecordingSaver {
  Future<bool> save(List<int> bytes, String filename);
}

class DeviceRecordingSaver implements RecordingSaver {
  @override
  Future<bool> save(List<int> bytes, String filename) async =>
      await FilePicker.saveFile(
        fileName: filename,
        bytes: Uint8List.fromList(bytes),
        mimeType: 'audio/wav',
        type: FileType.custom,
        allowedExtensions: const ['wav'],
      ) !=
      null;
}
