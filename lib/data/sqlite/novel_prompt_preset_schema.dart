import 'package:sqflite/sqflite.dart';

const novelPromptPresetStatements = [
  '''CREATE TABLE IF NOT EXISTS novel_prompt_presets (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    content TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK (revision >= 1),
    deleted_at TEXT NULL
  )''',
];
Future<void> createNovelPromptPresetSchema(DatabaseExecutor db) async {
  for (final statement in novelPromptPresetStatements) {
    await db.execute(statement);
  }
}
