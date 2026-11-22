import '../../domain/characters/character_card.dart';

abstract class CharacterRepository {
  Future<List<CharacterCard>> listCharacters(
    String projectId, {
    bool includeDeleted = false,
  });

  Future<CharacterCard> getCharacter(String id);

  Future<void> upsertCharacter(CharacterCard character);

  Future<void> softDeleteCharacter(String id, DateTime deletedAt);

  Future<void> restoreCharacter(String id, DateTime updatedAt);

  Future<void> reorderCharacters({
    required String projectId,
    required List<String> orderedIds,
    required DateTime updatedAt,
  });
}
