import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/application/import/sillytavern_asset_store.dart';
import 'package:ibukihome/application/import/sillytavern_file_picker.dart';
import 'package:ibukihome/application/import/sillytavern_import_plan.dart';
import 'package:ibukihome/application/import/sillytavern_import_service.dart';
import 'package:ibukihome/application/import/sillytavern_parser.dart';
import 'package:ibukihome/application/world_roleplay/world_roleplay_service.dart';
import 'package:ibukihome/application/world_roleplay/start_roleplay_story.dart';
import 'package:ibukihome/application/world_roleplay/world_context_builder.dart';
import 'package:ibukihome/data/memory/in_memory_character_repository.dart';
import 'package:ibukihome/data/memory/in_memory_compatibility_import_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/data/memory/in_memory_world_roleplay_repository.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/import/sillytavern_models.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_models.dart';

void main() {
  const parser = SillyTavernParser();

  test('parses Character Card V2 semantic fields without flattening', () {
    final parsed = parser.parse(
      _jsonBytes(_characterCard(version: 2)),
      fileName: 'v2.json',
    );

    expect(parsed.kind, SillyTavernAssetKind.characterCard);
    expect(parsed.sourceFormat, 'chara_card_v2');
    expect(parsed.sourceVersion, '2.0');
    expect(parsed.characterCard?.name, 'Mira');
    expect(parsed.characterCard?.firstMessage, 'Welcome home.');
    expect(parsed.characterCard?.alternateGreetings, ['Good morning.', 'Hey.']);
    expect(parsed.characterCard?.exampleMessages, contains('Tea'));
    expect(parsed.characterCard?.systemPrompt, 'Keep her voice calm.');
    expect(parsed.characterCard?.postHistoryInstructions, 'Stay in character.');
  });

  test('parses V3 PNG chara metadata', () {
    final bytes = _pngWithText(
      'chara',
      base64Encode(_jsonBytes(_characterCard(version: 3))),
    );
    final parsed = parser.parse(bytes, fileName: 'card.png');

    expect(parsed.sourceFormat, 'chara_card_v3');
    expect(parsed.characterCard?.characterBook?.entries, hasLength(2));
  });

  test('prefers ccv3 and reports duplicate embedded metadata', () {
    final first = base64Encode(_jsonBytes(_characterCard(version: 2)));
    final second = base64Encode(
      _jsonBytes(_characterCard(version: 3, name: 'CCV3 Mira')),
    );
    final bytes = _pngWithChunks([
      _textChunk('chara', first),
      _textChunk('chara', first),
      _textChunk('ccv3', second),
    ]);

    final parsed = parser.parse(bytes, fileName: 'dual.png');
    expect(parsed.characterCard?.name, 'CCV3 Mira');
    expect(parsed.warnings, contains(contains('重复 metadata')));
    expect(parsed.warnings, contains(contains('优先使用 ccv3')));
  });

  test('preserves unknown extensions and blocks executable-looking data', () {
    final source = _characterCard(version: 3);
    final data = source['data']! as Map<String, Object?>;
    data['extensions'] = {
      'future_ibuki_test': {'value': 7},
      'xiaobaix-tasks': [
        {'name': 'panel', 'script': 'document.querySelector("#x")'},
      ],
      'remote_theme': 'https://invalid.example/theme.css',
      'credential': ['Bearer', 'TEST_ONLY_TOKEN_1234567890'].join(' '),
    };

    final parsed = parser.parse(_jsonBytes(source), fileName: 'complex.json');

    expect(parsed.unsupportedPayload['extensions'], isA<Map>());
    expect(parsed.extensionSummaries, hasLength(4));
    expect(
      parsed.extensionSummaries
          .firstWhere((item) => item.key == 'xiaobaix-tasks')
          .kind,
      SillyTavernExtensionKind.scriptLike,
    );
    expect(parsed.security.scriptLikePaths, isNotEmpty);
    expect(parsed.security.remoteReferencePaths, isNotEmpty);
    expect(parsed.security.secretLikePaths, isNotEmpty);
    expect(
      jsonEncode(parsed.unsupportedPayload),
      isNot(contains('TEST_ONLY_TOKEN')),
    );
    expect(parsed.warnings, contains(contains('不会执行')));
  });

  test('parses standalone lorebook and retains advanced rules', () {
    final parsed = parser.parse(
      _jsonBytes({
        'name': 'Chaldea',
        'entries': {
          '0': {
            'uid': 5,
            'comment': 'Cafeteria',
            'content': 'The cafeteria is open at night.',
            'key': ['cafeteria'],
            'constant': false,
            'sticky': 3,
          },
          '1': {
            'uid': 6,
            'comment': 'Base',
            'content': 'Chaldea is a secure base.',
            'constant': true,
          },
        },
      }),
      fileName: 'world-info.json',
    );

    expect(parsed.kind, SillyTavernAssetKind.lorebook);
    expect(parsed.lorebook?.entries, hasLength(2));
    expect(parsed.lorebook?.entries.first.unsupported['sticky'], 3);
    expect(parsed.warnings, contains(contains('当前版本暂不执行')));
  });

  test('only explicitly identified Persona is accepted', () {
    final parsed = parser.parse(
      _jsonBytes({
        'spec': 'sillytavern_persona',
        'version': '1',
        'name': 'Rin',
        'description': 'Chaldea Master',
        'avatar': 'rin.png',
      }),
      fileName: 'persona.json',
    );
    expect(parsed.kind, SillyTavernAssetKind.persona);
    expect(parsed.persona?.name, 'Rin');

    expect(
      () => parser.parse(
        _jsonBytes({'name': 'Not a persona', 'description': 'ambiguous'}),
        fileName: 'unknown.json',
      ),
      throwsA(isA<SillyTavernParseException>()),
    );
  });

  test(
    'recognizes official single Persona backup without guessing a bundle selection',
    () {
      final parsed = parser.parse(
        _jsonBytes({
          'personas': {'rin.png': 'Rin'},
          'persona_descriptions': {
            'rin.png': {'description': 'Master', 'position': 0, 'future': 5},
          },
          'default_persona': 'rin.png',
        }),
        fileName: 'personas_backup.json',
      );
      expect(parsed.persona!.name, 'Rin');
      expect(parsed.persona!.avatarReference, 'rin.png');
      expect(jsonEncode(parsed.unsupportedPayload), contains('future'));
      expect(
        () => parser.parse(
          _jsonBytes({
            'personas': {'a.png': 'A', 'b.png': 'B'},
            'persona_descriptions': {
              'a.png': {'description': 'A'},
              'b.png': {'description': 'B'},
            },
          }),
          fileName: 'bundle.json',
        ),
        throwsA(isA<SillyTavernParseException>()),
      );
    },
  );

  test(
    'maps prompt preset as candidates without applying provider options',
    () {
      final parsed = parser.parse(
        _jsonBytes({
          'spec': 'sillytavern_preset',
          'name': 'RP preset',
          'main_prompt': 'World style',
          'post_history_instructions': 'Late instruction',
          'authors_note': 'Short scenes',
          'temperature': 0.9,
          'provider_token': ['sk', 'TEST_ONLY_ABCDEFGHIJKLMNOP'].join('-'),
        }),
        fileName: 'preset.json',
      );
      expect(parsed.kind, SillyTavernAssetKind.promptPreset);
      expect(parsed.promptPreset?.mainPrompt, 'World style');
      expect(parsed.promptPreset?.generationParameters['temperature'], 0.9);
      expect(
        jsonEncode(parsed.unsupportedPayload),
        isNot(contains('ABCDEFGHIJKLMNOP')),
      );
    },
  );

  test('future Character Card version parses common fields with warning', () {
    final source = _characterCard(version: 4);
    final parsed = parser.parse(_jsonBytes(source), fileName: 'future.json');
    expect(parsed.characterCard?.name, 'Mira');
    expect(parsed.warnings, contains(contains('未来版本')));
  });

  test('malformed PNG, bad Base64, and bad JSON fail without raw crash', () {
    expect(
      () => parser.parse(
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1]),
        fileName: 'bad.png',
      ),
      throwsA(isA<SillyTavernParseException>()),
    );
    expect(
      () => parser.parse(_pngWithText('ccv3', '%%%'), fileName: 'base64.png'),
      throwsA(isA<SillyTavernParseException>()),
    );
    expect(
      () => parser.parse(
        Uint8List.fromList(utf8.encode('{no')),
        fileName: 'bad.json',
      ),
      throwsA(isA<SillyTavernParseException>()),
    );
  });

  test(
    'import plan persists native character and lazy compatibility payload',
    () async {
      final fixture = await _ImportFixture.create();
      final sourceBytes = _pngWithText(
        'ccv3',
        base64Encode(_jsonBytes(_characterCard(version: 3))),
      );
      final inspection = await fixture.service.inspect(
        _MemorySource('mira.png', sourceBytes),
      );
      final plan = await fixture.service.buildPlan(
        inspection: inspection,
        destination: const SillyTavernImportDestination(projectId: 'project'),
      );
      final result = await fixture.service.execute(plan);

      expect(result.character?.mode, isNull);
      expect(result.character?.sourceFormat, 'chara_card_v3');
      expect(result.character?.avatarReference, startsWith('memory://'));
      expect(
        (await fixture.characters.listCharacters('project')),
        hasLength(1),
      );
      final payload = await fixture.compatibility.getPayload(result.payload.id);
      expect(payload.normalizedPayload['alternateGreetings'], hasLength(2));
      expect(payload.unsupportedPayload['extensions'], isA<Map>());

      final duplicate = await fixture.service.inspect(
        _MemorySource('mira-copy.png', sourceBytes),
      );
      final duplicatePlan = await fixture.service.buildPlan(
        inspection: duplicate,
        destination: const SillyTavernImportDestination(projectId: 'project'),
      );
      expect(duplicatePlan.canImport, isFalse);
      expect(duplicatePlan.conflicts, contains(contains('已经导入')));
    },
  );

  test('lore and Persona import become native World data', () async {
    final fixture = await _ImportFixture.create();
    final loreInspection = await fixture.service.inspect(
      _MemorySource(
        'lore.json',
        _jsonBytes({
          'name': 'World Info',
          'entries': [
            {'name': 'Always', 'content': 'A', 'constant': true},
            {
              'name': 'Keyword',
              'content': 'B',
              'keys': ['tea'],
            },
          ],
        }),
      ),
    );
    final lorePlan = await fixture.service.buildPlan(
      inspection: loreInspection,
      destination: SillyTavernImportDestination(worldId: fixture.worldId),
    );
    final lore = await fixture.service.execute(lorePlan);
    expect(lore.worldBook!.worldId, isNull);
    expect(
      (await fixture.worlds.listWorldBookReferences(
        fixture.worldId,
      )).single.worldBookId,
      lore.worldBook!.id,
    );
    final entries = await fixture.worlds.listLoreEntries(lore.worldBook!.id);
    expect(
      entries.map((item) => item.activationMode),
      unorderedEquals([LoreActivationMode.always, LoreActivationMode.keyword]),
    );

    final personaInspection = await fixture.service.inspect(
      _MemorySource(
        'persona.json',
        _jsonBytes({
          'spec': 'sillytavern_persona',
          'name': 'Rin',
          'description': 'Master',
        }),
      ),
    );
    final personaPlan = await fixture.service.buildPlan(
      inspection: personaInspection,
      destination: SillyTavernImportDestination(worldId: fixture.worldId),
    );
    final persona = await fixture.service.execute(personaPlan);
    expect(persona.persona?.metadata['knowledgeVisibility'], {
      'description': 'public',
    });
    expect(await fixture.worlds.listPersonas(fixture.worldId), hasLength(1));
  });
  test(
    'native fields and named credentials are sanitized before mapping',
    () async {
      final source = _characterCard(version: 3);
      final data = source['data']! as Map<String, Object?>;
      final secret = ['Bearer', 'TEST_ONLY_TOKEN_1234567890'].join(' ');
      data['description'] = 'Description $secret';
      data['system_prompt'] = secret;
      data['extensions'] = {'api_key': 'short-sensitive-value'};
      final fixture = await _ImportFixture.create();
      final inspection = await fixture.service.inspect(
        _MemorySource('secret.json', _jsonBytes(source)),
      );
      final result = await fixture.service.execute(
        await fixture.service.buildPlan(
          inspection: inspection,
          destination: const SillyTavernImportDestination(projectId: 'project'),
        ),
      );
      expect(result.character!.content, isNot(contains('TEST_ONLY_TOKEN')));
      final saved = await fixture.compatibility.getPayload(result.payload.id);
      expect(
        jsonEncode(saved.normalizedPayload),
        isNot(contains('TEST_ONLY_TOKEN')),
      );
      expect(
        jsonEncode(saved.unsupportedPayload),
        isNot(contains('short-sensitive-value')),
      );
      expect(saved.securityFlags, isNotEmpty);
    },
  );

  test(
    'retains raw lore rules and correctly normalizes percent and numeric ids',
    () {
      final parsed = parser.parse(
        _jsonBytes({
          'name': 'Rules',
          'entries': [
            {
              'uid': 17,
              'content': 'Tea',
              'probability': 1,
              'future_rule': {'enabled': true},
            },
          ],
        }),
        fileName: 'lore.json',
      );
      expect(parsed.lorebook!.entries.single.id, '17');
      expect(parsed.lorebook!.entries.single.probability, 0.01);
      expect(jsonEncode(parsed.unsupportedPayload), contains('future_rule'));
      final preset = parser.parse(
        _jsonBytes({
          'spec': 'sillytavern_preset',
          'prompts': [
            {'identifier': 'future_section', 'content': 'Preserve me'},
          ],
          'prompt_order': [
            {'future_order': 12},
          ],
        }),
        fileName: 'preset.json',
      );
      expect(jsonEncode(preset.unsupportedPayload), contains('Preserve me'));
      expect(preset.unsupportedPayload, contains('prompt_order'));
    },
  );

  test('rejects oversized images, bad UTF8 and deeply nested payloads', () {
    final bytes = _pngWithText(
      'ccv3',
      base64Encode(_jsonBytes(_characterCard(version: 3))),
    );
    ByteData.sublistView(bytes).setUint32(16, 9000);
    expect(
      () => parser.parse(bytes, fileName: 'large.png'),
      throwsA(isA<SillyTavernParseException>()),
    );
    expect(
      () =>
          parser.parse(Uint8List.fromList([0xff, 0xfe]), fileName: 'bad.json'),
      throwsA(isA<SillyTavernParseException>()),
    );
    Object nested = 'leaf';
    for (var i = 0; i < 70; i++) {
      nested = {'next': nested};
    }
    expect(
      () => parser.parse(
        _jsonBytes({'spec': 'chara_card_v3', 'data': nested}),
        fileName: 'nested.json',
      ),
      throwsA(isA<SillyTavernParseException>()),
    );
    const tinyParser = SillyTavernParser(
      limits: SillyTavernParserLimits(maxEmbeddedMetadataBytes: 16),
    );
    expect(
      () => tinyParser.parse(
        _jsonBytes(_characterCard(version: 3)),
        fileName: 'large.json',
      ),
      throwsA(isA<SillyTavernParseException>()),
    );
  });

  test(
    'first character import creates its collection in the same write',
    () async {
      final fixture = await _ImportFixture.create();
      final inspection = await fixture.service.inspect(
        _MemorySource('first.json', _jsonBytes(_characterCard(version: 3))),
      );
      final plan = await fixture.service.buildPlan(
        inspection: inspection,
        destination: const SillyTavernImportDestination(
          newProjectTitle: 'Character collection',
        ),
      );
      expect(plan.project, isNotNull);
      final result = await fixture.service.execute(plan);
      expect(
        (await fixture.projects.getProject(plan.project!.id)).title,
        'Character collection',
      );
      expect(result.character!.projectId, plan.project!.id);
    },
  );

  test(
    'onboarding consumes deferred Persona and Lore with native cast and prompt isolation',
    () async {
      final fixture = await _ImportFixture.create();
      final ids = <String>{};
      for (final name in ['Mira', 'Morgan']) {
        final inspection = await fixture.service.inspect(
          _MemorySource(
            '$name.json',
            _jsonBytes(_characterCard(version: 3, name: name)),
          ),
        );
        final result = await fixture.service.execute(
          await fixture.service.buildPlan(
            inspection: inspection,
            destination: const SillyTavernImportDestination(
              projectId: 'project',
            ),
          ),
        );
        ids.add(result.character!.id);
      }
      final persona = SillyTavernStoryImport(
        inspection: await fixture.service.inspect(
          _MemorySource(
            'persona.json',
            _jsonBytes({
              'spec': 'sillytavern_persona',
              'name': 'Rin',
              'description': 'Hidden identity',
              'avatar': 'file:///private/secret.png',
              'future_persona': 4,
            }),
          ),
        ),
        personaVisibility: SillyTavernPersonaVisibility.directorOnly,
      );
      final lore = SillyTavernStoryImport(
        inspection: await fixture.service.inspect(
          _MemorySource(
            'lore.json',
            _jsonBytes({
              'name': 'Tea Book',
              'entries': [
                {
                  'content': 'Tea is warm.',
                  'keys': ['tea'],
                  'constant': false,
                },
              ],
            }),
          ),
        ),
        personaVisibility: SillyTavernPersonaVisibility.public,
      );
      final start = StartRoleplayStory(
        worlds: fixture.worldService,
        imports: fixture.service,
      );
      final session = await start(
        worldName: 'New story',
        personaImport: persona,
        lorebookImport: lore,
        characterCardIds: ids,
        sceneName: 'Cafe',
      );
      final player = await fixture.worlds.getPlayerInstance(
        session.currentPlayerInstanceId!,
      );
      final template = await fixture.worlds.getPersona(player.playerPersonaId);
      expect(template.name, 'Rin');
      expect(template.avatarReference, isNull);
      expect(template.metadata['knowledgeVisibility'], {
        'description': 'directorOnly',
      });
      expect(
        await fixture.worlds.listSceneCast(session.currentSceneId!),
        hasLength(2),
      );
      expect(session.currentBranchId, isNotNull);
      final builder = WorldRoleplayContextBuilder(
        worlds: fixture.worlds,
        characters: fixture.characters,
        compatibility: fixture.compatibility,
      );
      final snapshot = await builder.build(
        worldSessionId: session.id,
        userAction: 'tea',
      );
      expect(snapshot.lore.entries.single.content, 'Tea is warm.');
      expect(
        snapshot.characterCompatibility.values.first.systemPrompt,
        'Keep her voice calm.',
      );
      expect(
        snapshot.context.directorSystemPrompt,
        isNot(contains('Keep her voice calm.')),
      );
      final second = await start(
        worldId: session.worldId,
        worldName: 'ignored',
        personaId: template.id,
        characterCardIds: ids,
        worldBookIds: {},
        sceneName: 'Second',
      );
      expect(
        (await builder.build(
          worldSessionId: second.id,
          userAction: 'tea',
        )).lore.entries,
        isEmpty,
      );
      expect(
        second.currentPlayerInstanceId,
        isNot(session.currentPlayerInstanceId),
      );
      expect(
        (await builder.build(
          worldSessionId: session.id,
          userAction: 'tea',
        )).lore.entries,
        hasLength(1),
      );
    },
  );

  test('failed story setup removes only newly created story data', () async {
    final fixture = await _ImportFixture.create();
    final oldSessions = await fixture.worlds.listSessions(fixture.worldId);
    final start = StartRoleplayStory(
      worlds: fixture.worldService,
      imports: fixture.service,
    );
    await expectLater(
      start(
        worldId: fixture.worldId,
        worldName: '',
        personaName: 'Transient',
        characterCardIds: {'does-not-exist'},
        worldBookIds: {'foreign-book'},
        sceneName: 'Cafe',
      ),
      throwsArgumentError,
    );
    expect(
      (await fixture.worlds.listSessions(fixture.worldId)).map((s) => s.id),
      oldSessions.map((s) => s.id),
    );
    expect(await fixture.worlds.listPersonas(fixture.worldId), isEmpty);
    expect(await fixture.compatibility.listPayloads(), isEmpty);
  });

  test(
    'private import files cannot overwrite or escape their namespace',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ibuki_import_paths_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final assets = FileSillyTavernImportAssetStore(directory);
      final path = await assets.saveCharacterImage(
        'owned',
        Uint8List.fromList([1, 2, 3]),
      );
      await expectLater(
        assets.saveCharacterImage('owned', Uint8List.fromList([4])),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        assets.saveCharacterImage('../escape', Uint8List(0)),
        throwsA(isA<FileSystemException>()),
      );
      final outside = File('${directory.path}/unrelated.txt');
      await outside.writeAsString('keep');
      await expectLater(
        assets.deleteAsset(outside.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await outside.readAsString(), 'keep');
      expect(await File(path).readAsBytes(), [1, 2, 3]);
      await assets.deleteAsset(path);
      expect(await File(path).exists(), isFalse);
    },
  );
}

