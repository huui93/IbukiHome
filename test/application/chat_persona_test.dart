import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/chat/create_chat_persona.dart';
import 'package:ibukihome/application/chat/create_chat_session.dart';
import 'package:ibukihome/application/chat/open_persona_chat.dart';
import 'package:ibukihome/application/chat/save_chat_persona.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_character_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_persona_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';

void main() {
  group('ChatPersona domain', () {
    test('simple persona JSON round-trips', () {
      final persona = _persona('p1');
      expect(ChatPersona.fromJson(persona.toJson()), persona);
    });

    test('detailed persona JSON round-trips', () {
      final persona = _persona(
        'p1',
        mode: ChatPersonaDescriptionMode.detailed,
        identity: '旅店老板',
      );
      expect(ChatPersona.fromJson(persona.toJson()), persona);
    });

    test('copyWith preserves advanced fields in simple mode', () {
      final detailed = _persona(
        'p1',
        mode: ChatPersonaDescriptionMode.detailed,
        identity: '旅店老板',
      );
      final simple = detailed.copyWith(
        descriptionMode: ChatPersonaDescriptionMode.simple,
      );
      expect(simple.coreIdentity, '旅店老板');
    });

    test('legacy JSON defaults description mode to simple', () {
      final json = _persona('p1').toJson()..remove('description_mode');
      expect(
        ChatPersona.fromJson(json).descriptionMode,
        ChatPersonaDescriptionMode.simple,
      );
    });

    test('ChatSession JSON round-trips personaId', () {
      final session = _session('s1', personaId: 'p1');
      expect(ChatSession.fromJson(session.toJson()), session);
    });

    test('legacy ChatSession JSON keeps personaId null', () {
      final json = _session('s1').toJson()..remove('persona_id');
      expect(ChatSession.fromJson(json).personaId, isNull);
    });

    test('ChatSession can preserve legacy character and persona snapshot', () {
      final session = _session('s1', personaId: 'p1', characterId: 'c1');
      expect(session.characterId, 'c1');
      expect(session.personaId, 'p1');
    });
  });

  group('ChatPersona application flow', () {
    test('creates a simple persona', () async {
      final fixture = await _Fixture.create();
      final persona = await fixture.createPersona(
        id: 'p1',
        name: ' 小铃 ',
        descriptionMode: ChatPersonaDescriptionMode.simple,
        shortDescription: ' 懒散但亲近 ',
        speakingStyle: ' 短句 ',
        nowUtc: _t1,
      );
      expect(persona.name, '小铃');
      expect(persona.shortDescription, '懒散但亲近');
      expect(persona.revision, 1);
    });

    test('empty persona name fails', () async {
      final fixture = await _Fixture.create();
      expect(
        fixture.createPersona(
          id: 'p1',
          name: '   ',
          descriptionMode: ChatPersonaDescriptionMode.simple,
          shortDescription: '',
          speakingStyle: '',
          nowUtc: _t1,
        ),
        throwsA(isA<DataFormatException>()),
      );
    });

    test('updates a persona and increments revision', () async {
      final fixture = await _Fixture.create(persona: true);
      final updated = await fixture.save(
        personaId: 'p1',
        name: '新名字',
        descriptionMode: ChatPersonaDescriptionMode.simple,
        shortDescription: '新描写',
        speakingStyle: '自然',
        nowUtc: _t1,
      );
      expect(updated.name, '新名字');
      expect(updated.revision, 2);
    });

    test('simple to detailed retains basic content', () async {
      final fixture = await _Fixture.create(persona: true);
      final updated = await fixture.save(
        personaId: 'p1',
        name: '小铃',
        descriptionMode: ChatPersonaDescriptionMode.detailed,
        shortDescription: '懒散但亲近',
        speakingStyle: '短句',
        coreIdentity: '旧友',
        nowUtc: _t1,
      );
      expect(updated.shortDescription, '懒散但亲近');
      expect(updated.coreIdentity, '旧友');
    });

    test('detailed to simple does not erase advanced content', () async {
      final fixture = await _Fixture.create(detailedPersona: true);
      final stored = await fixture.personas.getPersona('p1');
      final updated = await fixture.save(
        personaId: 'p1',
        name: stored.name,
        descriptionMode: ChatPersonaDescriptionMode.simple,
        shortDescription: stored.shortDescription,
        speakingStyle: stored.speakingStyle,
        coreIdentity: stored.coreIdentity,
        nowUtc: _t1,
      );
      expect(updated.coreIdentity, '旅店老板');
    });

    test('soft delete hides persona by default', () async {
      final fixture = await _Fixture.create(persona: true);
      await fixture.personas.softDeletePersona('p1', _t1);
      expect(await fixture.personas.listPersonas(), isEmpty);
      expect(
        await fixture.personas.listPersonas(includeDeleted: true),
        hasLength(1),
      );
    });

    test('restore returns persona to active list', () async {
      final fixture = await _Fixture.create(persona: true);
      await fixture.personas.softDeletePersona('p1', _t1);
      await fixture.personas.restorePersona('p1', _t2);
      expect(await fixture.personas.listPersonas(), hasLength(1));
    });

    test('deleting CharacterCard does not delete ChatPersona', () async {
      final fixture = await _Fixture.create(persona: true, character: true);
      await fixture.characters.softDeleteCharacter('c1', _t1);
      expect((await fixture.personas.getPersona('p1')).deletedAt, isNull);
    });

    test('deleting ChatPersona does not delete CharacterCard', () async {
      final fixture = await _Fixture.create(persona: true, character: true);
      await fixture.personas.softDeletePersona('p1', _t1);
      expect((await fixture.characters.getCharacter('c1')).deletedAt, isNull);
    });

    test(
      'editing novel data does not change an independent chat persona',
      () async {
        final fixture = await _Fixture.create(persona: true, character: true);
        final before = await fixture.personas.getPersona('p1');
        final character = await fixture.characters.getCharacter('c1');
        await fixture.characters.upsertCharacter(
          character.copyWith(content: 'Changed novel content'),
        );
        expect(await fixture.personas.getPersona('p1'), before);
      },
    );

    test('opening Persona creates a persona-bound session', () async {
      final fixture = await _Fixture.create(persona: true);
      final session = await fixture.open(
        personaId: 'p1',
        newSessionId: 's1',
        nowUtc: _t1,
      );
      expect(session.personaId, 'p1');
      expect(session.characterId, isNull);
    });

    test('opening Persona reuses latest active session', () async {
      final fixture = await _Fixture.create(persona: true);
      await fixture.chats.upsertSession(
        _session('older', personaId: 'p1', updatedAt: _t0),
      );
      await fixture.chats.upsertSession(
        _session('latest', personaId: 'p1', updatedAt: _t1),
      );
      final session = await fixture.open(
        personaId: 'p1',
        newSessionId: 'unused',
        nowUtc: _t2,
      );
      expect(session.id, 'latest');
    });

    test('deleted Persona cannot create a new chat', () async {
      final fixture = await _Fixture.create(persona: true);
      await fixture.personas.softDeletePersona('p1', _t1);
      expect(
        fixture.open(personaId: 'p1', newSessionId: 's1', nowUtc: _t2),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('old sessions remain after Persona deletion', () async {
      final fixture = await _Fixture.create(persona: true);
      await fixture.chats.upsertSession(_session('s1', personaId: 'p1'));
      await fixture.personas.softDeletePersona('p1', _t1);
      expect((await fixture.chats.getSession('s1')).personaId, 'p1');
    });

    test('repository filters sessions by personaId', () async {
      final fixture = await _Fixture.create(persona: true);
      await fixture.personas.upsertPersona(_persona('p2'));
      await fixture.chats.upsertSession(_session('s1', personaId: 'p1'));
      await fixture.chats.upsertSession(_session('s2', personaId: 'p2'));
      expect(
        (await fixture.chats.listSessions(personaId: 'p2')).single.id,
        's2',
      );
    });

    test('existing session cannot change persona binding', () async {
      final fixture = await _Fixture.create(persona: true);
      await fixture.personas.upsertPersona(_persona('p2'));
      final session = _session('s1', personaId: 'p1');
      await fixture.chats.upsertSession(session);
      expect(
        fixture.chats.upsertSession(session.copyWith(personaId: 'p2')),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('Persona list ordering is stable by name then id', () async {
      final fixture = await _Fixture.create();
      await fixture.personas.upsertPersona(_persona('p2', name: 'A'));
      await fixture.personas.upsertPersona(_persona('p1', name: 'A'));
      expect((await fixture.personas.listPersonas()).map((item) => item.id), [
        'p1',
        'p2',
      ]);
    });
  });
}

final _t0 = DateTime.utc(2026, 8, 11, 8);
final _t1 = DateTime.utc(2026, 8, 11, 9);
final _t2 = DateTime.utc(2026, 8, 11, 10);

class _Fixture {
  _Fixture._();

  final store = InMemoryIbukiStore();
  late final projects = InMemoryProjectRepository(store);
  late final characters = InMemoryCharacterRepository(store);
  late final personas = InMemoryChatPersonaRepository(store);
  late final chats = InMemoryChatRepository(store);
  late final createPersona = CreateChatPersona(personas);
  late final save = SaveChatPersona(personas);
  late final createSession = CreateChatSession(chats, personas);
  late final open = OpenPersonaChat(personas, chats, createSession);

  static Future<_Fixture> create({
    bool persona = false,
    bool detailedPersona = false,
    bool character = false,
  }) async {
    final fixture = _Fixture._();
    await fixture.projects.upsertProject(
      Project(metadata: _metadata('project-1'), title: '小说', description: ''),
    );
    if (character) {
      await fixture.characters.upsertCharacter(
        CharacterCard(
          metadata: _metadata('c1'),
          projectId: 'project-1',
          name: '小说角色',
          content: '小说人物设定',
          sortOrder: 0,
        ),
      );
    }
    if (persona || detailedPersona) {
      await fixture.personas.upsertPersona(
        _persona(
          'p1',
          mode: detailedPersona
              ? ChatPersonaDescriptionMode.detailed
              : ChatPersonaDescriptionMode.simple,
          identity: detailedPersona ? '旅店老板' : '',
        ),
      );
    }
    return fixture;
  }
}

ChatPersona _persona(
  String id, {
  String name = '小铃',
  ChatPersonaDescriptionMode mode = ChatPersonaDescriptionMode.simple,
  String identity = '',
}) => ChatPersona(
  metadata: _metadata(id),
  name: name,
  descriptionMode: mode,
  shortDescription: '懒散但亲近',
  speakingStyle: '短句，自然',
  coreIdentity: identity,
);

ChatSession _session(
  String id, {
  String? personaId,
  String? characterId,
  DateTime? updatedAt,
}) => ChatSession(
  metadata: _metadata(id, updatedAt: updatedAt),
  projectId: null,
  personaId: personaId,
  characterId: characterId,
  title: id,
);

EntityMetadata _metadata(String id, {DateTime? updatedAt}) => EntityMetadata(
  id: id,
  createdAt: _t0,
  updatedAt: updatedAt ?? _t0,
  revision: 1,
);
