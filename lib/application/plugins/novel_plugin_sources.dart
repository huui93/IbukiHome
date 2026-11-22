import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/compatibility_import_repository.dart';
import '../../data/repositories/world_roleplay_repository.dart';
import '../../domain/plugins/novel_history_fingerprint.dart';
import '../../domain/plugins/novel_plugin_models.dart';
import '../ai/novel_context_loader.dart';
import '../tavern/prompt/prompt_models.dart';
import '../tavern/world_info/world_info_models.dart';
import '../tavern/world_info/world_info_native_adapter.dart';
import '../tavern/world_info/world_info_runtime.dart';

class NovelPluginSources {
  const NovelPluginSources(this.imports, this.worlds);
  final CompatibilityImportRepository imports;
  final WorldRoleplayRepository worlds;

  Future<
    ({
      Map<String, String> variables,
      Map<String, String> placeholders,
      List<String> activated,
    })
  >
  resolve({
    required NovelAiContext context,
    required Map<String, Object?> settings,
    required List<NovelHistoryMessage> history,
    required List<NovelMemoryBlock> memories,
    required String input,
    required String requestId,
    required NovelGenerationMode mode,
    required DateTime now,
    String? speakerId,
  }) async {
    final cards = context.characters;
    final primary = speakerId == null
        ? cards.firstOrNull
        : cards.where((c) => c.id == speakerId).firstOrNull;
    if (speakerId != null && primary == null) {
      throw const DataConflictException('所选发言角色不在本轮角色中。');
    }
    final definitions = <String>[];
    final examples = <String>[];
    final bookIds = {
      for (final id in (settings['worldBookIds'] as List? ?? const []))
        if (id is String) id,
    };
    var personality = '';
    var greeting = '';
    final extraScenario = <String>[];
    final author = Map<String, Object?>.from(
      settings['variables'] as Map? ?? const {},
    );
    String value(Object? raw) => raw is String ? raw.trim() : '';
    for (final card in cards) {
      // A fork retains the source payload ID while cloning its own editable card.
      final payload = card.compatibilityPayloadId == null
          ? (await imports.listForEntity('characterCard', card.id)).firstOrNull
          : await imports.getPayload(card.compatibilityPayloadId!);
      final data = payload?.normalizedPayload ?? const {};
      definitions.add(
        [
          '【${card.name}】',
          card.content,
          if (card.fanficAdaptationNotes.isNotEmpty) card.fanficAdaptationNotes,
          value(data['systemPrompt']),
        ].where((s) => s.trim().isNotEmpty).join('\n'),
      );
      if (value(data['exampleMessages']).isNotEmpty) {
        examples.add('【${card.name}】\n${data['exampleMessages']}');
      }
      if (card == primary) {
        personality = value(data['personality']);
        greeting = value(data['firstMessage']);
        if (value(data['scenario']).isNotEmpty) {
          extraScenario.add(value(data['scenario']));
        }
      }
      for (final id in {card.id, if (payload != null) payload.linkedEntityId}) {
        for (final reference in await worlds.listCharacterWorldBookReferences(
          id,
        )) {
          if (reference.enabled) bookIds.add(reference.worldBookId);
        }
      }
    }
    final user = value(author['user']).isEmpty ? '作者' : value(author['user']);
    final scenario = [
      context.project.description.trim(),
      ...extraScenario,
      value(author['scenario']),
    ].where((s) => s.isNotEmpty).join('\n');
    final early = [
      for (final card in context.worldCards) '【${card.title}】\n${card.content}',
    ];
    final late = <String>[];
    final activated = <String>[];
    if (bookIds.isNotEmpty) {
      final entries = <WorldInfoEntry>[];
      for (final id in bookIds) {
        final book = await worlds.getWorldBook(id);
        if (book.entity.deletedAt != null ||
            book.metadata['enabled'] == false) {
          continue;
        }
        for (final item in await worlds.listLoreEntries(id)) {
          if (item.scope == 'private' ||
              item.scope == 'directorOnly' ||
              (item.metadata['visibility'] != null &&
                  item.metadata['visibility'] != 'public')) {
            continue;
          }
          entries.add(
            const WorldInfoNativeAdapter().fromLoreEntry(
              item,
              bookEnabled: true,
            ),
          );
        }
      }
      final projectId = context.project.id;
      final plan = const WorldInfoRuntime().evaluate(
        entries: entries,
        context: WorldInfoActivationContext(
          sessionId: projectId,
          storyLineId: projectId,
          generationType: switch (mode) {
            NovelGenerationMode.regenerate =>
              WorldInfoGenerationType.regenerate,
            NovelGenerationMode.continueReply =>
              WorldInfoGenerationType.continueTurn,
            _ => WorldInfoGenerationType.normal,
          },
          messages: [
            for (final message in history)
              WorldInfoScanMessage(turnId: message.id, text: message.content),
            for (final memory in memories)
              if (memory.scanForWorldInfo)
                WorldInfoScanMessage(
                  turnId: 'memory:${memory.id}',
                  text: memory.content,
                ),
            if (input.trim().isNotEmpty)
              WorldInfoScanMessage(turnId: 'author', text: input),
          ],
          historyMarker: novelRefsFingerprint(novelSourceRefs(history)),
          characterIds: cards.map((c) => c.id).toSet(),
          additionalScanText: {
            WorldInfoAdditionalScanSource.characterDescription: definitions
                .join('\n'),
            WorldInfoAdditionalScanSource.characterPersonality: personality,
            WorldInfoAdditionalScanSource.scenario: scenario,
            WorldInfoAdditionalScanSource.personaDescription: value(
              author['persona'],
            ),
          },
        ),
        state: WorldInfoRuntimeState(
          sessionId: projectId,
          storyLineId: projectId,
        ),
        random: SeededWorldInfoRandom(requestId.hashCode),
      );
      for (final item in plan.promptSources) {
        final text = item.atoms
            .map((a) => a.text)
            .whereType<String>()
            .join('\n');
        final list =
            const {
              PromptPlacementKind.afterHistory,
              PromptPlacementKind.tail,
            }.contains(item.placement.kind)
            ? late
            : early;
        if (text.isNotEmpty) list.add(text);
      }
      activated.addAll(plan.activated.map((id) => '${id.$1}:${id.$2}'));
    }
    final date = now.toLocal().toIso8601String();
    return (
      variables: {
        'user': user,
        'char': primary?.name ?? '故事角色',
        'group': cards.map((c) => c.name).join('、'),
        'scenario': scenario,
        'personality': personality,
        'date': date.substring(0, 10),
        'time': date.substring(11, 16),
      },
      placeholders: {
        'charDescription': definitions.join('\n\n'),
        'charPersonality': personality,
        'scenario': scenario,
        'personaDescription': value(author['persona']),
        'worldInfoBefore': early.join('\n\n'),
        'worldInfoAfter': late.join('\n\n'),
        'dialogueExamples': examples.join('\n\n'),
        'opening': greeting,
      },
      activated: activated,
    );
  }
}