class _ImportFixture {
  const _ImportFixture({
    required this.service,
    required this.characters,
    required this.compatibility,
    required this.worlds,
    required this.worldId,
    required this.projects,
  });

  final SillyTavernImportService service;
  final InMemoryCharacterRepository characters;
  final InMemoryCompatibilityImportRepository compatibility;
  final InMemoryWorldRoleplayRepository worlds;
  final String worldId;
  final InMemoryProjectRepository projects;
  WorldRoleplayService get worldService => WorldRoleplayService(
    repository: worlds,
    ids: EntityIdGenerator(),
    clock: const UtcClock(),
  );

  static Future<_ImportFixture> create() async {
    final store = InMemoryIbukiStore();
    final projects = InMemoryProjectRepository(store);
    final characters = InMemoryCharacterRepository(store);
    final worlds = InMemoryWorldRoleplayRepository(store);
    final compatibility = InMemoryCompatibilityImportRepository(
      coreStore: store,
      worlds: worlds,
    );
    await projects.upsertProject(
      Project(
        metadata: _metadata('project'),
        title: 'Story Project',
        description: '',
      ),
    );
    final worldService = WorldRoleplayService(
      repository: worlds,
      ids: EntityIdGenerator(),
      clock: const UtcClock(),
    );
    final world = await worldService.createWorld(name: 'Chaldea');
    return _ImportFixture(
      service: SillyTavernImportService(
        repository: compatibility,
        projects: projects,
        characters: characters,
        worlds: worlds,
        assets: InMemorySillyTavernImportAssetStore(),
        ids: EntityIdGenerator(),
        clock: const UtcClock(),
      ),
      characters: characters,
      compatibility: compatibility,
      worlds: worlds,
      worldId: world.world.id,
      projects: projects,
    );
  }
}

