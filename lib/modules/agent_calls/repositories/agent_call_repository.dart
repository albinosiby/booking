import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../models/sarvam_models.dart';

abstract interface class SarvamRepository {
  Future<SarvamSettings> settings();

  /// Omitted API key keeps the backend credential.
  Future<SarvamSettings> connect({
    required int version,
    required Set<String> businessIds,
    required String orgId,
    required String workspaceId,
    required String appId,
    String? apiKey,
  });

  Future<SarvamSettings> setupStep();
  Future<SarvamSettings> disconnect();
  Future<SarvamSettings> setBookingEnabled(int version, bool enabled);
  Future<SarvamSettings> publish(int version, String deploymentId);
  Future<bool> openAuthorization(String url);

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
