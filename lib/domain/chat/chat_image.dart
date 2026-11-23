import 'dart:convert';
import 'dart:typed_data';

/// One locally stored, prepared image. No external path or remote URL is trusted.
class ChatImage {
  ChatImage({
    required this.base64Data,
    required this.mimeType,
    required this.userText,
    this.description,
  }) {
    _validateHeader();
    _bytes;
  }

  ChatImage._stored({
    required this.base64Data,
    required this.mimeType,
    required this.userText,
    this.description,
  }) {
    _validateHeader();
  }

  void _validateHeader() {
    if (base64Data.length > (maxBytes + 2) ~/ 3 * 4 ||
        !const {'image/jpeg', 'image/png', 'image/webp'}.contains(mimeType) ||
        (description != null &&
            (description!.trim().isEmpty || description!.length > 16000))) {
      throw const FormatException('图片格式或大小无效。');
    }
  }

  Uint8List _validateBytes() {
    final data = base64Decode(base64Data);
    final valid = switch (mimeType) {
      'image/jpeg' =>
        data.length >= 3 && data[0] == 255 && data[1] == 216 && data[2] == 255,
      'image/png' =>
        data.length >= 8 && base64Encode(data.sublist(0, 8)) == 'iVBORw0KGgo=',
      'image/webp' =>
        data.length >= 12 &&
            ascii.decode(data.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
            ascii.decode(data.sublist(8, 12), allowInvalid: true) == 'WEBP',
      _ => false,
    };
    if (!valid || data.length > maxBytes) {
      throw const FormatException('图片数据或识别结果无效。');
    }
    return data.asUnmodifiableView();
  }

  static const maxBytes = 2 * 1024 * 1024;
  final String base64Data;
  final String mimeType;
  final String userText;
  final String? description;
  late final Uint8List _bytes = _validateBytes();
  Uint8List get bytes => _bytes;
  bool get needsRecognition => description == null;

  ChatImage recognized(String text) => ChatImage(
    base64Data: base64Data,
    mimeType: mimeType,
    userText: userText,
    description: text.trim(),
  );
  ChatImage withUserText(String text) =>
      ChatImage(base64Data: base64Data, mimeType: mimeType, userText: text);
  bool sameSource(ChatImage other) =>
      base64Data == other.base64Data &&
      mimeType == other.mimeType &&
      userText == other.userText;

  Map<String, Object?> toJson() => {
    'data': base64Data,
    'mime': mimeType,
    'userText': userText,
    'description': description,
  };

  /// Defer decoding only for rows already validated when written to local storage.
  factory ChatImage.fromJson(
    Map<String, dynamic> json, {
    bool deferDecoding = false,
  }) {
    if (json['data'] is! String ||
        json['mime'] is! String ||
        json['userText'] is! String ||
        (json['description'] != null && json['description'] is! String)) {
      throw const FormatException('图片记录无效。');
    }
    final create = deferDecoding ? ChatImage._stored : ChatImage.new;
    return create(
      base64Data: json['data'] as String,
      mimeType: json['mime'] as String,
      userText: json['userText'] as String,
      description: json['description'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatImage &&
      sameSource(other) &&
      description == other.description;
  @override
  int get hashCode => Object.hash(base64Data, mimeType, userText, description);
}
