import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_outline_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_project_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:ibukihome/domain/outline/outline_node.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  group('creation settings schema version 4', () {
    test('fresh schema stores project system prompt', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(
        project('project-1', systemPrompt: 'Keep the prose restrained.'),
      );
      final reopened = await reopenFixture(fixture);
      expect(
        (await reopened.projects.getProject('project-1')).systemPrompt,
        'Keep the prose restrained.',
      );
    });

    test('outline node and status persist across reopen', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-1'));
      await fixture.outlines.upsertOutlineNode(
        outlineNode('outline-1', 'project-1', 0),
      );
      await fixture.outlines.setOutlineNodeStatus(
        id: 'outline-1',
        status: OutlineNodeStatus.current,
        updatedAt: DateTime.utc(2026, 8, 12),
      );
      final reopened = await reopenFixture(fixture);
      expect(
        (await reopened.outlines.getOutlineNode('outline-1')).status,
        OutlineNodeStatus.current,
      );
    });

    test('switching current keeps exactly one current node', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-1'));
      await fixture.outlines.upsertOutlineNode(
        outlineNode('outline-1', 'project-1', 0),
      );
      await fixture.outlines.upsertOutlineNode(
        outlineNode('outline-2', 'project-1', 1),
      );
      await fixture.outlines.setOutlineNodeStatus(
        id: 'outline-1',
        status: OutlineNodeStatus.current,
        updatedAt: DateTime.utc(2026, 8, 12, 8),
      );
      await fixture.outlines.setOutlineNodeStatus(
        id: 'outline-2',
        status: OutlineNodeStatus.current,
        updatedAt: DateTime.utc(2026, 8, 12, 9),
      );

      final nodes = await fixture.outlines.listOutlineNodes('project-1');
      expect(
        nodes.where((node) => node.status == OutlineNodeStatus.current),
        hasLength(1),
      );
      expect(nodes[0].status, OutlineNodeStatus.planned);
      expect(nodes[1].status, OutlineNodeStatus.current);
    });

    test('reorder and soft delete remain persistent', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-1'));
      await fixture.outlines.upsertOutlineNode(
        outlineNode('outline-1', 'project-1', 0),
      );
      await fixture.outlines.upsertOutlineNode(
        outlineNode('outline-2', 'project-1', 1),
      );
      await fixture.outlines.reorderOutlineNodes(
        projectId: 'project-1',
        orderedIds: const ['outline-2', 'outline-1'],
        updatedAt: DateTime.utc(2026, 8, 12, 9),
      );
      await fixture.outlines.softDeleteOutlineNode(
        'outline-1',
        DateTime.utc(2026, 8, 12, 10),
      );
      final reopened = await reopenFixture(fixture);

      expect(
        (await reopened.outlines.listOutlineNodes('project-1')).single.id,
        'outline-2',
      );
      expect(
        await reopened.outlines.listOutlineNodes(
          'project-1',
          includeDeleted: true,
        ),
        hasLength(2),
      );
      expect(
        (await reopened.outlines.getOutlineNode('outline-1')).deletedAt,
        isNotNull,
      );
    });

    test('version 3 migration is non destructive', () async {
      final fixture = await _VersionThreeFixture.create();
      final db = await fixture.database.database;
      expect(await db.getVersion(), SqliteSchema.version);
      for (final table in [
        'projects',
        'segments',
        'segment_revisions',
        'character_cards',
        'world_cards',
        'chat_personas',
        'chat_sessions',
        'chat_messages',
      ]) {
        expect(await db.query(table), hasLength(1), reason: table);
      }
      expect(await db.query('outline_nodes'), isEmpty);
      expect(
        (await fixture.projects.getProject('project-1')).systemPrompt,
        isEmpty,
      );
    });

    test('version 3 project description remains unchanged', () async {
      final fixture = await _VersionThreeFixture.create();
      final stored = await fixture.projects.getProject('project-1');
      expect(stored.description, 'legacy project summary');
      expect(stored.systemPrompt, isEmpty);
    });
  });
}

class _VersionThreeFixture {
  _VersionThreeFixture(this.directory, this.database)
    : projects = SQLiteProjectRepository(database),
      outlines = SQLiteOutlineRepository(database);

