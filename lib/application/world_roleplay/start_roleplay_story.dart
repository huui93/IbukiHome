import '../../data/repositories/world_roleplay_repository.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/world_roleplay/world_roleplay_models.dart';
import '../import/sillytavern_import_plan.dart';
import '../import/sillytavern_import_service.dart';
import 'world_roleplay_service.dart';

class StartRoleplayStory {
  const StartRoleplayStory({required this.worlds, required this.imports});

  final WorldRoleplayService worlds;
  final SillyTavernImportService imports;

  WorldRoleplayRepository get repository => worlds.repository;

  Future<WorldSession> call({
    String? worldId,
    required String worldName,
    String worldDescription = '',
    String? personaId,
    String personaName = '',
    String personaDescription = '',
    SillyTavernStoryImport? personaImport,
    SillyTavernStoryImport? lorebookImport,
    required Set<String> characterCardIds,
    Set<String>? worldBookIds,
    required String sceneName,
    String location = '',
    String timeText = '',
    String atmosphere = '',
  }) async {
    if (characterCardIds.isEmpty) throw ArgumentError('请至少选择一个登场角色。');
    RoleplayWorld? createdWorld;
    WorldSession? session;
    PlayerPersona? createdPersona;
    final imported = <SillyTavernImportResult>[];
    try {
      late RoleplayWorld world;
      if (worldId == null) {
        final result = await worlds.createWorld(
          name: worldName,
          description: worldDescription,
        );
        createdWorld = world = result.world;
        session = result.session;
      } else {
        world = await repository.getWorld(worldId);
        session = await worlds.createWorldSession(
          worldId: worldId,
          name: '${world.name} · 新故事',
        );
      }
      PlayerPersona persona;
      if (personaImport != null) {
        final result = await _import(personaImport, world.id);
        imported.add(result);
        persona = result.persona!;
      } else if (personaId != null) {
        final source = await repository.getPersona(personaId);
        if (source.worldId == world.id) {
          persona = source;
        } else {
          persona = await worlds.createPersona(
            worldId: world.id,
            name: source.name,
            description: source.description,
            appearance: source.appearance,
            background: source.background,
            notes: source.notes,
            avatarReference: source.avatarReference,
            metadata: source.metadata,
          );
          createdPersona = persona;
        }
      } else {
        persona = await worlds.createPersona(
          worldId: world.id,
          name: personaName,
          description: personaDescription,
        );
        createdPersona = persona;
      }
      if (lorebookImport != null) {
        imported.add(await _import(lorebookImport, world.id));
      }
      final books = await repository.listWorldBooks(world.id);
      final references = await repository.listWorldBookReferences(world.id);
      final availableBookIds = {
        ...books.map((book) => book.id),
        ...references.map((reference) => reference.worldBookId),
      };
      final selectedBooks = worldBookIds == null
          ? availableBookIds
          : {...worldBookIds};
      if (!selectedBooks.every(availableBookIds.contains)) {
        throw ArgumentError('所选世界书未被当前世界引用。');
      }
      if (worldBookIds != null) {
        final now = worlds.clock.now();
        for (final reference in references) {
          await repository.upsertWorldBookOverride(
            WorldSessionWorldBookOverride(
              entity: EntityMetadata(
                id: worlds.ids.nextId('world_book_override'),
                createdAt: now,
                updatedAt: now,
                revision: 1,
              ),
              worldSessionId: session.id,
              worldBookId: reference.worldBookId,
              mode: selectedBooks.contains(reference.worldBookId)
                  ? WorldBookOverrideMode.enabled
                  : WorldBookOverrideMode.disabled,
            ),
          );
        }
      }
      await worlds.activatePlayerPersona(
        worldSessionId: session.id,
        playerPersonaId: persona.id,
      );
      final castIds = <String>{};
      for (final cardId in characterCardIds) {
        final instance = await worlds.addCharacterToWorld(
          worldSessionId: session.id,
          characterCardId: cardId,
        );
        castIds.add(instance.id);
      }
      final scene = await worlds.createScene(
        worldSessionId: session.id,
        name: sceneName.trim().isEmpty ? '初始场景' : sceneName,
        location: location,
        timeText: timeText,
        atmosphere: atmosphere,
      );
      await worlds.setCurrentScene(
        worldSessionId: session.id,
        sceneId: scene.id,
        presentCharacterInstanceIds: castIds,
      );
      final ready = (await repository.getSession(session.id)).copyWith(
        metadata: {
          ...session.metadata,
          'worldBookIds': selectedBooks.toList(growable: false),
        },
      );
      await repository.upsertSession(ready);
      return ready;
    } catch (_) {
      // Remove only rows created by this attempt. Existing templates and stories
      // remain untouched; each individual asset import is transactional as well.
      if (session != null) await repository.deleteSession(session.id);
      for (final result in imported.reversed) {
        if (result.characterBookReference != null) {
          await repository.deleteCharacterWorldBookReference(
            result.characterBookReference!.id,
          );
        }
        if (result.worldBookReference != null) {
          await repository.deleteWorldBookReference(
            result.worldBookReference!.id,
          );
        }
        if (result.persona != null) {
          await repository.deletePersona(result.persona!.id);
        }
        if (result.worldBook != null) {
          await repository.deleteWorldBook(result.worldBook!.id);
        }
        await imports.repository.deletePayload(result.payload.id);
      }
      if (createdPersona != null) {
        await repository.deletePersona(createdPersona.id);
      }
      if (createdWorld != null) await repository.deleteWorld(createdWorld.id);
      rethrow;
    }
  }

  Future<SillyTavernImportResult> _import(
    SillyTavernStoryImport selection,
    String worldId,
  ) async {
    final plan = await imports.buildPlan(
      inspection: selection.inspection,
      destination: SillyTavernImportDestination(
        worldId: worldId,
        personaVisibility: selection.personaVisibility,
        allowDuplicateSource: selection.allowDuplicateSource,
      ),
    );
    return imports.execute(plan);
  }
}
