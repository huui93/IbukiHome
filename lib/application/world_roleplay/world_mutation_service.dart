import '../../application/common/entity_id_generator.dart';
import '../../application/common/utc_clock.dart';
import '../../data/repositories/world_roleplay_repository.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/world_roleplay/world_roleplay_engine_models.dart';
import '../../domain/world_roleplay/world_roleplay_models.dart';
import 'world_context_builder.dart';

class WorldMutationService {
  const WorldMutationService({
    required this.repository,
    required this.ids,
    required this.clock,
  });

  final WorldRoleplayRepository repository;
  final EntityIdGenerator ids;
  final UtcClock clock;

  Future<WorldMutationCommit> prepare({
    required WorldRoleplaySnapshot snapshot,
    required WorldTurn turn,
    required WorldMutationProposal proposal,
  }) async {
    final now = clock.now();
    var session = snapshot.session;
    var scene = snapshot.scene;
    var player = snapshot.playerInstance;
    final characterById = {
      for (final item in await repository.listCharacterInstances(session.id))
        item.id: item,
    };
    final stateById = {
      for (final item in await repository.listStateEntries(session.id))
        item.id: item,
    };
    final stateByKey = {for (final item in stateById.values) item.key: item};
    final relationshipById = {
      for (final item in await repository.listRelationships(session.id))
        item.id: item,
    };
    final cast = scene == null
        ? <String>{}
        : (await repository.listSceneCast(scene.id)).toSet();
    var castChanged = false;
    final changedCharacters = <String, WorldCharacterInstance>{};
    final stateUpserts = <String, WorldStateEntry>{};
    final stateDeletes = <String>{};
    final relationshipUpserts = <String, WorldRelationship>{};

    for (final operation in proposal.operations) {
      switch (operation.type) {
        case WorldMutationType.sceneUpdate:
          final current = scene;
          if (current == null || operation.entityId != current.id) {
            return _invalid('只能更新当前世界存档的当前场景。');
          }
          _onlyFields(operation.values, const {
            'name',
            'description',
            'location',
            'timeText',
            'weather',
            'atmosphere',
            'currentEvent',
          });
          scene = current.copyWith(
            entity: _next(current.entity, now),
            name: _text(operation.values, 'name', current.name),
            description: _text(
              operation.values,
              'description',
              current.description,
            ),
            location: _text(operation.values, 'location', current.location),
            timeText: _text(operation.values, 'timeText', current.timeText),
            weather: _text(operation.values, 'weather', current.weather),
            atmosphere: _text(
              operation.values,
              'atmosphere',
              current.atmosphere,
            ),
            currentEvent: _text(
              operation.values,
              'currentEvent',
              current.currentEvent,
            ),
          );
          continue;
        case WorldMutationType.stateSet:
          _onlyFields(operation.values, const {'key', 'value', 'category'});
          final key = _requiredText(operation.values, 'key', maxLength: 200);
          final value = operation.values['value'];
          if (!_isJsonSafe(value)) return _invalid('世界状态值不是安全 JSON。');
          final existing = operation.entityId == null
              ? stateByKey[key]
              : stateById[operation.entityId];
          if (operation.entityId != null && existing == null) {
            return _invalid('世界状态不属于当前存档。');
          }
          final entry = existing == null
              ? WorldStateEntry(
                  entity: _entity(ids.nextId('world_state'), now),
                  worldSessionId: session.id,
                  key: key,
                  value: value,
                  category: _text(operation.values, 'category', 'general'),
                  source: 'worldEngine',
                )
              : existing.copyWith(
                  entity: _next(existing.entity, now),
                  key: key,
                  value: value,
                  category: _text(
                    operation.values,
                    'category',
                    existing.category,
                  ),
                  source: 'worldEngine',
                );
          stateUpserts[entry.id] = entry;
          continue;
        case WorldMutationType.stateRemove:
          final id = operation.entityId;
          if (id == null || stateById[id] == null) {
            return _invalid('要删除的世界状态不属于当前存档。');
          }
          stateDeletes.add(id);
          stateUpserts.remove(id);
          continue;
        case WorldMutationType.characterUpdate:
          final id = operation.entityId;
          final current = id == null ? null : characterById[id];
          if (current == null) return _invalid('角色实例不属于当前存档。');
          _onlyFields(operation.values, const {
            'currentLocation',
            'currentStatus',
            'currentMood',
            'currentGoal',
            'isPresent',
          });
          final updated = current.copyWith(
            entity: _next(current.entity, now),
            currentLocation: _text(
              operation.values,
              'currentLocation',
              current.currentLocation,
            ),
            currentStatus: _text(
              operation.values,
              'currentStatus',
              current.currentStatus,
            ),
            currentMood: _text(
              operation.values,
              'currentMood',
              current.currentMood,
            ),
            currentGoal: _text(
              operation.values,
              'currentGoal',
              current.currentGoal,
            ),
            isPresent: _boolean(
              operation.values,
              'isPresent',
              current.isPresent,
            ),
            lastActiveAt: now,
          );
          changedCharacters[id!] = updated;
          if (updated.isPresent) {
            cast.add(id);
          } else {
            cast.remove(id);
          }
          castChanged = true;
          continue;
        case WorldMutationType.playerUpdate:
          final current = player;
          if (current == null || operation.entityId != current.id) {
            return _invalid('玩家实例不属于当前存档。');
          }
          _onlyFields(operation.values, const {
            'currentLocation',
            'currentStatus',
            'currentMood',
            'currentGoal',
          });
          player = current.copyWith(
            entity: _next(current.entity, now),
            currentLocation: _text(
              operation.values,
              'currentLocation',
              current.currentLocation,
            ),
            currentStatus: _text(
              operation.values,
              'currentStatus',
              current.currentStatus,
            ),
            currentMood: _text(
              operation.values,
              'currentMood',
              current.currentMood,
            ),
            currentGoal: _text(
              operation.values,
              'currentGoal',
              current.currentGoal,
            ),
            lastActiveAt: now,
          );
          continue;
        case WorldMutationType.sceneCastAdd:
        case WorldMutationType.sceneCastRemove:
          if (scene == null) return _invalid('当前没有可修改的场景。');
          final id = operation.entityId;
          final character = id == null ? null : characterById[id];
          if (character == null) return _invalid('Scene Cast 角色不属于当前存档。');
          final present = operation.type == WorldMutationType.sceneCastAdd;
          if (present) {
            cast.add(id!);
          } else {
            cast.remove(id);
          }
          castChanged = true;
          changedCharacters[id!] = character.copyWith(
            entity: _next(character.entity, now),
            isPresent: present,
            lastActiveAt: now,
          );
          continue;
        case WorldMutationType.relationshipUpsert:
          _onlyFields(operation.values, const {
            'sourceEntityType',
            'sourceEntityId',
            'targetEntityType',
            'targetEntityId',
            'relationType',
            'summary',
            'state',
          });
          final existing = operation.entityId == null
              ? null
              : relationshipById[operation.entityId];
          if (operation.entityId != null && existing == null) {
            return _invalid('人物关系不属于当前存档。');
          }
          final sourceId = _text(
            operation.values,
            'sourceEntityId',
            existing?.sourceEntityId ?? '',
          );
          final targetId = _text(
            operation.values,
            'targetEntityId',
            existing?.targetEntityId ?? '',
          );
          if (!_ownedEntity(sourceId, characterById, player?.id) ||
              !_ownedEntity(targetId, characterById, player?.id)) {
            return _invalid('人物关系引用了当前存档以外的实体。');
          }
          final rawState =
              operation.values['state'] ?? existing?.state ?? const {};
          if (rawState is! Map || !_isJsonSafe(rawState)) {
            return _invalid('人物关系状态不是安全 JSON。');
          }
          final relationship = existing == null
              ? WorldRelationship(
                  entity: _entity(ids.nextId('world_relationship'), now),
                  worldSessionId: session.id,
                  sourceEntityType: _requiredText(
                    operation.values,
                    'sourceEntityType',
                  ),
                  sourceEntityId: sourceId,
                  targetEntityType: _requiredText(
                    operation.values,
                    'targetEntityType',
                  ),
                  targetEntityId: targetId,
                  relationType: _requiredText(operation.values, 'relationType'),
                  summary: _text(operation.values, 'summary', ''),
                  state: Map<String, Object?>.from(rawState),
                )
              : existing.copyWith(
                  entity: _next(existing.entity, now),
                  sourceEntityType: _text(
                    operation.values,
                    'sourceEntityType',
                    existing.sourceEntityType,
                  ),
                  sourceEntityId: sourceId,
                  targetEntityType: _text(
                    operation.values,
                    'targetEntityType',
                    existing.targetEntityType,
                  ),
                  targetEntityId: targetId,
                  relationType: _text(
                    operation.values,
                    'relationType',
                    existing.relationType,
                  ),
                  summary: _text(operation.values, 'summary', existing.summary),
                  state: Map<String, Object?>.from(rawState),
                );
          relationshipUpserts[relationship.id] = relationship;
          continue;
        case WorldMutationType.worldTimeUpdate:
          _onlyFields(operation.values, const {'worldTime', 'minutesAdvanced'});
          final worldTime = _requiredText(operation.values, 'worldTime');
          session = session.copyWith(
            entity: _next(session.entity, now),
            worldTime: worldTime,
            metadata: {
              ...session.metadata,
              if (operation.values['minutesAdvanced'] is num)
                'lastMinutesAdvanced': operation.values['minutesAdvanced'],
            },
          );
          continue;
      }
    }

    if (scene != null &&
        scene.timeText.isNotEmpty &&
        scene.timeText != session.worldTime) {
      session = session.copyWith(
        entity: _next(session.entity, now),
        worldTime: scene.timeText,
      );
    }
    final memories = proposal.memories
        .where(
          (candidate) =>
              candidate.importance >= 0.65 && candidate.summary.isNotEmpty,
        )
        .where(
          (candidate) =>
              candidate.relatedCharacterIds.every(characterById.containsKey),
        )
        .map(
          (candidate) => WorldMemoryEntry(
            entity: _entity(ids.nextId('world_memory'), now),
            worldSessionId: session.id,
            type: candidate.type,
            summary: candidate.summary,
            content: candidate.content,
            importance: candidate.importance,
            relatedCharacterIds: candidate.relatedCharacterIds,
            relatedSceneId: scene?.id,
            metadata: {'source': 'worldEngine', 'turnId': turn.id},
          ),
        )
        .toList(growable: false);
    final timeline = proposal.timelineEvents
        .where(
          (candidate) =>
              candidate.importance >= 0.65 && candidate.title.isNotEmpty,
        )
        .where(
          (candidate) =>
              candidate.characterIds.every(characterById.containsKey),
        )
        .map(
          (candidate) => WorldTimelineEvent(
            entity: _entity(ids.nextId('world_event'), now),
            worldSessionId: session.id,
            title: candidate.title,
            description: candidate.description,
            worldTime: session.worldTime,
            sceneId: scene?.id,
            characterIds: candidate.characterIds,
            eventType: candidate.eventType,
            importance: candidate.importance,
            metadata: {'source': 'worldEngine', 'turnId': turn.id},
          ),
        )
        .toList(growable: false);
    return WorldMutationCommit(
      worldSessionId: session.id,
      turn: turn,
      session: session == snapshot.session ? null : session,
      scene: scene == snapshot.scene && !castChanged ? null : scene,
      sceneCast: castChanged ? cast : null,
      characterInstances: List.unmodifiable(changedCharacters.values),
      playerInstance: player == snapshot.playerInstance ? null : player,
      stateUpserts: List.unmodifiable(stateUpserts.values),
      stateDeleteIds: List.unmodifiable(stateDeletes),
      relationshipUpserts: List.unmodifiable(relationshipUpserts.values),
      memories: List.unmodifiable(memories),
      timelineEvents: List.unmodifiable(timeline),
    );
  }