  final Directory directory;
  final IbukiDatabase database;
  final SQLiteProjectRepository projects;
  final SQLiteOutlineRepository outlines;

  static Future<_VersionThreeFixture> create() async {
    final directory = await Directory.systemTemp.createTemp('ibuki_v3_');
    final path = p.join(directory.path, 'ibukihome.db');
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) => _createVersionThree(db),
      ),
    );
    await _seedVersionThree(old);
    await old.close();
    final database = IbukiDatabase(
      pathResolver: () async => path,
      databaseFactory: databaseFactoryFfi,
    );
    await database.open();
    final fixture = _VersionThreeFixture(directory, database);
    addTearDown(() async {
      await database.close();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    return fixture;
  }
}

Future<void> _createVersionThree(Database db) async {
  for (final statement in SqliteSchema.createTableStatements) {
    if (statement.contains('CREATE TABLE outline_nodes')) continue;
    if (statement.contains('CREATE TABLE novel_summary_chunks')) continue;
    if (statement.contains('CREATE TABLE story_memory_digests')) continue;
    if (statement.contains('CREATE TABLE reader_preferences')) continue;
    if (statement.contains('CREATE TABLE reader_progress')) continue;
    if (statement.contains('CREATE TABLE chat_memory_entries')) continue;
    if (statement.contains('CREATE TABLE conversation_summaries')) continue;
    if (statement.contains('CREATE TABLE projects')) {
      await db.execute('''
CREATE TABLE projects (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  deleted_at TEXT NULL
)
''');
    } else if (statement.contains('CREATE TABLE chat_personas')) {
      await db.execute('''
CREATE TABLE chat_personas (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  avatar_reference TEXT NULL,
  description_mode TEXT NOT NULL CHECK (description_mode IN ('simple', 'detailed')),
  short_description TEXT NOT NULL DEFAULT '',
  speaking_style TEXT NOT NULL DEFAULT '',
  core_identity TEXT NOT NULL DEFAULT '',
  personality TEXT NOT NULL DEFAULT '',
  background TEXT NOT NULL DEFAULT '',
  relationship_to_user TEXT NOT NULL DEFAULT '',
  behavior_habits TEXT NOT NULL DEFAULT '',
  preferences TEXT NOT NULL DEFAULT '',
  scenario TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  deleted_at TEXT NULL
)
''');
    } else {
      await db.execute(statement);
    }
  }
  for (final statement in SqliteSchema.createIndexStatements) {
    if (statement.contains('idx_outline_nodes_')) continue;
    if (statement.contains('idx_novel_summary_chunks_')) continue;
    if (statement.contains('idx_chat_memory_entries_')) continue;
    if (statement.contains('idx_conversation_summaries_')) continue;
    await db.execute(statement);
  }
}

Future<void> _seedVersionThree(Database db) async {
  const at = '2026-08-11T08:00:00.000Z';
  await db.insert('projects', {
    'id': 'project-1',
    'title': 'Legacy project',
    'description': 'legacy project summary',
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('segments', {
    'id': 'segment-1',
    'project_id': 'project-1',
    'order_index': 0,
    'content': 'legacy segment',
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('segment_revisions', {
    'id': 'revision-1',
    'project_id': 'project-1',
    'segment_id': 'segment-1',
    'revision_number': 1,
    'content': 'older segment',
    'note': '',
    'user_instruction': '',
    'mode': 'local_edit',
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('character_cards', {
    'id': 'character-1',
    'project_id': 'project-1',
    'name': 'Legacy character',
    'content': 'character details',
    'sort_order': 0,
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('world_cards', {
    'id': 'world-1',
    'project_id': 'project-1',
    'title': 'Legacy world',
    'content': 'world details',
    'sort_order': 0,
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('chat_personas', {
    'id': 'persona-1',
    'name': 'Legacy persona',
    'avatar_reference': null,
    'description_mode': 'simple',
    'short_description': 'persona details',
    'speaking_style': '',
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
    'project_id': 'project-1',
    'character_id': 'character-1',
    'persona_id': 'persona-1',
    'title': 'Legacy session',
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('chat_messages', {
    'id': 'message-1',
    'session_id': 'session-1',
    'project_id': 'project-1',
    'role': 'user',
    'content': 'legacy message',
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  });
}
