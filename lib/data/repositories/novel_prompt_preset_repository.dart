import '../../domain/projects/novel_prompt_preset.dart';

abstract interface class NovelPromptPresetRepository {
  Future<List<NovelPromptPreset>> list();

  /// Inserts revision 1, or replaces exactly the preceding revision.
  Future<void> save(NovelPromptPreset preset);
}
