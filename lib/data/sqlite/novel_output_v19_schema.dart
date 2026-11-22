import 'package:sqflite/sqflite.dart';

const novelOutputV19Statements = [
  '''CREATE TABLE IF NOT EXISTS novel_output_settings (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL UNIQUE REFERENCES projects(id) ON DELETE RESTRICT,
    minimum_characters INTEGER NULL CHECK(minimum_characters > 0),
    maximum_characters INTEGER NULL CHECK(maximum_characters > 0),
    revision INTEGER NOT NULL CHECK(revision >= 1),
    updated_at TEXT NOT NULL,
    CHECK(minimum_characters IS NULL OR maximum_characters IS NULL OR minimum_characters <= maximum_characters)
  )''',
];
Future<void> createNovelOutputV19Schema(DatabaseExecutor db) async {
  for (final statement in novelOutputV19Statements) {
    await db.execute(statement);
  }
}
