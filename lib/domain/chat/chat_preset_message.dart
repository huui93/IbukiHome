import '../../core/errors/data_exceptions.dart';

class ChatPresetMessage {
  const ChatPresetMessage({required this.user, required this.assistant});
  final String user;
  final String assistant;

  Map<String, Object?> toJson() => {'user': user, 'assistant': assistant};

  static List<ChatPresetMessage> parseList(Object? value) {
    if (value == null) return const [];
    if (value is! List) throw const DataFormatException('预设消息格式无效。');
    return List.unmodifiable(
      value.map((entry) {
        if (entry is! Map ||
            entry['user'] is! String ||
            entry['assistant'] is! String) {
          throw const DataFormatException('预设消息需要用户消息和 AI 回答。');
        }
        final user = (entry['user'] as String).trim();
        final assistant = (entry['assistant'] as String).trim();
        if (user.isEmpty || assistant.isEmpty) {
          throw const DataFormatException('请完整填写用户消息和 AI 回答。');
        }
        return ChatPresetMessage(user: user, assistant: assistant);
      }),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatPresetMessage &&
      user == other.user &&
      assistant == other.assistant;
  @override
  int get hashCode => Object.hash(user, assistant);
}
