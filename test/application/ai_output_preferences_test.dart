import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ibukihome/application/ai/ai_generation_service.dart';
import 'package:ibukihome/application/ai/ai_output_preferences.dart';
import 'package:ibukihome/application/ai/ai_settings_controller.dart';
import 'package:ibukihome/data/memory/in_memory_secure_value_store.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';

void main() {
  test('stream output defaults on and survives a new app container', () async {
    final store = InMemorySecureValueStore();
    final c = ProviderContainer(
      overrides: [aiSecureValueStoreProvider.overrideWithValue(store)],
    );
    expect(await c.read(aiOutputPreferencesProvider.future), isTrue);
    await c.read(aiOutputPreferencesProvider.notifier).setStreaming(false);
    c.dispose();
    final reopened = ProviderContainer(
      overrides: [aiSecureValueStoreProvider.overrideWithValue(store)],
    );
    addTearDown(reopened.dispose);
    expect(await reopened.read(aiOutputPreferencesProvider.future), isFalse);
  });
  test(
    'disabled output waits for terminal event then emits one complete answer',
    () async {
      final source = StreamController<AiStreamEvent>();
      final seen = <AiStreamEvent>[];
      final done = bufferAiOutput(
        source.stream,
        emitDeltas: false,
      ).forEach(seen.add);
      source.add(const AiStreamEvent.content('第一段'));
      source.add(const AiStreamEvent.content('第二段'));
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty);
      source.add(const AiStreamEvent.finished(AiFinishReason.length));
      await source.close();
      await done;
      expect(seen.map((e) => e.content).where((s) => s.isNotEmpty), ['第一段第二段']);
      expect(seen.last.finishReason, AiFinishReason.length);
    },
  );
  test(
    'buffering retains received text and propagates a transport failure',
    () async {
      Stream<AiStreamEvent> broken() async* {
        yield const AiStreamEvent.content('已收到的内容');
        throw StateError('断线');
      }

      final seen = <AiStreamEvent>[];
      await expectLater(
        bufferAiOutput(broken(), emitDeltas: false).forEach(seen.add),
        throwsStateError,
      );
      expect(seen.single.content, '已收到的内容');
    },
  );
  test(
    'streaming output keeps individual chunks and cancellation reason',
    () async {
      final events = [
        const AiStreamEvent.content('一'),
        const AiStreamEvent.content('二'),
        const AiStreamEvent.finished(AiFinishReason.cancelled),
      ];
      expect(
        await bufferAiOutput(
          Stream.fromIterable(events),
          emitDeltas: true,
        ).toList(),
        events,
      );
    },
  );
}
