import 'package:sqflite/sqflite.dart';

import '../../domain/memory/novel_summary_chunk.dart';
import '../../domain/memory/story_memory_digest.dart';
import '../repositories/novel_memory_repository.dart';
import 'ibuki_database.dart';
import 'sqlite_value_codec.dart';

class SQLiteNovelMemoryRepository implements NovelMemoryRepository {
  SQLiteNovelMemoryRepository(this.ibukiDatabase);

  final IbukiDatabase ibukiDatabase;

  @override
  Future<List<NovelSummaryChunk>> listChunks(String projectId) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'novel_summary_chunks',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'source_start_order ASC, source_end_order ASC, id ASC',
    );
    return List.unmodifiable(rows.map(novelSummaryChunkFromSql));
  }

  @override
  Future<NovelSummaryChunk?> getChunk(String id) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'novel_summary_chunks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : novelSummaryChunkFromSql(rows.single);
  }

  @override
  Future<void> upsertChunk(NovelSummaryChunk chunk) async {
    final db = await ibukiDatabase.database;
    await db.insert(
      'novel_summary_chunks',
      novelSummaryChunkToSql(chunk),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteChunksFromOrder(String projectId, int fromOrder) async {
    final db = await ibukiDatabase.database;
    await db.delete(
      'novel_summary_chunks',
      where: 'project_id = ? AND source_end_order >= ?',
      whereArgs: [projectId, fromOrder],
    );
  }

  @override
  Future<StoryMemoryDigest?> getDigest(String projectId) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'story_memory_digests',
      where: 'project_id = ?',
      whereArgs: [projectId],
      limit: 1,
    );
    return rows.isEmpty ? null : storyMemoryDigestFromSql(rows.single);
  }

  @override
  Future<void> upsertDigest(StoryMemoryDigest digest) async {
    final db = await ibukiDatabase.database;
    await db.insert(
      'story_memory_digests',
      storyMemoryDigestToSql(digest),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
