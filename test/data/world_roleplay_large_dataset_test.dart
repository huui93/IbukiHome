import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/application/world_roleplay/world_context_builder.dart';
import 'package:ibukihome/application/world_roleplay/world_roleplay_service.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_character_repository.dart';
import 'package:ibukihome/data/memory/in_memory_world_roleplay_repository.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_models.dart';

void main() {
  test(
    'large world dataset remains queryable without eager UI materialization',
    () async {
      final core = InMemoryIbukiStore();
      final repository = InMemoryWorldRoleplayRepository(core);
      final service = WorldRoleplayService(
        repository: repository,
        ids: EntityIdGenerator(),
        clock: const UtcClock(),
      );
      final created = await service.createWorld(name: 'Large World');

      for (var index = 0; index < 100; index += 1) {
        final cardId = 'card-$index';
        core.putCharacter(
          CharacterCard(
            metadata: _meta(cardId),
            projectId: 'synthetic-project',
            name: 'Character $index',
            content: 'Synthetic definition',
            sortOrder: index,
          ),
        );
        await repository.upsertCharacterInstance(
          WorldCharacterInstance(
            entity: _meta('instance-$index'),
            worldSessionId: created.session.id,
            characterCardId: cardId,
            currentLocation: 'Location ${index % 10}',
            currentStatus: 'Active',
          ),
        );
      }
      final scene = await service.createScene(
        worldSessionId: created.session.id,
        name: 'Bounded Context Scene',
      );
      await service.setCurrentScene(
        worldSessionId: created.session.id,
        sceneId: scene.id,
        presentCharacterInstanceIds: const {
          'instance-0',
          'instance-1',
          'instance-2',
        },
      );

      for (var index = 0; index < 1000; index += 1) {
        await repository.upsertLoreEntry(
          LoreEntry(
            entity: _meta('lore-$index'),
            worldBookId: created.worldBook.id,
            title: index == 777 ? 'Needle Lore' : 'Lore $index',
            content: 'World definition $index',
            keywords: ['keyword-$index'],
          ),
        );
        await repository.upsertMemory(
          WorldMemoryEntry(
            entity: _meta('memory-$index'),
            worldSessionId: created.session.id,
            type: 'synthetic',
            summary: index == 777 ? 'Needle Memory' : 'Memory $index',
            content: 'Memory detail $index',
          ),
        );
      }

      for (var index = 0; index < 2000; index += 1) {
        await repository.upsertTimelineEvent(
          WorldTimelineEvent(
            entity: _meta('event-$index'),
            worldSessionId: created.session.id,
            title: index == 1777 ? 'Needle Timeline' : 'Event $index',
            description: 'Timeline detail $index',
            worldTime: 'Day ${index ~/ 24} · ${index % 24}:00',
          ),
        );
      }

      for (var index = 0; index < 5000; index += 1) {
        await repository.upsertFeedEntry(
          WorldFeedEntry(
            entity: _meta('feed-${index.toString().padLeft(5, '0')}'),
            worldSessionId: created.session.id,
            branchId: created.branch.id,
            type: index.isEven
                ? WorldFeedEntryType.narration
                : WorldFeedEntryType.userAction,
            content: 'Feed entry $index',
          ),
        );
      }

      final counts = await repository.getDatabaseCounts(created.session.id);
      expect(counts.characterInstances, 100);
      expect(counts.loreEntries, 1000);
      expect(counts.memories, 1000);
      expect(counts.timelineEvents, 2000);
      expect(counts.feedEntries, 5000);
      expect(
        await repository.listFeedEntries(created.session.id, limit: 50),
        hasLength(50),
      );
      expect(
        (await repository.searchWorldDatabase(
          created.session.id,
          'Needle',
        )).map((item) => item.type).toSet(),
        {'lore', 'memory', 'timeline'},
      );

      final snapshot =
          await WorldRoleplayContextBuilder(
            worlds: repository,
            characters: InMemoryCharacterRepository(core),
          ).build(
            worldSessionId: created.session.id,
            userAction: '继续探索 keyword-777',
          );
      expect(snapshot.context.diagnostics.selectedCharacterCount, 3);
      expect(snapshot.recentFeed, hasLength(24));
      expect(snapshot.memories.length, lessThanOrEqualTo(12));
      expect(snapshot.timeline.length, lessThanOrEqualTo(10));
      expect(snapshot.stateEntries.length, lessThanOrEqualTo(40));
      expect(snapshot.lore.entries, isNotEmpty);
      expect(
        snapshot.lore.diagnostics.estimatedTokens,
        lessThanOrEqualTo(created.session.loreContextBudget),
      );
    },
  );
}

EntityMetadata _meta(String id) {
  final index = id.codeUnits.fold<int>(0, (sum, value) => sum + value);
  final at = DateTime.utc(2026, 8, 28).add(Duration(milliseconds: index));
  return EntityMetadata(id: id, createdAt: at, updatedAt: at, revision: 1);
}
