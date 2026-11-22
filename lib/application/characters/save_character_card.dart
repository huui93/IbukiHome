import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/character_repository.dart';
import '../../domain/characters/character_card.dart';

class SaveCharacterCard {
  const SaveCharacterCard(this._characters);

  final CharacterRepository _characters;

  Future<CharacterCard> call({
    required String projectId,
    required String characterId,
    required String name,
    required String content,
    required DateTime nowUtc,
    CharacterCardMode? mode,
    String? sourceWorkTitle,
    String? sourceCharacterName,
    String? sourceVersionHint,
    String? fanficAdaptationNotes,
    String? originalIdea,
  }) async {
    final stored = await _characters.getCharacter(characterId);
    if (stored.projectId != projectId) {
      throw const DataConflictException('角色不属于当前项目。');
    }
    if (stored.deletedAt != null) {
      throw const DataConflictException('已删除的角色不能编辑。');
    }
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const DataFormatException('角色名称不能为空。');
    }
    final nextMode = mode ?? stored.mode;
    final nextWork = (sourceWorkTitle ?? stored.sourceWorkTitle).trim();
    final nextSourceName = (sourceCharacterName ?? stored.sourceCharacterName)
        .trim();
    if (nextMode == CharacterCardMode.fanfic &&
        (nextWork.isEmpty || nextSourceName.isEmpty)) {
      throw const DataFormatException('同人角色必须填写作品名称和角色名称。');
    }
    final nextVersion = (sourceVersionHint ?? stored.sourceVersionHint).trim();
    final nextAdaptation =
        (fanficAdaptationNotes ?? stored.fanficAdaptationNotes).trim();
    final nextIdea = (originalIdea ?? stored.originalIdea).trim();
    if (stored.name == normalizedName &&
        stored.content == content &&
        stored.mode == nextMode &&
        stored.sourceWorkTitle == nextWork &&
        stored.sourceCharacterName == nextSourceName &&
        stored.sourceVersionHint == nextVersion &&
        stored.fanficAdaptationNotes == nextAdaptation &&
        stored.originalIdea == nextIdea) {
      return stored;
    }
    final updated = stored.copyWith(
      metadata: stored.metadata.copyWith(
        updatedAt: nowUtc.toUtc(),
        revision: stored.revision + 1,
      ),
      name: normalizedName,
      content: content,
      mode: nextMode,
      sourceWorkTitle: nextWork,
      sourceCharacterName: nextSourceName,
      sourceVersionHint: nextVersion,
      fanficAdaptationNotes: nextAdaptation,
      originalIdea: nextIdea,
    );
    await _characters.upsertCharacter(updated);
    return updated;
  }
}
