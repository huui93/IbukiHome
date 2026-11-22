import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/character_repository.dart';
import '../../data/repositories/committed_entity_cache.dart';
import '../../data/repositories/compatibility_import_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/world_roleplay_repository.dart';
import '../../domain/characters/character_card.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/import/external_compatibility_payload.dart';
import '../../domain/import/sillytavern_models.dart';
import '../../domain/projects/project.dart';
import '../../domain/world_roleplay/world_roleplay_models.dart';
import '../common/entity_id_generator.dart';
import '../common/utc_clock.dart';
import '../world_roleplay/world_prompt_layer.dart';
import 'sillytavern_asset_store.dart';
import 'sillytavern_file_picker.dart';
import 'sillytavern_import_plan.dart';
import 'sillytavern_parser.dart';

class SillyTavernImportConflictException extends DataException {
  SillyTavernImportConflictException(List<String> conflicts)
    : super(conflicts.join('\n'));
}

class SillyTavernImportService {
  const SillyTavernImportService({
    required this.repository,
    required this.projects,
    required this.characters,
    required this.worlds,
    required this.assets,
    required this.ids,
    required this.clock,
    this.parser = const SillyTavernParser(),
  });

  final CompatibilityImportRepository repository;
  final ProjectRepository projects;
  final CharacterRepository characters;
  final WorldRoleplayRepository worlds;
  final SillyTavernImportAssetStore assets;
  final EntityIdGenerator ids;
  final UtcClock clock;
  final SillyTavernParser parser;

