import '../../core/errors/data_exceptions.dart';

enum ChatMessageRole {
  user('user'),
  assistant('assistant'),
  system('system');

  const ChatMessageRole(this.jsonValue);

  final String jsonValue;

  static ChatMessageRole fromJson(Object? value) {
    if (value is! String) {
      throw const DataFormatException('ChatMessage.role must be a string.');
    }
    for (final role in ChatMessageRole.values) {
      if (role.jsonValue == value) {
        return role;
      }
    }
    throw DataFormatException('Unsupported ChatMessage.role: $value');
  }
}
