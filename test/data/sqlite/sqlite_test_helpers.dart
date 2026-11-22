import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_character_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_chat_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_chat_persona_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_project_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_outline_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_segment_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_world_repository.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/chat/chat_message.dart' as chat;
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/outline/outline_node.dart';
import 'package:ibukihome/domain/segments/segment.dart';
import 'package:ibukihome/domain/segments/segment_revision.dart';
import 'package:ibukihome/domain/world/world_card.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void ensureSqliteFfi() {
  sqfliteFfiInit();
}

class SqliteFixture {
  SqliteFixture._({
    required this.directory,
    required this.databasePath,
    required this.database,
  }) : projects = SQLiteProjectRepository(database),
       segments = SQLiteSegmentRepository(database),
       characters = SQLiteCharacterRepository(database),
       world = SQLiteWorldRepository(database),
       chatRepository = SQLiteChatRepository(database),
       personas = SQLiteChatPersonaRepository(database),
       outlines = SQLiteOutlineRepository(database);

  final Directory directory;
  final String databasePath;
  final IbukiDatabase database;
  final SQLiteProjectRepository projects;
  final SQLiteSegmentRepository segments;
  final SQLiteCharacterRepository characters;
  final SQLiteWorldRepository world;
  final SQLiteChatRepository chatRepository;
  final SQLiteChatPersonaRepository personas;
  final SQLiteOutlineRepository outlines;

  static Future<SqliteFixture> create({
    String fileName = 'ibukihome.db',
  }) async {
    ensureSqliteFfi();
    final directory = await Directory.systemTemp.createTemp(
      'ibukihome_sqlite_test_',
    );
    final databasePath = p.join(directory.path, fileName);
    final database = IbukiDatabase(
      pathResolver: () async => databasePath,
      databaseFactory: databaseFactoryFfi,
    );
    await database.open();
    final fixture = SqliteFixture._(
      directory: directory,
      databasePath: databasePath,
      database: database,
    );
    addTearDown(fixture.dispose);
    return fixture;
  }

  Future<void> dispose() async {
    await database.close();
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }

  Future<void> reopen() async {
    await database.close();
    throw StateError('Use reopenFixture for a fresh IbukiDatabase instance.');
  }
}

Future<SqliteFixture> reopenFixture(SqliteFixture oldFixture) async {
  final database = IbukiDatabase(
    pathResolver: () async => oldFixture.databasePath,
    databaseFactory: databaseFactoryFfi,
  );
  await database.open();
  final fixture = SqliteFixture._(
    directory: oldFixture.directory,
    databasePath: oldFixture.databasePath,
    database: database,
  );
  addTearDown(database.close);
  return fixture;
}

EntityMetadata metadata(
  String id, {
  DateTime? createdAt,
  DateTime? updatedAt,
  int revision = 1,
  DateTime? deletedAt,
}) {
  final created = createdAt ?? DateTime.utc(2026, 1, 1);
  return EntityMetadata(
    id: id,
    createdAt: created,
    updatedAt: updatedAt ?? created,
    revision: revision,
    deletedAt: deletedAt,
  );
}

Project project(
  String id, {
  String? title,
  String description = 'description',
  String systemPrompt = '',
  DateTime? updatedAt,
}) {
  return Project(
    metadata: metadata(id, updatedAt: updatedAt),
    title: title ?? id,
    description: description,
    systemPrompt: systemPrompt,
  );
}

OutlineNode outlineNode(
  String id,
  String projectId,
  int orderIndex, {
  String? title,
  String summary = '',
  OutlineNodeStatus status = OutlineNodeStatus.planned,
}) {
  return OutlineNode(
    metadata: metadata(id),
    projectId: projectId,
    title: title ?? id,
    summary: summary,
    orderIndex: orderIndex,
    status: status,
  );
}

Segment segment(
  String id,
  String projectId,
  int orderIndex, {
  String? content,
  int revision = 1,
}) {
  return Segment(
    metadata: metadata(id, revision: revision),
    projectId: projectId,
    orderIndex: orderIndex,
    content: content ?? id,
  );
}

SegmentRevision segmentRevision(
  String id,
  String projectId,
  String segmentId,
  int revisionNumber, {
  String content = 'old content',
}) {
  return SegmentRevision(
    metadata: metadata(id),
    projectId: projectId,
    segmentId: segmentId,
    revisionNumber: revisionNumber,
    content: content,
    note: '',
    userInstruction: '',
    mode: 'local_edit',
  );
}

CharacterCard characterCard(String id, String projectId, int sortOrder) {
  return CharacterCard(
    metadata: metadata(id),
    projectId: projectId,
    name: id,
    content: 'character content',
    sortOrder: sortOrder,
  );
}

WorldCard worldCard(String id, String projectId, int sortOrder) {
  return WorldCard(
    metadata: metadata(id),
    projectId: projectId,
    title: id,
    content: 'world content',
    sortOrder: sortOrder,
  );
}

ChatSession chatSession(String id, String? projectId) {
  return ChatSession(metadata: metadata(id), projectId: projectId, title: id);
}

ChatPersona chatPersona(
  String id, {
  String? name,
  ChatPersonaDescriptionMode mode = ChatPersonaDescriptionMode.simple,
  String shortDescription = 'persona description',
  String speakingStyle = 'natural',
}) {
  return ChatPersona(
    metadata: metadata(id),
    name: name ?? id,
    descriptionMode: mode,
    shortDescription: shortDescription,
    speakingStyle: speakingStyle,
  );
}

chat.ChatMessage chatMessage(
  String id,
  String sessionId,
  String? projectId, {
  required int hour,
  ChatMessageRole role = ChatMessageRole.user,
  String? content,
}) {
  return chat.ChatMessage(
    metadata: metadata(id, createdAt: DateTime.utc(2026, 1, 1, hour)),
    sessionId: sessionId,
    projectId: projectId,
    role: role,
    content: content ?? id,
  );
}
