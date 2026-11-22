import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TxtNovelFile {
  const TxtNovelFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

abstract interface class TxtNovelPicker {
  Future<TxtNovelFile?> pick();
}

class SafTxtNovelPicker implements TxtNovelPicker {
  const SafTxtNovelPicker();
  @override
  Future<TxtNovelFile?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final path = file.path;
    final bytes = path != null ? await File(path).readAsBytes() : file.bytes;
    if (bytes == null) throw const FormatException('无法读取所选 TXT 文件。');
    return TxtNovelFile(file.name, bytes);
  }
}

class DecodedNovelText {
  const DecodedNovelText(this.text, this.encoding);
  final String text;
  final String encoding;
}

class TxtNovelDecoder {
  const TxtNovelDecoder();
  static const channel = MethodChannel('com.ibuki.ibukihome/novel-text');
  Future<DecodedNovelText> decode(Uint8List bytes) async {
    final unicode = await compute(decodeUnicodeNovelText, bytes);
    if (unicode != null) return unicode;
    try {
      final text = await channel.invokeMethod<String>('decodeLegacyTxt', {
        'bytes': bytes,
      });
      if (text == null) throw const FormatException('TXT 解码失败。');
      return DecodedNovelText(text, 'GB18030 / GBK');
    } on MissingPluginException {
      throw const FormatException('未识别 TXT 编码，请将文件另存为 UTF-8 后导入。');
    } on PlatformException {
      throw const FormatException('无法识别这个 TXT，请检查文件或另存为 UTF-8。');
    }
  }
}

DecodedNovelText? decodeUnicodeNovelText(Uint8List bytes) {
  if (bytes.isEmpty) return const DecodedNovelText('', 'UTF-8');
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff))) {
    if (bytes.length.isOdd) throw const FormatException('UTF-16 文件内容不完整。');
    final little = bytes[0] == 0xff;
    final units = <int>[];
    for (var i = 2; i < bytes.length; i += 2) {
      units.add(
        little ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1],
      );
    }
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
          throw const FormatException('UTF-16 文件包含不完整字符。');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const FormatException('UTF-16 文件包含不完整字符。');
      }
    }
    return DecodedNovelText(
      String.fromCharCodes(units),
      little ? 'UTF-16 LE' : 'UTF-16 BE',
    );
  }
  try {
    return DecodedNovelText(utf8.decode(bytes), 'UTF-8');
  } on FormatException {
    return null;
  }
}

class PreparedTxtNovel {
  const PreparedTxtNovel({
    required this.fileName,
    required this.title,
    required this.encoding,
    required this.parts,
    required this.characters,
  });
  final String fileName;
  final String title;
  final String encoding;
  final List<String> parts;
  final int characters;
}

PreparedTxtNovel prepareTxtNovel(
  ({String fileName, String text, String encoding}) input,
) {
  if (!input.fileName.toLowerCase().endsWith('.txt')) {
    throw const FormatException('请选择 .txt 文件。');
  }
  final text = input.text
      .replaceFirst(RegExp('^\ufeff'), '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  if (text.trim().isEmpty) throw const FormatException('这个 TXT 没有小说正文。');
  if (RegExp(r'[\x00-\x08\x0e-\x1f]').hasMatch(text)) {
    throw const FormatException('文件包含非文本内容，请选择纯文本 TXT。');
  }
  final parts = <String>[];
  var start = 0;
  while (start < text.length) {
    var end = (start + 6000).clamp(0, text.length);
    if (end < text.length) {
      final newline = text.lastIndexOf('\n', end - 1);
      if (newline > start + 3000) end = newline + 1;
      if (text.codeUnitAt(end - 1) >= 0xd800 &&
          text.codeUnitAt(end - 1) <= 0xdbff) {
        end--;
      }
    }
    parts.add(text.substring(start, end));
    start = end;
  }
  final name = input.fileName.substring(0, input.fileName.length - 4).trim();
  return PreparedTxtNovel(
    fileName: input.fileName,
    title: name.isEmpty ? '导入的小说' : name,
    encoding: input.encoding,
    parts: List.unmodifiable(parts),
    characters: text.runes.length,
  );
}
