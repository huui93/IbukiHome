import '../../domain/chat/chat_message.dart';
import '../../domain/segments/segment.dart';
import '../../domain/ai/ai_generation.dart';

enum AiDraftStatus {
  streaming,
  retrying,
  autoRecovering,
  completed,
  limited,
  interrupted,
  cancelled,
  contentFiltered,
  providerError,
}

class AiDraftUpdate {
  const AiDraftUpdate({
    required this.requestId,
    required this.draft,
    required this.status,
    this.savedSegment,
    this.savedMessage,
    this.finishReason,
    this.pluginNotice,
    this.outputNotice,
    this.storyEnded = false,
  });

  final String requestId;
  final String draft;
  final AiDraftStatus status;
  final Segment? savedSegment;
  final ChatMessage? savedMessage;
  final AiFinishReason? finishReason;
  final String? pluginNotice;
  final String? outputNotice;
  final bool storyEnded;
}
