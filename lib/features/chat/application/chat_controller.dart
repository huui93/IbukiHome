import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../mascot/application/mascot_controller.dart';
import '../../mascot/domain/mascot_action.dart';
import '../domain/chat_message.dart';

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

class ChatState {
  const ChatState({
    required this.messages,
    required this.draft,
    required this.isWaitingForDemoReply,
  });

  factory ChatState.initial() {
    return const ChatState(
      messages: [],
      draft: '',
      isWaitingForDemoReply: false,
    );
  }

  final List<ChatMessage> messages;
  final String draft;
  final bool isWaitingForDemoReply;

  bool get canSend => draft.trim().isNotEmpty && !isWaitingForDemoReply;

  ChatState copyWith({
    List<ChatMessage>? messages,
    String? draft,
    bool? isWaitingForDemoReply,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      draft: draft ?? this.draft,
      isWaitingForDemoReply:
          isWaitingForDemoReply ?? this.isWaitingForDemoReply,
    );
  }
}

class ChatController extends Notifier<ChatState> {
  Timer? _replyTimer;
  var _disposed = false;
  var _messageCount = 0;

  @override
  ChatState build() {
    ref.onDispose(() {
      _disposed = true;
      _replyTimer?.cancel();
    });

    return ChatState.initial();
  }

  void updateDraft(String value) {
    if (value == state.draft) {
      return;
    }

    state = state.copyWith(draft: value);
  }

  void fillSuggestion(String value) {
    _replyTimer?.cancel();
    state = state.copyWith(draft: value, isWaitingForDemoReply: false);
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.listen);
  }

  void focusInput() {
    if (!state.isWaitingForDemoReply) {
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.listen);
    }
  }

  void leaveInput() {
    if (state.messages.isEmpty && !state.isWaitingForDemoReply) {
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
    }
  }

  void sendDraft({Duration replyDelay = const Duration(milliseconds: 900)}) {
    final text = state.draft.trim();
    if (text.isEmpty || state.isWaitingForDemoReply) {
      return;
    }

    _replyTimer?.cancel();
    final sentAt = DateTime.now();
    final nextMessages = [
      ...state.messages,
      ChatMessage(
        id: 'local-${_messageCount++}',
        role: ChatMessageRole.user,
        text: text,
        createdAt: sentAt,
      ),
      ChatMessage(
        id: 'local-${_messageCount++}',
        role: ChatMessageRole.system,
        text: '本地演示：尚未连接桌面端或真实 AI。',
        createdAt: sentAt,
      ),
    ];

    state = state.copyWith(
      messages: nextMessages,
      draft: '',
      isWaitingForDemoReply: true,
    );
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);

    _replyTimer = Timer(replyDelay, () {
      if (_disposed) {
        return;
      }

      state = state.copyWith(
        messages: [
          ...state.messages,
          ChatMessage(
            id: 'local-${_messageCount++}',
            role: ChatMessageRole.assistant,
            text: '我先把这个念头接住。可以从角色现在最想隐瞒的事开始，也可以写一个只有她听见的声音。',
            createdAt: DateTime.now(),
          ),
        ],
        isWaitingForDemoReply: false,
      );
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
    });
  }
}
