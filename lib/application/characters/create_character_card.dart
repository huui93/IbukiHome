import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/character_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../domain/characters/character_card.dart';
import '../../domain/common/entity_metadata.dart';

class CreateCharacterCard {
  const CreateCharacterCard(this._projects, this._characters);

  final ProjectRepository _projects;
  final CharacterRepository _characters;

  Future<CharacterCard> call({
    required String projectId,
    required String name,
    required String content,
    required String id,
    required DateTime nowUtc,
    CharacterCardMode? mode,
    String sourceWorkTitle = '',
    String sourceCharacterName = '',
    String sourceVersionHint = '',
    String fanficAdaptationNotes = '',
    String originalIdea = '',
    String? avatarReference,
    String sourceFormat = '',
    String? compatibilityPayloadId,
  }) async {
    final project = await _projects.getProject(projectId);
    if (project.deletedAt != null) {
      throw const DataConflictException('项目已删除，不能新建角色。');
    }
    final normalizedName = name.trim();
    if (normalizedName.isEmpty && mode == null) {
      throw const DataFormatException('角色名称不能为空。');
    }
    if (mode == CharacterCardMode.fanfic &&
        (sourceWorkTitle.trim().isEmpty ||
            sourceCharacterName.trim().isEmpty)) {
      throw const DataFormatException('同人角色必须填写作品名称和角色名称。');
    }
    final active = await _characters.listCharacters(projectId);
    final nextOrder = active.isEmpty
        ? 0
        : active
                  .map((character) => character.sortOrder)
                  .reduce((left, right) => left > right ? left : right) +
              1;
    final now = nowUtc.toUtc();
    final character = CharacterCard(
      metadata: EntityMetadata(
        id: id,
        createdAt: now,
        updatedAt: now,
        revision: 1,
      ),
      projectId: projectId,
      name: normalizedName.isEmpty
          ? mode == CharacterCardMode.fanfic
                ? sourceCharacterName.trim()
                : '未命名角色'
          : normalizedName,
      content: content,
      sortOrder: nextOrder,
      mode: mode,
      sourceWorkTitle: sourceWorkTitle.trim(),
      sourceCharacterName: sourceCharacterName.trim(),
      sourceVersionHint: sourceVersionHint.trim(),
      fanficAdaptationNotes: fanficAdaptationNotes.trim(),
      originalIdea: originalIdea.trim(),
      avatarReference: avatarReference,
      sourceFormat: sourceFormat,
      compatibilityPayloadId: compatibilityPayloadId,
    );
    await _characters.upsertCharacter(character);
    return character;
  }
}
