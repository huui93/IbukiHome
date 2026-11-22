import '../../application/import/sillytavern_import_plan.dart';
import '../../core/errors/data_exceptions.dart';
import '../../domain/import/external_compatibility_payload.dart';
import '../repositories/compatibility_import_repository.dart';
import '../repositories/world_roleplay_repository.dart';
import 'in_memory_ibuki_store.dart';

class InMemoryCompatibilityImportRepository
    implements CompatibilityImportRepository {
  InMemoryCompatibilityImportRepository({
    required this.coreStore,
    required this.worlds,
  });

  final InMemoryIbukiStore coreStore;
  final WorldRoleplayRepository worlds;
  final Map<String, ExternalCompatibilityPayload> _payloads = {};

  @override
  Future<List<ExternalCompatibilityPayload>> listPayloads() async {
    final items = _payloads.values.toList()
      ..sort((left, right) {
        final created = right.createdAt.compareTo(left.createdAt);
        return created != 0 ? created : left.id.compareTo(right.id);
      });
    return List.unmodifiable(
      items.map(
        (item) => item.copyWith(
          normalizedPayload: const {},
          unsupportedPayload: const {},
        ),
      ),
    );
  }

  @override
  Future<ExternalCompatibilityPayload> getPayload(String id) async {
    final payload = _payloads[id];
    if (payload == null) {
      throw EntityNotFoundException('ExternalCompatibilityPayload', id);
    }
    return payload;
  }

  @override
  Future<List<ExternalCompatibilityPayload>> findBySourceSha256(
    String sha256,
  ) async {
    return List.unmodifiable(
      _payloads.values
          .where((item) => item.sourceSha256 == sha256)
          .map(
            (item) => item.copyWith(
              normalizedPayload: const {},
              unsupportedPayload: const {},
            ),
          ),
    );
  }

  @override
  Future<List<ExternalCompatibilityPayload>> listForEntity(
    String linkedEntityType,
    String linkedEntityId,
  ) async {
    return List.unmodifiable(
      _payloads.values
          .where(
            (item) =>
                item.linkedEntityType == linkedEntityType &&
                item.linkedEntityId == linkedEntityId,
          )
          .map((item) => item.copyWith(unsupportedPayload: const {})),
    );
  }

  @override
  Future<void> commitImport(SillyTavernImportWrite write) async {
    if (_payloads.containsKey(write.payload.id)) {
      throw DataConflictException(
        'Compatibility payload ${write.payload.id} already exists.',
      );
    }
    final character = write.character;
    if (character != null) {
      if (!coreStore.hasProject(character.projectId) &&
          write.project?.id != character.projectId) {
        throw EntityNotFoundException('Project', character.projectId);
      }
      if (coreStore.hasCharacter(character.id)) {
        throw DataConflictException('CharacterCard ${character.id} exists.');
      }
    }
    final oldWorld = write.updatedWorld == null
        ? null
        : await worlds.getWorld(write.updatedWorld!.id);
    final oldSession = write.updatedSession == null
        ? null
        : await worlds.getSession(write.updatedSession!.id);
    if ((oldWorld != null &&
            oldWorld.entity.revision !=
                write.updatedWorld!.entity.revision - 1) ||
        (oldSession != null &&
            oldSession.entity.revision !=
                write.updatedSession!.entity.revision - 1)) {
      throw const DataConflictException('故事设置已变化，请重新预览后导入。');
    }
    var characterInserted = false;
    var projectInserted = false;
    var bookInserted = false;
    var personaInserted = false;
    var worldReferenceInserted = false;
    var characterReferenceInserted = false;
    final insertedLoreIds = <String>[];
    try {
      if (write.project != null) {
        if (coreStore.hasProject(write.project!.id)) {
          throw const DataConflictException('Project already exists.');
        }
        coreStore.putProject(write.project!);
        projectInserted = true;
      }
      if (character != null) {
        coreStore.putCharacter(character);
        characterInserted = true;
      }
      if (write.worldBook != null) {
        await worlds.upsertWorldBook(write.worldBook!);
        bookInserted = true;
      }
      for (final entry in write.loreEntries) {
        await worlds.upsertLoreEntry(entry);
        insertedLoreIds.add(entry.id);
      }
      if (write.worldBookReference != null) {
        await worlds.upsertWorldBookReference(write.worldBookReference!);
        worldReferenceInserted = true;
      }
      if (write.characterBookReference != null) {
        await worlds.upsertCharacterWorldBookReference(
          write.characterBookReference!,
        );
        characterReferenceInserted = true;
      }
      if (write.persona != null) {
        await worlds.upsertPersona(write.persona!);
        personaInserted = true;
      }
      if (write.updatedWorld != null) {
        await worlds.upsertWorld(write.updatedWorld!);
      }
      if (write.updatedSession != null) {
        await worlds.upsertSession(write.updatedSession!);
      }
      _payloads[write.payload.id] = write.payload;
    } catch (_) {
      _payloads.remove(write.payload.id);
      if (write.updatedSession != null && oldSession != null) {
        await worlds.upsertSession(oldSession);
      }
      if (write.updatedWorld != null && oldWorld != null) {
        await worlds.upsertWorld(oldWorld);
      }
      if (personaInserted) await worlds.deletePersona(write.persona!.id);
      if (characterReferenceInserted) {
        await worlds.deleteCharacterWorldBookReference(
          write.characterBookReference!.id,
        );
      }
      if (worldReferenceInserted) {
        await worlds.deleteWorldBookReference(write.worldBookReference!.id);
      }
      for (final id in insertedLoreIds.reversed) {
        await worlds.deleteLoreEntry(id);
      }
      if (bookInserted) await worlds.deleteWorldBook(write.worldBook!.id);
      if (characterInserted) coreStore.removeCharacter(character!.id);
      if (projectInserted) coreStore.removeProject(write.project!.id);
      rethrow;
    }
  }

  @override
  Future<void> deletePayload(String id) async {
    if (_payloads.remove(id) == null) {
      throw EntityNotFoundException('ExternalCompatibilityPayload', id);
    }
  }
}
