import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_chat_memory_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_chat_persona_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_chat_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_novel_memory_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_outline_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_project_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_reader_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:ibukihome/data/sqlite/sqlite_segment_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late _VersionFourFixture fixture;

  setUpAll(() async {
    sqfliteFfiInit();
    fixture = await _VersionFourFixture.create();
  });

  tearDownAll(() => fixture.dispose());

  test('schema version migrates from v4 to v5', () async {
    final db = await fixture.database.database;
    expect(await db.getVersion(), SqliteSchema.version);
    expect(SqliteSchema.version, 21);
  });

  test('v4 project and system prompt survive migration', () async {
    final project = await fixture.projects.getProject('project-1');
    expect(project.title, '旧项目');
    expect(project.systemPrompt, '保持第三人称叙事');
  });

  test('v4 segment and revision survive migration', () async {
    expect((await fixture.segments.getSegment('segment-1')).content, '当前正文');
    expect((await fixture.segments.getRevision('revision-1')).content, '旧版正文');
  });

  test('v4 outline survives migration', () async {
    final nodes = await fixture.outlines.listOutlineNodes('project-1');
    expect(nodes.single.title, '旧大纲');
    expect(nodes.single.status.name, 'current');
  });

  test('v4 CharacterCard and WorldCard rows survive migration', () async {
    final db = await fixture.database.database;
    expect((await db.query('character_cards')).single['name'], '旧角色');
    expect((await db.query('world_cards')).single['title'], '旧世界观');
  });

  test('v4 Persona gains safe memory defaults', () async {
    final persona = await fixture.personas.getPersona('persona-1');
    expect(persona.name, '旧聊天角色');
    expect(persona.autoMemoryEnabled, isTrue);
    expect(persona.useLongTermMemory, isTrue);
  });

  test('v4 ChatSession and ChatMessage survive migration', () async {
    final session = await fixture.chats.getSession('session-1');
    expect(session.personaId, 'persona-1');
    final messages = await fixture.chats.listMessages('session-1');
    expect(messages.single.content, '旧聊天消息');
  });

  test('v5 long-context tables start empty for old data', () async {
    expect(await fixture.novelMemory.listChunks('project-1'), isEmpty);
    expect(await fixture.novelMemory.getDigest('project-1'), isNull);
    expect(await fixture.chatMemory.listEntries('persona-1'), isEmpty);
    expect(await fixture.chatMemory.listSummaries('session-1'), isEmpty);
  });

  test('v5 reader defaults are safe for an old project', () async {
    final preferences = await fixture.reader.loadPreferences('project-1');
    final progress = await fixture.reader.loadProgress('project-1');
    expect(preferences.fontSize, 18);
    expect(progress.scrollOffset, 0);
    expect(progress.lastReadSegmentId, isNull);
  });

  test('migration creates all long-context indexes', () async {
    final db = await fixture.database.database;
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    );
    final names = rows.map((row) => row['name']);
    expect(names, contains('idx_novel_summary_chunks_project_range'));
    expect(names, contains('idx_chat_memory_entries_persona_updated'));
    expect(names, contains('idx_conversation_summaries_session_created'));
  });
}

class _VersionFourFixture {
  _VersionFourFixture._(this.directory, this.database)
    : projects = SQLiteProjectRepository(database),
      segments = SQLiteSegmentRepository(database),
      outlines = SQLiteOutlineRepository(database),
      personas = SQLiteChatPersonaRepository(database),
      chats = SQLiteChatRepository(database),
      novelMemory = SQLiteNovelMemoryRepository(database),
      chatMemory = SQLiteChatMemoryRepository(database),
      reader = SQLiteReaderRepository(database);

  final Directory directory;
  final IbukiDatabase database;
  final SQLiteProjectRepository projects;
  final SQLiteSegmentRepository segments;
  final SQLiteOutlineRepository outlines;
  final SQLiteChatPersonaRepository personas;
  final SQLiteChatRepository chats;
  final SQLiteNovelMemoryRepository novelMemory;
  final SQLiteChatMemoryRepository chatMemory;
  final SQLiteReaderRepository reader;

