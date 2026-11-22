import 'package:sqflite/sqflite.dart';

const chatControlsV18Statements = [
  '''CREATE TABLE IF NOT EXISTS chat_session_controls (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL UNIQUE REFERENCES chat_sessions(id) ON DELETE CASCADE,
    reasoning_level TEXT NOT NULL DEFAULT 'automatic' CHECK(reasoning_level IN ('automatic','disabled','enabled','low','medium','high','xhigh','max')),
    updated_at TEXT NOT NULL
  )''',
  '''CREATE TABLE IF NOT EXISTS chat_usage_records (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES chat_sessions(id) ON DELETE CASCADE,
    operation TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    model TEXT NOT NULL,
    status TEXT NOT NULL,
    started_at TEXT NOT NULL,
    ended_at TEXT NOT NULL,
    estimated_input_tokens INTEGER NOT NULL CHECK(estimated_input_tokens >= 0),
    estimated_output_tokens INTEGER NOT NULL CHECK(estimated_output_tokens >= 0),
    input_tokens INTEGER NULL CHECK(input_tokens >= 0),
    output_tokens INTEGER NULL CHECK(output_tokens >= 0),
    total_tokens INTEGER NULL CHECK(total_tokens >= 0),
    cached_input_tokens INTEGER NULL CHECK(cached_input_tokens >= 0),
    cache_write_tokens INTEGER NULL CHECK(cache_write_tokens >= 0),
    reasoning_tokens INTEGER NULL CHECK(reasoning_tokens >= 0),
    reported_complete INTEGER NOT NULL CHECK(reported_complete IN (0,1))
  )''',
  'CREATE INDEX IF NOT EXISTS idx_chat_usage_session ON chat_usage_records(session_id, started_at DESC)',
];

Future<void> createChatControlsV18Schema(DatabaseExecutor db) async {
  for (final sql in chatControlsV18Statements) {
    await db.execute(sql);
  }
}
