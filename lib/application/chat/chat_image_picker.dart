import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/chat/chat_image.dart';

final chatImagePickerProvider = Provider<ChatImagePicker>(
  (ref) => const ChatImagePicker(),
);

class ChatImagePicker {
  const ChatImagePicker();
  Future<ChatImage?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: false,
      allowMultiple: false,
    );
    if (result == null) return null;
    final file = result.files.single;
    final path = file.path;
    if (path == null) throw const FormatException('无法读取这张图片。');
    final Uint8List bytes;
    String mime;
    if (Platform.isAndroid) {
      final prepared = await const MethodChannel(
        'com.ibuki.ibukihome/profile',
      ).invokeMethod<Uint8List>('prepareChatImage', {'path': path});
      if (prepared == null) throw const FormatException('无法处理这张图片。');
      bytes = prepared;
      mime = 'image/jpeg';
    } else {
      final source = File(path);
      if (await source.length() > ChatImage.maxBytes) {
        throw const FormatException('请先缩小图片再发送。');
      }
      bytes = await source.readAsBytes();
      mime = bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216
          ? 'image/jpeg'
          : bytes.length >= 12 &&
                ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP'
          ? 'image/webp'
          : 'image/png';
    }
    return ChatImage(
      base64Data: base64Encode(bytes),
      mimeType: mime,
      userText: '',
    );
  }
}
