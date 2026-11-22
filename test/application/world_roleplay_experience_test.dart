import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/application/world_roleplay/world_context_builder.dart';
import 'package:ibukihome/application/world_roleplay/world_lore_activator.dart';
import 'package:ibukihome/application/world_roleplay/world_roleplay_experience.dart';
import 'package:ibukihome/application/world_roleplay/world_roleplay_service.dart';
import 'package:ibukihome/data/memory/in_memory_character_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_world_roleplay_repository.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_engine_models.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_models.dart';

void main() {
  test('feed entries form stable visual groups by persisted turn id', () {
    final entries = [
      _feed('user-a', 'turn-a', WorldFeedEntryType.userAction),
      _feed('narration-a', 'turn-a', WorldFeedEntryType.narration),
      _feed('speech-a', 'turn-a', WorldFeedEntryType.characterSpeech),
      _feed('legacy', null, WorldFeedEntryType.systemEvent),
    ];
    final turn = _turn('turn-a', 'user-a');
    final groups = groupWorldFeedByTurn(entries: entries, turns: [turn]);

    expect(groups, hasLength(2));
    expect(groups.first.entries.map((entry) => entry.id), [
      'user-a',
      'narration-a',
      'speech-a',
    ]);
    expect(groups.first.turn, same(turn));
    expect(groups.last.id, 'legacy:legacy');
  });

  test(
    'turn experience exposes lore, world changes, and bounded diagnostics',
    () {
      final turn = WorldTurn(
        entity: _meta('turn-summary'),
        worldSessionId: 'session',
        branchId: 'branch',
        userFeedEntryId: 'user',
        status: WorldTurnStatus.completed,
        mutationProposal: const WorldMutationProposal(
          operations: [
            WorldMutationOperation(
              type: WorldMutationType.worldTimeUpdate,
              values: {'worldTime': 'Day 18 · 20:31'},
            ),
            WorldMutationOperation(type: WorldMutationType.relationshipUpsert),
          ],
          memories: [WorldMemoryCandidate(summary: '玩家送出一个蛋糕。')],
          timelineEvents: [WorldTimelineCandidate(title: '食堂的礼物')],
        ).toJson(),
        metadata: const {
          'activatedLoreEntryIds': ['lore-a', 'lore-b'],
          'manualLoreEntryIds': ['lore-b'],
          'contextDiagnostics': {
            'selectedCharacterCount': 3,
            'selectedMemoryCount': 8,
            'selectedTimelineCount': 5,
            'selectedStateCount': 12,
            'estimatedTokensBySection': {'scene': 120, 'recentFeed': 420},
          },
        },
      );

      final summary = WorldTurnExperienceSummary.fromTurn(turn);
      expect(summary.activatedLoreEntryIds, ['lore-a', 'lore-b']);
      expect(summary.manualLoreEntryIds, ['lore-b']);
      expect(summary.changes, contains('时间推进至 Day 18 · 20:31'));
      expect(summary.changes, contains('人物关系发生变化'));
      expect(summary.memories, ['玩家送出一个蛋糕。']);
      expect(summary.timelineEvents, ['食堂的礼物']);
      expect(summary.selectedCharacterCount, 3);
      expect(summary.estimatedContextTokens, 540);
    },
  );

  test('friendly world errors keep technical detail behind a safe summary', () {
    final result = presentWorldError(
      const WorldEngineException(
        WorldEngineErrorCategory.directorError,
        'invalid director JSON',
        detail: 'requestId=world-1',
      ),
    );
    expect(result.summary, '世界没有成功理解这次行动。');
    expect(result.actionLabel, '重试');
    expect(result.detail, contains('directorError'));
    expect(result.detail, contains('requestId=world-1'));
  });

  test('pinned lore wins budget before higher priority unpinned lore', () {
    const activator = WorldLoreActivator();
    final pinned = LoreEntry(
      entity: _meta('pinned'),
      worldBookId: 'book',
      title: '固定设定',
      content: '固定',
      priority: 1,
      activationMode: LoreActivationMode.always,
      tokenBudgetHint: 2,
      metadata: const {'pinned': true},
    );
    final highPriority = LoreEntry(
      entity: _meta('priority'),
      worldBookId: 'book',
      title: '高优先级',
      content: '高优先级',
      priority: 99,
      activationMode: LoreActivationMode.always,
      tokenBudgetHint: 2,
    );
    final result = activator.activate(
      entries: [highPriority, pinned],
      searchTexts: const ['继续'],
      tokenBudget: 2,
    );

    expect(result.entries.single.id, pinned.id);
    expect(result.entries.single.isPinned, isTrue);
  });

  test(
    'alternate branch inherits only to its point and preserves parent',
    () async {
      final fixture = await _seedExperienceWorld();
      final repository = fixture.repository;
      final parentBefore = await repository.listFeedEntries(
        fixture.sessionId,
        branchId: fixture.branchId,
      );
      final point = parentBefore[2];
      final child = await fixture.service.createWorldBranch(
        worldSessionId: fixture.sessionId,
        name: '另一种发展',
        parentBranchId: fixture.branchId,
        branchPointMessageId: point.id,
        makeCurrent: true,
      );
      await repository.upsertFeedEntry(
        WorldFeedEntry(
          entity: _meta('child-action'),
          worldSessionId: fixture.sessionId,
          branchId: child.id,
          type: WorldFeedEntryType.userAction,
          content: '换一种做法。',
        ),
      );

      final parentAfter = await repository.listFeedEntries(
        fixture.sessionId,
        branchId: fixture.branchId,
      );
      final childFeed = await repository.listFeedEntries(
        fixture.sessionId,
        branchId: child.id,
      );
      expect(
        parentAfter.map((entry) => entry.id),
        parentBefore.map((entry) => entry.id),
      );
      expect(childFeed.map((entry) => entry.id), [
        ...parentBefore.take(3).map((entry) => entry.id),
        'child-action',
      ]);
    },
  );

  test(
    'reenacting the first turn can start with no inherited parent feed',
    () async {
      final fixture = await _seedExperienceWorld();
      final child = await fixture.service.createWorldBranch(
        worldSessionId: fixture.sessionId,
        name: '首回合另一种发展',
        parentBranchId: fixture.branchId,
        inheritParentFeed: false,
      );

      expect(
        await fixture.repository.listFeedEntries(
          fixture.sessionId,
          branchId: child.id,
        ),
        isEmpty,
      );
      expect(
        await fixture.repository.listFeedEntries(
          fixture.sessionId,
          branchId: fixture.branchId,
        ),
        hasLength(150),
      );
    },
  );

  test('50 mixed turns keep context and selected history bounded', () async {
    final fixture = await _seedExperienceWorld();
    final snapshot = await fixture.contextBuilder.build(
      worldSessionId: fixture.sessionId,
      userAction: '继续这个世界。',
    );
    final allFeed = await fixture.repository.listFeedEntries(
      fixture.sessionId,
      branchId: fixture.branchId,
    );
    final turns = await fixture.repository.listTurns(fixture.sessionId);
    final groups = groupWorldFeedByTurn(entries: allFeed, turns: turns);

    expect(groups, hasLength(50));
    expect(snapshot.recentFeed, hasLength(24));
    expect(snapshot.memories.length, lessThanOrEqualTo(12));
    expect(snapshot.timeline.length, lessThanOrEqualTo(10));
    expect(snapshot.stateEntries.length, lessThanOrEqualTo(40));
    expect(
      snapshot.context.diagnostics.estimatedTokensBySection['recentFeed'],
      lessThan(2000),
    );
  });
}

