import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class ProfileAvatarPicker {
  Future<Uint8List?> pick();
}

final profileAvatarPickerProvider = Provider<ProfileAvatarPicker>(
  (ref) => const SafProfileAvatarPicker(),
);

class SafProfileAvatarPicker implements ProfileAvatarPicker {
  const SafProfileAvatarPicker();

  @override
  Future<Uint8List?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: false,
      withReadStream: false,
      allowMultiple: false,
    );
    if (result == null) return null;
    final file = result.files.single;
    final path = file.path;
    if (path == null || path.isEmpty) {
      throw const FormatException('无法读取图片文件，请重新选择');
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final png = await const MethodChannel(
        'com.ibuki.ibukihome/profile',
      ).invokeMethod<Uint8List>('prepareAvatar', {'path': path});
      if (png == null || png.isEmpty) {
        throw const FormatException('无法读取这张图片，请选择有效的图片');
      }
      return png;
    }
    return normalizeProfileAvatarFile(path);
  }
}

Future<Uint8List> normalizeProfileAvatar(Uint8List bytes) async {
  return _normalizeProfileBuffer(await ui.ImmutableBuffer.fromUint8List(bytes));
}

Future<Uint8List> normalizeProfileAvatarFile(String path) async {
  return _normalizeProfileBuffer(await ui.ImmutableBuffer.fromFilePath(path));
}

Future<Uint8List> _normalizeProfileBuffer(ui.ImmutableBuffer buffer) async {
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final factor = math.min(
      1.0,
      256 / math.max(descriptor.width, descriptor.height),
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * factor).round()),
      targetHeight: math.max(1, (descriptor.height * factor).round()),
    );
    image = (await codec.getNextFrame()).image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null || png.lengthInBytes > 256 * 1024) {
      throw const FormatException('无法使用这张头像，请选择其他图片');
    }
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