class _MemorySource implements SillyTavernImportSource {
  const _MemorySource(this.fileName, this.bytes);

  @override
  final String fileName;
  final Uint8List bytes;

  @override
  Future<int> length() async => bytes.length;

  @override
  Stream<List<int>> openRead() => Stream.value(bytes);
}

Map<String, Object?> _characterCard({
  required int version,
  String name = 'Mira',
}) {
  return {
    'spec': 'chara_card_v$version',
    'spec_version': '$version.0',
    'data': <String, Object?>{
      'name': name,
      'description': 'A quiet knight.',
      'personality': 'Calm',
      'scenario': 'A late evening.',
      'first_mes': 'Welcome home.',
      'mes_example': '<START>\n{{char}}: Tea?',
      'creator_notes': 'Synthetic fixture',
      'system_prompt': 'Keep her voice calm.',
      'post_history_instructions': 'Stay in character.',
      'alternate_greetings': ['Good morning.', 'Hey.'],
      'tags': ['fixture'],
      'creator': 'IbukiHome Tests',
      'character_version': '1.0',
      'extensions': {
        'future_ibuki_test': {'kept': true},
      },
      'character_book': {
        'name': 'Mira Lore',
        'entries': [
          {'id': 1, 'name': 'Always', 'content': 'A', 'constant': true},
          {
            'id': 2,
            'name': 'Tea',
            'content': 'B',
            'keys': ['tea'],
          },
        ],
      },
    },
  };
}