Future<_ExperienceFixture> _seedExperienceWorld() async {
  final core = InMemoryIbukiStore();
  final repository = InMemoryWorldRoleplayRepository(core);
  final service = WorldRoleplayService(
    repository: repository,
    ids: EntityIdGenerator(),
    clock: const UtcClock(),
  );
  final created = await service.createWorld(name: 'Experience World');
  final card = CharacterCard(
    metadata: _meta('card'),
    projectId: 'project',
    name: 'Mira',
    content: '角色定义',
    sortOrder: 0,
  );
  core.putCharacter(card);
  final character = await service.addCharacterToWorld(
    worldSessionId: created.session.id,
    characterCardId: card.id,
  );
  final scene = await service.createScene(
    worldSessionId: created.session.id,
    name: '食堂',
  );
  await service.setCurrentScene(
    worldSessionId: created.session.id,
    sceneId: scene.id,
    presentCharacterInstanceIds: {character.id},
  );
  for (var index = 0; index < 50; index += 1) {
    final turnId = 'turn-${index.toString().padLeft(2, '0')}';
    final userId = '$turnId-user';
    final narrationId = '$turnId-narration';
    final speechId = '$turnId-speech';
    for (final entry in [
      WorldFeedEntry(
        entity: _meta(userId),
        worldSessionId: created.session.id,
        branchId: created.branch.id,
        type: WorldFeedEntryType.userAction,
        content: '第 $index 回合的行动。',
        metadata: {'turnId': turnId},
      ),
      WorldFeedEntry(
        entity: _meta(narrationId),
        worldSessionId: created.session.id,
        branchId: created.branch.id,
        type: WorldFeedEntryType.narration,
        content: '第 $index 回合的场景变化。',
        metadata: {'turnId': turnId},
      ),
      WorldFeedEntry(
        entity: _meta(speechId),
        worldSessionId: created.session.id,
        branchId: created.branch.id,
        type: WorldFeedEntryType.characterSpeech,
        speakerCharacterInstanceId: character.id,
        content: '第 $index 回合的角色回应。',
        metadata: {'turnId': turnId},
      ),
    ]) {
      await repository.upsertFeedEntry(entry);
    }
    await repository.upsertTurn(
      WorldTurn(
        entity: _meta(turnId),
        worldSessionId: created.session.id,
        branchId: created.branch.id,
        userFeedEntryId: userId,
        generatedFeedEntryIds: [narrationId, speechId],
        status: WorldTurnStatus.completed,
        mutationProposal: WorldMutationProposal(
          operations: index % 5 == 0
              ? const [
                  WorldMutationOperation(type: WorldMutationType.sceneUpdate),
                ]
              : const [],
          memories: index % 7 == 0
              ? [WorldMemoryCandidate(summary: '第 $index 回合记忆')]
              : const [],
          timelineEvents: index % 9 == 0
              ? [WorldTimelineCandidate(title: '第 $index 回合事件')]
              : const [],
        ).toJson(),
      ),
    );
  }
  return _ExperienceFixture(
    repository: repository,
    service: service,
    contextBuilder: WorldRoleplayContextBuilder(
      worlds: repository,
      characters: InMemoryCharacterRepository(core),
    ),
    sessionId: created.session.id,
    branchId: created.branch.id,
  );
}

class _ExperienceFixture {
  const _ExperienceFixture({
    required this.repository,
    required this.service,
    required this.contextBuilder,
    required this.sessionId,
    required this.branchId,
  });

  final InMemoryWorldRoleplayRepository repository;
  final WorldRoleplayService service;
  final WorldRoleplayContextBuilder contextBuilder;
  final String sessionId;
  final String branchId;
}

WorldFeedEntry _feed(String id, String? turnId, WorldFeedEntryType type) {
  return WorldFeedEntry(
    entity: _meta(id),
    worldSessionId: 'session',
    branchId: 'branch',
    type: type,
    content: id,
    metadata: {'turnId': ?turnId},
  );
}

WorldTurn _turn(String id, String userFeedEntryId) {
  return WorldTurn(
    entity: _meta(id),
    worldSessionId: 'session',
    branchId: 'branch',
    userFeedEntryId: userFeedEntryId,
    status: WorldTurnStatus.completed,
  );
}

EntityMetadata _meta(String id) {
  final index = id.codeUnits.fold<int>(0, (sum, value) => sum + value);
  final at = DateTime.utc(2026, 8, 31).add(Duration(milliseconds: index));
  return EntityMetadata(id: id, createdAt: at, updatedAt: at, revision: 1);
}
