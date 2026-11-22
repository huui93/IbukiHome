import '../../data/repositories/character_repository.dart';
import '../../data/repositories/world_roleplay_repository.dart';
import '../../data/repositories/world_repository.dart';
import '../../data/repositories/tavern_repository.dart';
import '../../domain/tavern/tavern_models.dart';
import '../import/sillytavern_character_context.dart';
import '../world_roleplay/world_prompt_layer.dart';
import 'prompt/prompt_models.dart';
import 'world_info/world_info_models.dart';
import 'world_info/world_info_native_adapter.dart';

class TavernSourceBundle {
  const TavernSourceBundle({
    this.sources = const [],
    this.entries = const [],
    this.worldId,
    this.personaId,
    this.characterIds = const {},
  });
  final List<PromptSource> sources;
  final List<WorldInfoEntry> entries;
  final String? worldId, personaId;
  final Set<String> characterIds;
}

abstract class TavernSourceResolver {
  Future<TavernSourceBundle> resolve(
    TavernTranscriptProjection projection,
    String speakerId,
  );
}

class NativeTavernSourceResolver implements TavernSourceResolver {
  const NativeTavernSourceResolver({
    required this.repository,
    required this.characters,
    required this.worlds,
    this.compatibility,
    this.worldCards,
  });
  final TavernRepository repository;
  final CharacterRepository characters;
  final WorldRoleplayRepository worlds;
  final SillyTavernCharacterContextResolver? compatibility;
  final WorldRepository? worldCards;

  static PromptSource dataSource(
    String id,
    PromptSourceType type,
    String text, {
    bool required = false,
    PromptPlacementKind placement = PromptPlacementKind.beforeHistory,
  }) => PromptSource(
    id: id,
    type: type,
    origin: PromptOrigin('nativeAsset', id),
    role: PromptRoleIntent.context,
    placement: PromptPlacement(placement),
    atoms: [PromptAtom(id: '$id:text', kind: PromptAtomKind.text, text: text)],
    required: required,
    budgetClass: PromptBudgetClass.grounding,
  );

  @override
  Future<TavernSourceBundle> resolve(
    TavernTranscriptProjection projection,
    String speakerId,
  ) async {
    final participants = await repository.listParticipants(
      projection.session.id,
    );
    return resolveParticipants(projection, speakerId, participants);
  }