Uint8List _jsonBytes(Object value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

Uint8List _pngWithText(String key, String value) =>
    _pngWithChunks([_textChunk(key, value)]);

Uint8List _pngWithChunks(List<Uint8List> chunks) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  final output = BytesBuilder()
    ..add(signature)
    ..add(
      _chunk(
        'IHDR',
        (ByteData(13)
              ..setUint32(0, 1)
              ..setUint32(4, 1))
            .buffer
            .asUint8List(),
      ),
    )
    ..add(chunks.expand((item) => item).toList())
    ..add(_chunk('IEND', Uint8List(0)));
  return output.takeBytes();
}

Uint8List _textChunk(String key, String value) => _chunk(
  'tEXt',
  Uint8List.fromList([...latin1.encode(key), 0, ...latin1.encode(value)]),
);

Uint8List _chunk(String type, Uint8List data) {
  final output = BytesBuilder();
  final length = ByteData(4)..setUint32(0, data.length, Endian.big);
  output
    ..add(length.buffer.asUint8List())
    ..add(ascii.encode(type))
    ..add(data)
    ..add(
      (ByteData(4)..setUint32(0, getCrc32([...ascii.encode(type), ...data])))
          .buffer
          .asUint8List(),
    );
  return output.takeBytes();
}

EntityMetadata _metadata(String id) {
  final now = DateTime.utc(2026, 9, 1);
  return EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);
}
