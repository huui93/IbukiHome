import '../../core/errors/data_exceptions.dart';
import '../../domain/projects/novel_prompt_preset.dart';
import '../repositories/novel_prompt_preset_repository.dart';

class InMemoryNovelPromptPresetRepository
    implements NovelPromptPresetRepository {
  final _presets = <String, NovelPromptPreset>{};
  @override
  Future<List<NovelPromptPreset>> list() async => List.unmodifiable(
    _presets.values.where((p) => p.metadata.deletedAt == null).toList()
      ..sort((a, b) => b.metadata.updatedAt.compareTo(a.metadata.updatedAt)),
  );
  @override
  Future<void> save(NovelPromptPreset preset) async {
    final previous = _presets[preset.id];
    if ((previous?.metadata.revision ?? 0) != preset.metadata.revision - 1) {
      throw const DataConflictException('方案已改变，请重新打开后编辑。');
    }
    _presets[preset.id] = preset;
  }
}
