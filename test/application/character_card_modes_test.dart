import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/characters/create_character_card.dart';
import 'package:ibukihome/application/characters/save_character_card.dart';
import 'package:ibukihome/data/memory/in_memory_character_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';

void main() {
  group('CharacterCard modes', () {
    test('fanfic fields round-trip through JSON', () {
      final card = _fanfic();
      expect(CharacterCard.fromJson(card.toJson()), card);
      expect(card.mode, CharacterCardMode.fanfic);
      expect(card.sourceWorkTitle, '原作');
      expect(card.sourceCharacterName, '角色A');
      expect(card.sourceVersionHint, '通常形态');
      expect(card.fanficAdaptationNotes, '本作穿白色大衣');
    });

    test('original idea round-trips through JSON', () {
      final card = _fanfic().copyWith(
        mode: CharacterCardMode.original,
        name: '原创角色',
        originalIdea: '懒散但可靠的短发少女',
      );
      final restored = CharacterCard.fromJson(card.toJson());
      expect(restored.mode, CharacterCardMode.original);
      expect(restored.originalIdea, '懒散但可靠的短发少女');
    });

    test('legacy JSON remains unclassified', () {
      final json = _fanfic().toJson()
        ..remove('mode')
        ..remove('source_work_title')
        ..remove('source_character_name')
        ..remove('source_version_hint')
        ..remove('fanfic_adaptation_notes')
        ..remove('original_idea');
      final restored = CharacterCard.fromJson(json);
      expect(restored.mode, isNull);
      expect(restored.sourceWorkTitle, '');
      expect(restored.originalIdea, '');
    });

    test('fanfic requires work and source character names', () async {
      final fixture = _Fixture();
      expect(
        () => fixture.create(
          projectId: 'project',
          name: '角色',
          content: '',
          id: 'card',
          nowUtc: _now,
          mode: CharacterCardMode.fanfic,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('original permits an empty provisional name', () async {
      final fixture = _Fixture();
      final card = await fixture.create(
        projectId: 'project',
        name: '',
        content: '',
        id: 'card',
        nowUtc: _now,
        mode: CharacterCardMode.original,
        originalIdea: '一个可靠的角色',
      );
      expect(card.name, '未命名角色');
      expect(card.mode, CharacterCardMode.original);
    });

    test(
      'fanfic uses the source character name when display name is empty',
      () async {
        final fixture = _Fixture();
        final card = await fixture.create(
          projectId: 'project',
          name: '',
          content: '',
          id: 'fanfic',
          nowUtc: _now,
          mode: CharacterCardMode.fanfic,
          sourceWorkTitle: '原作',
          sourceCharacterName: '原作角色',
        );
        expect(card.name, '原作角色');
      },
    );

    test('saving a fanfic keeps the author override intact', () async {
      final fixture = _Fixture();
      await fixture.characters.upsertCharacter(_fanfic());
      final updated = await fixture.save(
        projectId: 'project',
        characterId: 'character',
        name: '角色A',
        content: '冷静寡言，穿白色大衣。',
        fanficAdaptationNotes: '本作性格沉静，不使用原作服装。',
        nowUtc: _now.add(const Duration(minutes: 1)),
      );
      expect(updated.content, contains('白色大衣'));
      expect(updated.fanficAdaptationNotes, contains('不使用原作服装'));
    });

    test('changing a card never changes another card', () async {
      final fixture = _Fixture();
      await fixture.characters.upsertCharacter(_fanfic());
      await fixture.characters.upsertCharacter(
        _fanfic().copyWith(
          metadata: _metadata('other'),
          name: '独立角色',
          sortOrder: 1,
        ),
      );
      await fixture.save(
        projectId: 'project',
        characterId: 'character',
        name: '已修改',
        content: '新内容',
        nowUtc: _now.add(const Duration(minutes: 1)),
      );
      expect((await fixture.characters.getCharacter('other')).name, '独立角色');
    });
  });
}

class _Fixture {
  _Fixture() {
    store.putProject(
      Project(metadata: _metadata('project'), title: '作品', description: ''),
    );
    create = CreateCharacterCard(projects, characters);
    save = SaveCharacterCard(characters);
  }

  final store = InMemoryIbukiStore();
  late final projects = InMemoryProjectRepository(store);
  late final characters = InMemoryCharacterRepository(store);
  late final CreateCharacterCard create;
  late final SaveCharacterCard save;
}

CharacterCard _fanfic() => CharacterCard(
  metadata: _metadata('character'),
  projectId: 'project',
  name: '角色A',
  content: '用户当前设定',
  sortOrder: 0,
  mode: CharacterCardMode.fanfic,
  sourceWorkTitle: '原作',
  sourceCharacterName: '角色A',
  sourceVersionHint: '通常形态',
  fanficAdaptationNotes: '本作穿白色大衣',
);

EntityMetadata _metadata(String id) =>
    EntityMetadata(id: id, createdAt: _now, updatedAt: _now, revision: 1);

final _now = DateTime.utc(2026, 8, 13);
