import '../../data/repositories/character_repository.dart';
import '../../domain/characters/character_card.dart';

class ReorderCharacterCards {
  const ReorderCharacterCards(this._characters);

  final CharacterRepository _characters;

  Future<List<CharacterCard>> call({
    required String projectId,
    required List<String> orderedIds,
    required DateTime nowUtc,
  }) async {
    await _characters.reorderCharacters(
      projectId: projectId,
      orderedIds: List.unmodifiable(orderedIds),
      updatedAt: nowUtc.toUtc(),
    );
    return _characters.listCharacters(projectId);
  }
}