  Future<TavernSourceBundle> resolveParticipants(
    TavernTranscriptProjection projection,
    String speakerId,
    List<TavernParticipant> participants,
  ) async {
    final session = projection.session;
    final speaker = participants.where((p) => p.id == speakerId).firstOrNull;
    if (speaker == null ||
        speaker.kind != TavernParticipantKind.character ||
        speaker.entityId == null) {
      throw StateError('A native Character participant is required.');
    }
    final character = await characters.getCharacter(speaker.entityId!);
    if (character.deletedAt != null) throw StateError('Character is deleted.');
    final sources = <PromptSource>[
      dataSource(
        'character:${character.id}',
        PromptSourceType.character,
        'Current speaker: ${character.name}\n${character.content}',
        required: true,
      ),
    ];
    final books = <String, (int priority, bool enabled)>{};
    void reference(String bookId, int priority, bool enabled) {
      final old = books[bookId];
      books[bookId] = (
        old == null || priority > old.$1 ? priority : old.$1,
        enabled || old?.$2 == true,
      );
    }

    final worldId = session.worldAssetType == 'roleplayWorld'
        ? session.worldAssetId
        : null;
    if (session.worldAssetType == 'worldCard' &&
        session.worldAssetId != null &&
        worldCards != null) {
      final world = await worldCards!.getWorldCard(session.worldAssetId!);
      if (world.deletedAt != null) throw StateError('World card is deleted.');
      sources.add(
        dataSource(
          'world-card:${world.id}',
          PromptSourceType.scenario,
          '${world.title}\n${world.content}',
        ),
      );
    } else if (session.worldAssetId != null && worldId == null) {
      throw StateError('Unsupported World asset type.');
    }
    if (worldId != null) {
      final world = await worlds.getWorld(worldId);
      sources.add(
        dataSource(
          'world:$worldId',
          PromptSourceType.scenario,
          '${world.name}\n${world.description}\n${WorldPromptMetadata.worldSystemPrompt(world)}',
        ),
      );
      for (final ref in await worlds.listWorldBookReferences(worldId)) {
        reference(ref.worldBookId, ref.priority, ref.enabled);
      }
    }
    final characterIds = <String>{};
    for (final participant in participants) {
      if (participant.kind != TavernParticipantKind.character ||
          participant.entityId == null ||
          (participant.metadata['isPresent'] == false &&
              participant.id != speakerId)) {
        continue;
      }
      characterIds.add(participant.entityId!);
      for (final ref in await worlds.listCharacterWorldBookReferences(
        participant.entityId!,
      )) {
        reference(ref.worldBookId, ref.priority, ref.enabled);
      }
      if (participant.id != speakerId) {
        sources.add(
          dataSource(
            'participant:${participant.id}',
            PromptSourceType.scenario,
            'Present participant: ${participant.displayName}',
          ),
        );
      }
    }
    final personaId = session.personaType == 'playerPersona'
        ? session.personaId
        : null;
    if (session.personaId != null && personaId == null) {
      throw StateError('Unsupported Persona asset type.');
    }
    if (personaId != null) {
      final persona = await worlds.getPersona(personaId);
      final visibility = persona.metadata['knowledgeVisibility'];
      bool known(String key) {
        final value = visibility is Map ? visibility[key] : null;
        return value == 'public' ||
            (value == null &&
                const {'name', 'description', 'appearance'}.contains(key));
      }

      final text = [
        if (known('name')) persona.name,
        if (known('description')) persona.description,
        if (known('appearance')) persona.appearance,
        if (known('background')) persona.background,
        if (known('notes')) persona.notes,
      ].where((s) => s.isNotEmpty).join('\n');
      if (text.isNotEmpty) {
        sources.add(
          dataSource('persona:$personaId', PromptSourceType.persona, text),
        );
      }
      for (final ref in await worlds.listPersonaWorldBookReferences(
        personaId,
      )) {
        reference(ref.worldBookId, ref.priority, ref.enabled);
      }
    }
    final imported = await compatibility?.resolve(character.id);
    if (imported != null && !imported.isEmpty) {
      sources.add(
        dataSource(
          'character-style:${character.id}',
          PromptSourceType.exampleDialogue,
          '${imported.systemPrompt}\n${imported.exampleMessages}\n${imported.postHistoryInstructions}',
        ),
      );
    }
    final instructions = session.metadata['tavernSessionInstructionsV1'];
    if (instructions is String && instructions.isNotEmpty) {
      sources.add(
        dataSource(
          'session:${session.id}',
          PromptSourceType.authorNote,
          instructions,
        ),
      );
    }
    final scene = session.metadata['tavernSceneV1'];
    if (scene is Map) {
      sources.add(
        dataSource(
          'scene:${session.id}',
          PromptSourceType.scenario,
          ['name', 'description', 'timeText']
              .map((key) => scene[key])
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .join('\n'),
        ),
      );
    }
    final localBooks = session.metadata['tavernBookReferencesV1'];
    if (localBooks is Map) {
      for (final entry in localBooks.entries) {
        final value = entry.value;
        if (entry.key is String && value is Map && value['enabled'] == true) {
          reference(entry.key as String, value['priority'] as int? ?? 0, true);
        }
      }
    }
    final overrides = session.metadata['worldInfoBookOverridesV1'];
    final entries = <WorldInfoEntry>[];
    for (final bookId in books.keys.toList()..sort()) {
      final override = overrides is Map ? overrides[bookId] : null;
      if (override == 'disabled' ||
          (override != 'enabled' && !books[bookId]!.$2)) {
        continue;
      }
      final book = await worlds.getWorldBook(bookId);
      final lore = await worlds.listLoreEntries(bookId);
      entries.addAll(
        lore
            .where(
              (entry) =>
                  entry.scope != 'private' &&
                  entry.scope != 'directorOnly' &&
                  (entry.metadata['visibility'] == null ||
                      entry.metadata['visibility'] == 'public'),
            )
            .map(
              (entry) => const WorldInfoNativeAdapter().fromLoreEntry(
                entry,
                bookEnabled: book.metadata['enabled'] != false,
                referencePriority: books[bookId]!.$1,
                worldIds: worldId == null ? const {} : {worldId},
              ),
            ),
      );
    }
    return TavernSourceBundle(
      sources: sources,
      entries: entries,
      worldId: worldId,
      personaId: personaId,
      characterIds: characterIds,
    );
  }
}
