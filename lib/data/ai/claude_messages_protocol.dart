import '../../core/network/ai_provider_exceptions.dart';
import '../../domain/ai/ai_generation.dart';
import '../../domain/ai/ai_token_usage.dart';
import 'ai_usage_codec.dart';

const claudeApiVersion = '2023-06-01';

Map<String, Object?> claudeMessagesBody({
  required String model,
  required List<Map<String, Object?>> messages,
  required int maxTokens,
  required bool stream,
  bool structuredJson = false,
}) {
  final system = <String>[];
  final turns = <Map<String, Object?>>[];
  var historyStarted = false;
  for (final message in messages) {
    final role = message['role'];
    final content = message['content'];
    if (content is! String && content is! List) {
      throw const AiProviderProtocolException();
    }
    if (role == 'system' || role == 'developer') {
      if (historyStarted) {
        throw const AiProviderValidationException('Claude 不支持在历史消息中间插入系统提示。');
      }
      if (content is! String) throw const AiProviderProtocolException();
      system.add(content);
    } else if (role == 'user' || role == 'assistant') {
      historyStarted = true;
      turns.add({'role': role, 'content': content});
    } else {
      throw const AiProviderProtocolException();
    }
  }
  if (turns.isEmpty) {
    throw const AiProviderValidationException('Claude 对话至少需要一条消息。');
  }
  if (turns.first['role'] == 'assistant') {
    turns.insert(0, {
      'role': 'user',
      'content': 'Continue the following conversation.',
    });
  }
  if (structuredJson) {
    system.add(
      'Return only a valid JSON object, without Markdown fences or commentary.',
    );
  }
  return {
    'model': model,
    'max_tokens': maxTokens,
    'stream': stream,
    if (system.isNotEmpty) 'system': system.join('\n\n'),
    'messages': turns,
  };
}

AiFinishReason claudeFinishReason(Object? reason) => switch (reason) {
  'end_turn' || 'stop_sequence' => AiFinishReason.stop,
  'max_tokens' || 'model_context_window_exceeded' => AiFinishReason.length,
  'refusal' => AiFinishReason.contentFiltered,
  _ => AiFinishReason.unknown,
};

/// Only final text is exposed. Thinking/signature/tool blocks are never chat text.
class ClaudeMessageDecoder {
  ClaudeMessageDecoder({this.onUsage, this.onReasoning});
  final void Function(String)? onReasoning;
  final void Function(AiTokenUsage)? onUsage;
  final _usage = <String, Object?>{};
  bool _hasOutputUsage = false;
  AiFinishReason? _finish;
  bool completed = false;

  Iterable<AiStreamEvent> add(Map<String, dynamic> packet) sync* {
    if (completed) throw const AiProviderProtocolException();
    final message = packet['message'];
    final rawUsage = packet['type'] == 'message_start' && message is Map
        ? message['usage']
        : packet['usage'];
    if (rawUsage is Map) {
      for (final entry in rawUsage.entries) {
        if (entry.key is String && entry.value is num) {
          _usage[entry.key as String] = entry.value;
        }
      }
      if (packet['type'] != 'message_start' &&
          rawUsage['output_tokens'] is num) {
        _hasOutputUsage = true;
      }
    }
    final usage = claudeUsage(
      _usage,
      isFinal: packet['type'] == 'message_stop' && _hasOutputUsage,
    );
    if (usage != null) onUsage?.call(usage);
    switch (packet['type']) {
      case 'error':
        final error = packet['error'];
        throw claudeHttpError(200, error is Map ? error : const {});
      case 'content_block_start':
        final block = packet['content_block'];
        if (block is! Map) throw const AiProviderProtocolException();
        if (block['type'] == 'thinking' && block['thinking'] is String) {
          onReasoning?.call(block['thinking'] as String);
        }
        if (block['type'] == 'text' &&
            block['text'] is String &&
            (block['text'] as String).isNotEmpty) {
          yield AiStreamEvent.content(block['text'] as String);
        }
      case 'content_block_delta':
        final delta = packet['delta'];
        if (delta is! Map) throw const AiProviderProtocolException();
        if (delta['type'] == 'thinking_delta' && delta['thinking'] is String) {
          onReasoning?.call(delta['thinking'] as String);
        }
        if (delta['type'] == 'text_delta') {
          if (_finish != null) throw const AiProviderProtocolException();
          if (delta['text'] is! String) {
            throw const AiProviderProtocolException();
          }
          if ((delta['text'] as String).isNotEmpty) {
            yield AiStreamEvent.content(delta['text'] as String);
          }
        }
      case 'message_delta':
        final delta = packet['delta'];
        if (delta is! Map) throw const AiProviderProtocolException();
        if (delta['stop_reason'] != null) {
          _finish = claudeFinishReason(delta['stop_reason']);
        }
      case 'message_stop':
        completed = true;
        yield AiStreamEvent.finished(_finish ?? AiFinishReason.unknown);
      default:
        // message_start, ping, block_stop and future non-text event variants.
        break;
    }
  }
}

AiProviderException claudeHttpError(int status, Map error) {
  final type = error['type'];
  final message = (error['message'] is String ? error['message'] as String : '')
      .toLowerCase();
  if (status == 401 || type == 'authentication_error') {
    return const AiProviderAuthenticationException();
  }
  if (status == 403 || type == 'permission_error') {
    return const AiProviderRequestRejectedException();
  }
  if (status == 429 || type == 'rate_limit_error') {
    return const AiProviderRateLimitedException();
  }
  if (status == 408 || status == 504) return const AiProviderTimeoutException();
  if (status >= 500 || type == 'overloaded_error' || type == 'api_error') {
    return const AiProviderServerException();
  }
  if (status == 413 ||
      message.contains('too long') ||
      message.contains('context') ||
      message.contains('too many tokens')) {
    return const AiProviderContextTooLargeException();
  }
  if (type == 'not_found_error' && message.contains('model')) {
    return const AiProviderModelUnavailableException();
  }
  if (status == 404) return const AiProviderEndpointException();
  return const AiProviderProtocolException('Claude 拒绝了当前请求，请检查模型、接口与请求参数。');
}
