import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:eden_booking/modules/booking_website/repositories/rest_website_repository.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:eden_booking/utils/services/logo_picker_service.dart';
import 'package:eden_booking/utils/services/rest_api_service.dart';

final class PickedPhoto extends PlatformFile {
  PickedPhoto(this.data, {this.name = 'space.jpg'});
  final Uint8List data;
  int reads = 0;
  @override
  final String name;
  @override
  Uri get uri => Uri.parse('memory://$name');
  @override
  Never get xFile => throw UnimplementedError();
  @override
  int lengthSync() => data.length;
  @override
  Future<int?> length() async => data.length;
  @override
  Future<Uint8List> readAsBytes() async {
    reads++;
    return data;
  }

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(data);
}

class PhotoPickerPlatform extends FilePickerPlatform {
  PickedPhoto? photo;
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => photo;
}

class UnusedPhotoApi extends Fake implements RestApiService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FilePickerPlatform previous;
  late PhotoPickerPlatform picker;
  setUp(() {
    previous = FilePickerPlatform.instance;
    picker = PhotoPickerPlatform();
    FilePickerPlatform.instance = picker;
  });
  tearDown(() => FilePickerPlatform.instance = previous);
  test(
    'a 4 MB website photo is accepted, compressed and ready for preview',
    () async {
      final jpeg = img.encodeJpg(img.Image(width: 32, height: 32));
      final bytes = Uint8List(4 * 1024 * 1024)..setRange(0, jpeg.length, jpeg);
      picker.photo = PickedPhoto(bytes);
      final selected = await RestWebsiteRepository(
        UnusedPhotoApi(),
      ).pickImage();
      expect(selected, isNotNull);
      expect(selected!.contentType, 'image/jpeg');
      expect(selected.bytes.length, lessThanOrEqualTo(1024 * 1024));
      final decoded = img.decodeJpg(selected.bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, 32);
      expect(picker.photo!.reads, 1);
    },
  );
  test(
    'website photos above 10 MB are rejected before reading the bytes',
    () async {
      picker.photo = PickedPhoto(Uint8List(10 * 1024 * 1024 + 1));
      await expectLater(
        RestWebsiteRepository(UnusedPhotoApi()).pickImage(),
        throwsA(
          isA<AppException>().having(
            (error) => error.message,
            'message',
            contains('10 MB'),
          ),
        ),
      );
      expect(picker.photo!.reads, 0);
    },
  );
  test(
    'the organization logo picker retains its existing 2 MB limit',
    () async {
      picker.photo = PickedPhoto(Uint8List(4 * 1024 * 1024));
      await expectLater(
        LogoPickerService().pick(),
        throwsA(
          isA<AppException>().having(
            (error) => error.message,
            'message',
            contains('2 MB'),
          ),
        ),
      );
      expect(picker.photo!.reads, 0);
    },
  );
  test(
    'cancelling website photo selection produces no pending image',
    () async {
      expect(await RestWebsiteRepository(UnusedPhotoApi()).pickImage(), isNull);
    },
  );
}
