import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/memory/in_memory_novel_output_limits_repository.dart';
import '../../data/repositories/novel_output_limits_repository.dart';
import '../providers/repository_providers.dart';

final novelOutputLimitsRepositoryProvider =
    Provider<NovelOutputLimitsRepository>(
      (ref) => InMemoryNovelOutputLimitsRepository(
        ref.watch(projectRepositoryProvider),
      ),
    );
final novelOutputLimitsProvider = FutureProvider.family(
  (ref, String projectId) =>
      ref.watch(novelOutputLimitsRepositoryProvider).get(projectId),
);
