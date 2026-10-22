import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../models/agent_call_models.dart';

abstract interface class AgentCallRepository {
  Future<AgentServiceStatus> status();
  Future<AgentServiceStatus> request(String note);
  Future<AgentServiceStatus> setEnabled(bool enabled);

  Future<AgentCallPage> calls(DateTime start, DateTime end);
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
