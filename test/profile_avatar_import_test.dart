import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/profile/profile_avatar_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.ibuki.ibukihome/profile');
  late RecordingPicker picker;
  late int nativeCalls;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    picker = RecordingPicker();
    FilePicker.platform = picker;
    nativeCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls++;
          expect(call.method, 'prepareAvatar');
          expect(call.arguments, {'path': '/cache/file_picker/photo.jpg'});
          return Uint8List.fromList([1, 2, 3]);
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'large original uses its cached path without loading bytes or a Dart stream',
    () async {
      picker.result = FilePickerResult([
        PlatformFile(
          name: 'photo.jpg',
          path: '/cache/file_picker/photo.jpg',
          size: 48 * 1024 * 1024,
        ),
      ]);
      expect(
        await const SafProfileAvatarPicker().pick(),
        orderedEquals([1, 2, 3]),
      );
      expect(picker.withData, false);
      expect(picker.withReadStream, false);
      expect(picker.type, FileType.image);
      expect(nativeCalls, 1);
    },
  );

  test('unknown source size does not prevent thumbnail decoding', () async {
    picker.result = FilePickerResult([
      PlatformFile(
        name: 'photo.jpg',
        path: '/cache/file_picker/photo.jpg',
        size: 0,
      ),
    ]);
    expect(await const SafProfileAvatarPicker().pick(), isNotEmpty);
    expect(nativeCalls, 1);
  });

  test('canceling the native picker does not start decoding', () async {
    expect(await const SafProfileAvatarPicker().pick(), isNull);
    expect(nativeCalls, 0);
  });

  test('missing cached file is rejected before native decoding', () async {
    picker.result = FilePickerResult([
      PlatformFile(name: 'photo.jpg', size: 20 * 1024 * 1024),
    ]);
    await expectLater(
      const SafProfileAvatarPicker().pick(),
      throwsFormatException,
    );
    expect(nativeCalls, 0);
  });

  test('failed native decoding remains a recoverable picker error', () async {
    picker.result = FilePickerResult([
      PlatformFile(
        name: 'photo.jpg',
        path: '/cache/file_picker/photo.jpg',
        size: 48 * 1024 * 1024,
      ),
    ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'avatar_decode_failed'),
        );
    await expectLater(
      const SafProfileAvatarPicker().pick(),
      throwsA(isA<PlatformException>()),
    );
  });

  test('empty native thumbnail is not accepted as a saved avatar', () async {
    picker.result = FilePickerResult([
      PlatformFile(
        name: 'photo.jpg',
        path: '/cache/file_picker/photo.jpg',
        size: 12 * 1024 * 1024,
      ),
    ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => Uint8List(0));
    await expectLater(
      const SafProfileAvatarPicker().pick(),
      throwsFormatException,
    );
  });

  testWidgets('file decoder preserves aspect ratio and produces a small PNG', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = null;
    final bytes = await rootBundle.load(
      'assets/images/navigation/nav_chat.png',
    );
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'profile-file-test-',
      );
      final file = File('${directory.path}/avatar.png');
      try {
        await file.writeAsBytes(bytes.buffer.asUint8List());
        final result = await normalizeProfileAvatarFile(file.path);
        final codec = await ui.instantiateImageCodec(result);
        final image = (await codec.getNextFrame()).image;
        try {
          expect(image.width, lessThanOrEqualTo(256));
          expect(image.height, lessThanOrEqualTo(256));
          expect(image.width, image.height);
          expect(result.length, lessThanOrEqualTo(256 * 1024));
        } finally {
          image.dispose();
          codec.dispose();
        }
      } finally {
        if (await file.exists()) await file.delete();
        await directory.delete();
      }
    });
  });
}

class RecordingPicker extends FilePicker {
  FilePickerResult? result;
  bool? withData, withReadStream;
  FileType? type;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    this.withData = withData;
    this.withReadStream = withReadStream;
    this.type = type;
    return result;
  }
}