  static Future<_VersionFourFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'ibuki_v4_fixture_',
    );
    final path = p.join(directory.path, 'ibukihome.db');
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          await _createVersionFour(db);
          await _seedVersionFour(db);
        },
      ),
    );
    await old.close();
    final database = IbukiDatabase(
      pathResolver: () async => path,
      databaseFactory: databaseFactoryFfi,
    );
    await database.open();
    return _VersionFourFixture._(directory, database);
  }

  Future<void> dispose() async {
    await database.close();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

Future<void> _createVersionFour(Database db) async {
  for (var statement in SqliteSchema.createTableStatements) {
    if (_isVersionFiveTable(statement)) continue;
    if (statement.contains('CREATE TABLE chat_personas')) {
      statement = statement
          .replaceFirst(
            "  auto_memory_enabled INTEGER NOT NULL DEFAULT 1 CHECK (auto_memory_enabled IN (0, 1)),\n",
            '',
          )
          .replaceFirst(
            "  use_long_term_memory INTEGER NOT NULL DEFAULT 1 CHECK (use_long_term_memory IN (0, 1)),\n",
            '',
          );
    }
    await db.execute(statement);
  }
  for (final statement in SqliteSchema.createIndexStatements) {
    if (statement.contains('idx_novel_summary_chunks_') ||
        statement.contains('idx_chat_memory_entries_') ||
        statement.contains('idx_conversation_summaries_')) {
      continue;
    }
    await db.execute(statement);
  }
}

bool _isVersionFiveTable(String statement) =>
    statement.contains('CREATE TABLE novel_summary_chunks') ||
    statement.contains('CREATE TABLE story_memory_digests') ||
    statement.contains('CREATE TABLE reader_preferences') ||
    statement.contains('CREATE TABLE reader_progress') ||
    statement.contains('CREATE TABLE chat_memory_entries') ||
    statement.contains('CREATE TABLE conversation_summaries');

Future<void> _seedVersionFour(Database db) async {
  const at = '2026-08-12T08:00:00.000Z';
  await db.insert('projects', {
    'id': 'project-1',
    'title': '旧项目',
    'description': '旧说明',
    'system_prompt': '保持第三人称叙事',
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('segments', {
    'id': 'segment-1',
    'project_id': 'project-1',
    'order_index': 0,
    'content': '当前正文',
    'created_at': at,
    'updated_at': at,
    'revision': 2,
    'deleted_at': null,
  });
  await db.insert('segment_revisions', {
    'id': 'revision-1',
    'project_id': 'project-1',
    'segment_id': 'segment-1',
    'revision_number': 1,
    'content': '旧版正文',
    'note': '',
    'user_instruction': '',
    'mode': 'local_edit',
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('outline_nodes', {
    'id': 'outline-1',
    'project_id': 'project-1',
    'title': '旧大纲',
    'summary': '旧大纲摘要',
    'order_index': 0,
    'status': 'current',
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('character_cards', {
    'id': 'character-1',
    'project_id': 'project-1',
    'name': '旧角色',
    'content': '旧角色设定',
    'sort_order': 0,
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('world_cards', {
    'id': 'world-1',
    'project_id': 'project-1',
    'title': '旧世界观',
    'content': '旧世界观设定',
    'sort_order': 0,
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('chat_personas', {
    'id': 'persona-1',
    'name': '旧聊天角色',
    'avatar_reference': null,
    'description_mode': 'simple',
    'short_description': '旧角色描写',
    'speaking_style': '自然短句',
    'core_identity': '',
    'personality': '',
    'background': '',
    'relationship_to_user': '',
    'behavior_habits': '',
    'preferences': '',
    'scenario': '',
    'notes': '',
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('chat_sessions', {
    'id': 'session-1',
    'project_id': null,
    'character_id': null,
    'persona_id': 'persona-1',
    'title': '旧会话',
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('chat_messages', {
    'id': 'message-1',
    'session_id': 'session-1',
    'project_id': null,
    'role': 'user',
    'content': '旧聊天消息',
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  });
}
