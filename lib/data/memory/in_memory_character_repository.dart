import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/character_repository.dart';
import '../../domain/characters/character_card.dart';
import 'in_memory_ibuki_store.dart';

class InMemoryCharacterRepository implements CharacterRepository {
  InMemoryCharacterRepository(this.store);

  final InMemoryIbukiStore store;

  @override
  Future<List<CharacterCard>> listCharacters(
    String projectId, {
    bool includeDeleted = false,
  }) async {
    final items =
        store.characters.where((character) {
          return character.projectId == projectId &&
              (includeDeleted || character.deletedAt == null);
        }).toList()..sort((left, right) {
          final order = left.sortOrder.compareTo(right.sortOrder);
          if (order != 0) {
            return order;
          }
          final time = left.updatedAt.compareTo(right.updatedAt);
          return time != 0 ? time : left.id.compareTo(right.id);
        });
    return List.unmodifiable(items);
  }

  @override
  Future<CharacterCard> getCharacter(String id) async {
    final character = store.character(id);
    if (character == null) {
      throw EntityNotFoundException('CharacterCard', id);
    }
    return character;
  }

  @override
  Future<void> upsertCharacter(CharacterCard character) async {
    _requireProject(character.projectId);
    final existing = store.character(character.id);
    if (existing != null && existing.projectId != character.projectId) {
      throw DataConflictException(
        'CharacterCard ${character.id} cannot move between projects.',
      );
    }
    store.putCharacter(character);
  }

  @override
  Future<void> softDeleteCharacter(String id, DateTime deletedAt) async {
    final character = await getCharacter(id);
    final deletedUtc = deletedAt.toUtc();
    store.putCharacter(
      character.copyWith(
        metadata: character.metadata.copyWith(
          updatedAt: deletedUtc,
          revision: character.revision + 1,
          deletedAt: deletedUtc,
        ),
      ),
    );
  }

  @override
  Future<void> restoreCharacter(String id, DateTime updatedAt) async {
    final character = await getCharacter(id);
    final updatedUtc = updatedAt.toUtc();
    store.putCharacter(
      character.copyWith(
        metadata: character.metadata.copyWith(
          updatedAt: updatedUtc,
          revision: character.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }

  @override
  Future<void> reorderCharacters({
    required String projectId,
    required List<String> orderedIds,
    required DateTime updatedAt,
  }) async {
    _requireProject(projectId);
    final active = await listCharacters(projectId);
    _validateOrderedIds(active, orderedIds);
    final updatedUtc = updatedAt.toUtc();
    for (var index = 0; index < orderedIds.length; index += 1) {
      final character = store.character(orderedIds[index])!;
      if (character.sortOrder == index) {
        continue;
      }
      store.putCharacter(
        character.copyWith(
          metadata: character.metadata.copyWith(
            updatedAt: updatedUtc,
            revision: character.revision + 1,
          ),
          sortOrder: index,
        ),
      );
    }
  }

  void _validateOrderedIds(
    List<CharacterCard> active,
    List<String> orderedIds,
  ) {
    final expected = active.map((item) => item.id).toSet();
    final provided = orderedIds.toSet();
    if (orderedIds.length != provided.length ||
        expected.length != provided.length ||
        !expected.containsAll(provided)) {
      throw const DataConflictException('角色排序必须包含当前项目的全部有效角色，且不能重复。');
    }
  }

  void _requireProject(String projectId) {
    if (!store.hasProject(projectId)) {
      throw EntityNotFoundException('Project', projectId);
    }
  }
}
