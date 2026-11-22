import 'package:sqflite/sqflite.dart';

const chatMemoryV16Statements = <String>[
  '''CREATE TABLE IF NOT EXISTS chat_memory_states (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL UNIQUE REFERENCES chat_sessions(id) ON DELETE RESTRICT,
    data_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK (revision >= 1),
    deleted_at TEXT NULL
  )''',
  '''CREATE TABLE IF NOT EXISTS chat_memory_usage (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES chat_sessions(id) ON DELETE RESTRICT,
    message_id TEXT NOT NULL UNIQUE REFERENCES chat_messages(id) ON DELETE RESTRICT,
    source_keys_json TEXT NOT NULL
  )''',
  'CREATE INDEX IF NOT EXISTS idx_chat_memory_usage_session ON chat_memory_usage(session_id, message_id)',
];

Future<void> createChatMemoryV16Schema(DatabaseExecutor db) async {
  for (final sql in chatMemoryV16Statements) {
    await db.execute(sql);
  }
}
