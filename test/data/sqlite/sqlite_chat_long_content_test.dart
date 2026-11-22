import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/chat/chat_message.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';

import 'sqlite_test_helpers.dart';

void main() {
  test(
    'SQLite preserves and extends a 10000-character interrupted reply',
    () async {
      final fixture = await SqliteFixture.create();
      await fixture.chatRepository.upsertSession(
        chatSession('session-1', null),
      );
      final initial = List.generate(
        10000,
        (index) => String.fromCharCode(0x4e00 + index % 2000),
      ).join();
      final message = ChatMessage(
        metadata: metadata('assistant-long'),
        sessionId: 'session-1',
        projectId: null,
        role: ChatMessageRole.assistant,
        content: initial,
        finishReason: AiFinishReason.interrupted,
      );
      await fixture.chatRepository.appendMessage(message);

      final interrupted = await fixture.chatRepository.getMessage(message.id);
      expect(interrupted.content.length, 10000);
      expect(interrupted.content, initial);
      expect(interrupted.finishReason, AiFinishReason.interrupted);

      const suffix = '\n续接后的完整结尾。';
      await fixture.chatRepository.upsertMessage(
        interrupted.copyWith(
          metadata: interrupted.metadata.copyWith(
            updatedAt: DateTime.utc(2026, 1, 2),
            revision: interrupted.revision + 1,
          ),
          content: '$initial$suffix',
          finishReason: AiFinishReason.stop,
        ),
      );
      final completed = await fixture.chatRepository.getMessage(message.id);
      expect(completed.id, message.id);
      expect(completed.content, '$initial$suffix');
      expect(completed.finishReason, AiFinishReason.stop);
    },
  );
}
