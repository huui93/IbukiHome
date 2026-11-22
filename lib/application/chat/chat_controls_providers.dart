import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/memory/in_memory_chat_controls_repository.dart';
import '../../data/repositories/chat_controls_repository.dart';
import '../providers/repository_providers.dart';
import 'chat_usage_tracker.dart';

final chatControlsRepositoryProvider = Provider<ChatControlsRepository>(
  (ref) =>
      InMemoryChatControlsRepository(ref.watch(inMemoryIbukiStoreProvider)),
);
final chatReasoningLevelProvider = FutureProvider.family(
  (ref, String sessionId) =>
      ref.watch(chatControlsRepositoryProvider).getReasoning(sessionId),
);
final chatSessionUsageProvider = FutureProvider.family(
  (ref, String sessionId) =>
      ref.watch(chatControlsRepositoryProvider).listUsage(sessionId),
);
final chatUsageTrackerProvider = Provider(
  (ref) => ChatUsageTracker(
    ref.watch(chatControlsRepositoryProvider),
    onChanged: (sessionId) {
      if (ref.mounted) ref.invalidate(chatSessionUsageProvider(sessionId));
    },
  ),
);