  Future<SillyTavernImportInspection> inspect(
    SillyTavernImportSource source,
  ) async {
    final declaredLength = await source.length();
    if (declaredLength <= 0 || declaredLength > parser.limits.maxSourceBytes) {
      throw const SillyTavernParseException('文件为空或超过安全大小限制。');
    }
    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in source.openRead()) {
      received += chunk.length;
      if (received > parser.limits.maxSourceBytes) {
        throw const SillyTavernParseException('文件超过安全大小限制。');
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    final fileName = source.fileName;
    final safeParser = parser;
    final (asset, sourceHash) = await Isolate.run(
      () => (
        safeParser.parse(bytes, fileName: fileName),
        sha256.convert(bytes).toString(),
      ),
    );
    final duplicates = await repository.findBySourceSha256(sourceHash);
    return SillyTavernImportInspection(
      fileName: fileName,
      sourceSha256: sourceHash,
      sourceBytes: bytes,
      asset: asset,
      existingPayloadIds: List.unmodifiable(duplicates.map((item) => item.id)),
      imageBytes:
          asset.kind == SillyTavernAssetKind.characterCard && _isPng(bytes)
          ? bytes
          : null,
    );
  }

  Future<SillyTavernImportPlan> buildPlan({
    required SillyTavernImportInspection inspection,
    required SillyTavernImportDestination destination,
  }) async {
    final asset = inspection.asset;
    final now = clock.now();
    final payloadId = ids.nextId('compatibility_payload');
    final warnings = <String>[...asset.warnings];
    final conflicts = <String>[];
    if (inspection.isDuplicate && !destination.allowDuplicateSource) {
      conflicts.add('该资产已经导入。请选择查看已有资产、再次导入副本或取消。');
    }

    CharacterCard? character;
    Project? project;
    WorldBook? worldBook;
    WorldWorldBookReference? worldBookReference;
    EntityWorldBookReference? characterBookReference;
    var loreEntries = <LoreEntry>[];
    PlayerPersona? persona;
    RoleplayWorld? updatedWorld;
    WorldSession? updatedSession;
    late String linkedEntityType;
    late String linkedEntityId;

    switch (asset.kind) {
      case SillyTavernAssetKind.characterCard:
        var projectId = destination.projectId;
        if (projectId == null &&
            destination.newProjectTitle?.trim().isNotEmpty == true) {
          project = Project(
            metadata: _entity(ids.nextId('project'), now),
            title: destination.newProjectTitle!.trim(),
            description: '',
          );
          projectId = project.id;
        }
        if (projectId == null || projectId.isEmpty) {
          conflicts.add('请选择角色所属项目。');
          linkedEntityType = 'characterCard';
          linkedEntityId = '';
          break;
        }
        if (project == null &&
            (await projects.getProject(projectId)).deletedAt != null) {
          throw const DataConflictException('项目已删除，请重新选择保存位置。');
        }
        final card = asset.characterCard!;
        final active = project == null
            ? await characters.listCharacters(projectId)
            : <CharacterCard>[];
        final sameName = active.any(
          (item) => item.name.trim() == card.name.trim(),
        );
        if (sameName && !destination.allowSameNameCopy) {
          conflicts.add('同一项目已有同名角色；请选择导入为副本或取消。');
        }
        final order = active.isEmpty
            ? 0
            : active
                      .map((item) => item.sortOrder)
                      .reduce((left, right) => left > right ? left : right) +
                  1;
        final characterId = ids.nextId('character');
        character = CharacterCard(
          metadata: _entity(characterId, now),
          projectId: projectId,
          name: card.name,
          content: _nativeCharacterContent(card),
          sortOrder: order,
          mode: null,
          sourceFormat: asset.sourceFormat,
          compatibilityPayloadId: payloadId,
        );
        linkedEntityType = 'characterCard';
        linkedEntityId = characterId;
        final embeddedBook = card.characterBook;
        if (embeddedBook != null &&
            destination.characterBookMode !=
                SillyTavernCharacterBookImportMode.preserveOnly) {
          final target = await _resolveWorldBookTarget(
            destination,
            name: '${card.name} · 角色世界书',
            payloadId: payloadId,
            now: now,
          );
          worldBook = target.created;
          if (target.created != null) {
            characterBookReference = EntityWorldBookReference(
              entity: _entity(ids.nextId('character_book_reference'), now),
              entityId: characterId,
              worldBookId: target.worldBookId,
            );
          }
          loreEntries = _nativeLoreEntries(
            embeddedBook.entries,
            target.worldBookId,
            payloadId,
            now,
          );
        }
      case SillyTavernAssetKind.lorebook:
        final sourceBook = asset.lorebook!;
        final target = await _resolveWorldBookTarget(
          destination,
          name: sourceBook.name,
          payloadId: payloadId,
          now: now,
          forceCreateWhenPreserveSelected: true,
        );
        worldBook = target.created;
        if (target.created != null && destination.worldId?.isNotEmpty == true) {
          await worlds.getWorld(destination.worldId!);
          worldBookReference = WorldWorldBookReference(
            entity: _entity(ids.nextId('world_book_reference'), now),
            worldId: destination.worldId!,
            worldBookId: target.worldBookId,
          );
        }
        loreEntries = _nativeLoreEntries(
          sourceBook.entries,
          target.worldBookId,
          payloadId,
          now,
        );
        linkedEntityType = 'worldBook';
        linkedEntityId = target.worldBookId;
      case SillyTavernAssetKind.persona:
        final worldId = destination.worldId;
        if (worldId == null || worldId.isEmpty) {
          conflicts.add('请选择 Persona 所属世界。');
          linkedEntityType = 'playerPersona';
          linkedEntityId = '';
          break;
        }
        await worlds.getWorld(worldId);
        final sourcePersona = asset.persona!;
        final personaId = ids.nextId('world_persona');
        persona = PlayerPersona(
          entity: _entity(personaId, now),
          worldId: worldId,
          name: sourcePersona.name,
          description: sourcePersona.description,
          // External references are provenance only, never trusted local paths.
          avatarReference: null,
          metadata: {
            'sourceFormat': asset.sourceFormat,
            'compatibilityPayloadId': payloadId,
            'knowledgeVisibility': {
              'description': destination.personaVisibility.name,
            },
          },
        );
        linkedEntityType = 'playerPersona';
        linkedEntityId = personaId;
      case SillyTavernAssetKind.promptPreset:
        final worldId = destination.worldId;
        if (worldId == null || worldId.isEmpty) {
          conflicts.add('请选择 Prompt Preset 的目标世界。');
          linkedEntityType = 'world';
          linkedEntityId = '';
          break;
        }
        final world = await worlds.getWorld(worldId);
        final preset = asset.promptPreset!;
        linkedEntityType = 'world';
        linkedEntityId = worldId;
        if (destination.promptMode != SillyTavernPromptImportMode.skip &&
            preset.mainPrompt.isNotEmpty) {
          final current = WorldPromptMetadata.worldSystemPrompt(world);
          final next = _mergePrompt(
            current,
            preset.mainPrompt,
            destination.promptMode,
          );
          updatedWorld = WorldPromptMetadata.withWorldSystemPrompt(
            world,
            next,
            entity: _next(world.entity, now),
          );
        }
        final sessionId = destination.worldSessionId;
        if (destination.promptMode != SillyTavernPromptImportMode.skip &&
            sessionId != null &&
            sessionId.isNotEmpty) {
          final session = await worlds.getSession(sessionId);
          if (session.worldId != worldId) {
            conflicts.add('所选 WorldSession 不属于目标世界。');
          } else {
            final imported = [
              preset.postHistoryInstructions,
              preset.authorsNote,
            ].where((item) => item.isNotEmpty).join('\n\n');
            if (imported.isNotEmpty) {
              updatedSession =
                  WorldPromptMetadata.withSessionAdditionalInstructions(
                    session,
                    _mergePrompt(
                      WorldPromptMetadata.sessionAdditionalInstructions(
                        session,
                      ),
                      imported,
                      destination.promptMode,
                    ),
                    entity: _next(session.entity, now),
                  );
            }
          }
        }
        if (destination.promptMode == SillyTavernPromptImportMode.skip) {
          warnings.add('Prompt 已保存为兼容数据，未修改现有 World Prompt。');
        }
    }

    final payload = ExternalCompatibilityPayload(
      id: payloadId,
      sourceType: ExternalCompatibilitySourceType.sillyTavern,
      sourceFormat: asset.sourceFormat,
      sourceVersion: asset.sourceVersion,
      sourceSha256: inspection.sourceSha256,
      linkedEntityType: linkedEntityType,
      linkedEntityId: linkedEntityId,
      normalizedPayload: asset.normalizedPayload,
      unsupportedPayload: asset.unsupportedPayload,
      securityFlags: asset.security.flags,
      importWarnings: List.unmodifiable(warnings),
      createdAt: now,
      metadata: {
        'sourceFileName': inspection.fileName,
        'mappedFields': asset.normalizedPayload.keys.toList(growable: false),
      },
    );
    return SillyTavernImportPlan(
      inspection: inspection,
      destination: destination,
      payload: payload,
      warnings: List.unmodifiable(warnings),
      conflicts: List.unmodifiable(conflicts),
      project: project,
      character: character,
      worldBook: worldBook,
      worldBookReference: worldBookReference,
      characterBookReference: characterBookReference,
      loreEntries: List.unmodifiable(loreEntries),
      persona: persona,
      updatedWorld: updatedWorld,
      updatedSession: updatedSession,
    );
  }

  Future<SillyTavernImportResult> execute(SillyTavernImportPlan plan) async {
    if (!plan.canImport) {
      throw SillyTavernImportConflictException(plan.conflicts);
    }
    String? copiedImage;
    var character = plan.character;
    var payload = plan.payload;
    try {
      final image = plan.inspection.imageBytes;
      if (character != null && image != null) {
        copiedImage = await assets.saveCharacterImage(payload.id, image);
        character = character.copyWith(avatarReference: copiedImage);
        payload = payload.copyWith(
          normalizedPayload: Map.unmodifiable({
            ...payload.normalizedPayload,
            'avatarReference': copiedImage,
          }),
        );
      }
      await repository.commitImport(
        SillyTavernImportWrite(
          payload: payload,
          project: plan.project,
          character: character,
          worldBook: plan.worldBook,
          worldBookReference: plan.worldBookReference,
          characterBookReference: plan.characterBookReference,
          loreEntries: plan.loreEntries,
          persona: plan.persona,
          updatedWorld: plan.updatedWorld,
          updatedSession: plan.updatedSession,
        ),
      );
    } catch (_) {
      if (copiedImage != null) await assets.deleteAsset(copiedImage);
      rethrow;
    }
    // The transaction bypasses the read-through repositories used by the UI.
    // Publish only committed entities, without a second database write.
    final projectCache = projects;
    if (plan.project != null && projectCache is CommittedEntityCache<Project>) {
      (projectCache as CommittedEntityCache<Project>).acceptCommittedEntity(
        plan.project!,
      );
    }
    final characterCache = characters;
    if (character != null &&
        characterCache is CommittedEntityCache<CharacterCard>) {
      (characterCache as CommittedEntityCache<CharacterCard>)
          .acceptCommittedEntity(character);
    }
    return SillyTavernImportResult(
      payload: payload,
      character: character,
      worldBook: plan.worldBook,
      worldBookReference: plan.worldBookReference,
      characterBookReference: plan.characterBookReference,
      persona: plan.persona,
    );
  }

  Future<_WorldBookTarget> _resolveWorldBookTarget(
    SillyTavernImportDestination destination, {
    required String name,
    required String payloadId,
    required DateTime now,
    bool forceCreateWhenPreserveSelected = false,
  }) async {
    final useExisting =
        destination.characterBookMode ==
        SillyTavernCharacterBookImportMode.existingWorldBook;
    if (useExisting) {
      final id = destination.worldBookId;
      if (id == null || id.isEmpty) {
        throw const DataFormatException('请选择目标 WorldBook。');
      }
      final existing = await worlds.getWorldBook(id);
      return _WorldBookTarget(worldBookId: existing.id);
    }
    final shouldCreate =
        forceCreateWhenPreserveSelected ||
        destination.characterBookMode ==
            SillyTavernCharacterBookImportMode.createNewWorldBook;
    if (!shouldCreate) {
      throw const DataFormatException('CharacterBook 当前仅随角色保存。');
    }
    final book = WorldBook(
      entity: _entity(ids.nextId('world_book'), now),
      name: name,
      metadata: {
        'sourceFormat': 'sillytavern',
        'compatibilityPayloadId': payloadId,
      },
    );
    return _WorldBookTarget(worldBookId: book.id, created: book);
  }

  List<LoreEntry> _nativeLoreEntries(
    List<SillyTavernCharacterBookEntry> source,
    String worldBookId,
    String payloadId,
    DateTime now,
  ) {
    return [
      for (final item in source)
        LoreEntry(
          entity: _entity(ids.nextId('lore_entry'), now),
          worldBookId: worldBookId,
          title: item.title,
          content: item.content,
          keywords: item.keys,
          secondaryKeywords: item.selective ? item.secondaryKeys : const [],
          enabled: item.enabled,
          priority: item.order,
          activationMode: item.constant
              ? LoreActivationMode.always
              : item.keys.isNotEmpty
              ? LoreActivationMode.keyword
              : LoreActivationMode.manual,
          insertionPosition: item.position,
          probability: item.probability,
          metadata: {
            'sourceFormat': 'sillytavern',
            'sourceEntryId': item.id,
            'compatibilityPayloadId': payloadId,
            if (item.unsupported.isNotEmpty) 'hasPreservedAdvancedRules': true,
          },
        ),
    ];
  }

  String _nativeCharacterContent(SillyTavernCharacterCardData card) {
    final sections = <String>[
      if (card.description.isNotEmpty) '【角色描述】\n${card.description}',
      if (card.personality.isNotEmpty) '【性格】\n${card.personality}',
      if (card.scenario.isNotEmpty) '【初始场景】\n${card.scenario}',
    ];
    return sections.join('\n\n');
  }

  String _mergePrompt(
    String current,
    String imported,
    SillyTavernPromptImportMode mode,
  ) {
    return switch (mode) {
      SillyTavernPromptImportMode.skip => current,
      SillyTavernPromptImportMode.replace => imported.trim(),
      SillyTavernPromptImportMode.append => [
        current.trim(),
        imported.trim(),
      ].where((item) => item.isNotEmpty).join('\n\n'),
    };
  }

  bool _isPng(Uint8List bytes) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < signature.length) return false;
    for (var index = 0; index < signature.length; index += 1) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }
}

class _WorldBookTarget {
  const _WorldBookTarget({required this.worldBookId, this.created});

  final String worldBookId;
  final WorldBook? created;
}

EntityMetadata _entity(String id, DateTime now) =>
    EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);

EntityMetadata _next(EntityMetadata value, DateTime now) =>
    value.copyWith(updatedAt: now, revision: value.revision + 1);