  Future<void> commit(WorldMutationCommit commit) async {
    try {
      await repository.commitWorldMutation(commit);
    } catch (error) {
      throw WorldEngineException(
        WorldEngineErrorCategory.mutationSaveError,
        '世界变化保存失败。',
        detail: error.runtimeType.toString(),
      );
    }
  }

  Never _invalid(String message) {
    throw WorldEngineException(
      WorldEngineErrorCategory.mutationValidationError,
      message,
    );
  }

  void _onlyFields(Map<String, Object?> values, Set<String> allowed) {
    if (values.keys.any((key) => !allowed.contains(key))) {
      _invalid('世界变化包含不允许修改的字段。');
    }
  }

  String _requiredText(
    Map<String, Object?> values,
    String key, {
    int maxLength = 4000,
  }) {
    final value = values[key];
    if (value is! String || value.trim().isEmpty || value.length > maxLength) {
      return _invalid('世界变化字段 $key 无效。');
    }
    return value.trim();
  }

  String _text(Map<String, Object?> values, String key, String fallback) {
    if (!values.containsKey(key)) return fallback;
    final value = values[key];
    if (value is! String || value.length > 4000) {
      return _invalid('世界变化字段 $key 无效。');
    }
    return value.trim();
  }

  bool _boolean(Map<String, Object?> values, String key, bool fallback) {
    if (!values.containsKey(key)) return fallback;
    final value = values[key];
    if (value is! bool) return _invalid('世界变化字段 $key 无效。');
    return value;
  }

  bool _ownedEntity(
    String id,
    Map<String, WorldCharacterInstance> characters,
    String? playerId,
  ) => id == playerId || characters.containsKey(id);

  bool _isJsonSafe(Object? value, [int depth = 0]) {
    if (depth > 12) return false;
    if (value == null || value is String || value is bool) return true;
    if (value is num) return value.isFinite;
    if (value is List) {
      return value.length <= 1000 &&
          value.every((item) => _isJsonSafe(item, depth + 1));
    }
    if (value is Map) {
      return value.length <= 1000 &&
          value.entries.every(
            (entry) =>
                entry.key is String && _isJsonSafe(entry.value, depth + 1),
          );
    }
    return false;
  }
}

EntityMetadata _entity(String id, DateTime now) =>
    EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);

EntityMetadata _next(EntityMetadata entity, DateTime now) =>
    entity.copyWith(updatedAt: now, revision: entity.revision + 1);
