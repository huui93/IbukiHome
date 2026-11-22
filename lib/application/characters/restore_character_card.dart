import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/character_repository.dart';
import '../../domain/characters/character_card.dart';

class RestoreCharacterCard {
  const RestoreCharacterCard(this._characters);

  final CharacterRepository _characters;

  Future<CharacterCard> call({
    required String projectId,
    required String characterId,
    required DateTime nowUtc,
  }) async {
    final stored = await _characters.getCharacter(characterId);
    if (stored.projectId != projectId) {
      throw const DataConflictException('角色不属于当前项目。');
    }
    if (stored.deletedAt == null) {
      return stored;
    }
    await _characters.restoreCharacter(characterId, nowUtc.toUtc());
    return _characters.getCharacter(characterId);
  }
}
