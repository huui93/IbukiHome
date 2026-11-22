import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/data_exceptions.dart';
import '../../data/memory/in_memory_novel_prompt_preset_repository.dart';
import '../../data/repositories/novel_prompt_preset_repository.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/projects/novel_prompt_preset.dart';
import '../providers/repository_providers.dart';

final novelPromptPresetRepositoryProvider =
    Provider<NovelPromptPresetRepository>(
      (ref) => InMemoryNovelPromptPresetRepository(),
    );
final novelPromptPresetsProvider = FutureProvider(
  (ref) => ref.watch(novelPromptPresetRepositoryProvider).list(),
);
final novelPromptPresetServiceProvider = Provider(
  (ref) => NovelPromptPresetService(ref),
);

class NovelPromptPresetService {
  const NovelPromptPresetService(this.ref);
  final Ref ref;
  Future<NovelPromptPreset> save({
    required String name,
    required String content,
    NovelPromptPreset? previous,
  }) async {
    if (name.trim().isEmpty) throw const DataFormatException('请填写方案名称。');
    final now = ref.read(utcClockProvider).now().toUtc();
    final metadata = previous == null
        ? EntityMetadata(
            id: ref.read(entityIdGeneratorProvider).nextId('novel-prompt'),
            createdAt: now,
            updatedAt: now,
            revision: 1,
          )
        : previous.metadata.copyWith(
            updatedAt: now,
            revision: previous.metadata.revision + 1,
          );
    final preset = NovelPromptPreset(
      metadata: metadata,
      name: name.trim(),
      content: content.trim(),
    );
    await ref.read(novelPromptPresetRepositoryProvider).save(preset);
    ref.invalidate(novelPromptPresetsProvider);
    return preset;
  }

  Future<void> delete(NovelPromptPreset preset) async {
    final now = ref.read(utcClockProvider).now().toUtc();
    await ref
        .read(novelPromptPresetRepositoryProvider)
        .save(
          NovelPromptPreset(
            metadata: preset.metadata.copyWith(
              updatedAt: now,
              deletedAt: now,
              revision: preset.metadata.revision + 1,
            ),
            name: preset.name,
            content: preset.content,
          ),
        );
    ref.invalidate(novelPromptPresetsProvider);
  }
}
