import 'package:sqflite/sqflite.dart';

const novelPluginV21Statements = [
  '''CREATE TABLE IF NOT EXISTS novel_plugin_state (
    id TEXT PRIMARY KEY,
    project_id TEXT NULL REFERENCES projects(id) ON DELETE RESTRICT,
    plugin_id TEXT NOT NULL,
    storage_key TEXT NOT NULL,
    value_json TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(plugin_id,storage_key)
  )''',
  '''CREATE TABLE IF NOT EXISTS novel_story_branches (
    id TEXT PRIMARY KEY REFERENCES projects(id) ON DELETE RESTRICT,
    story_id TEXT NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
    parent_id TEXT NULL REFERENCES novel_story_branches(id) ON DELETE RESTRICT,
    label TEXT NOT NULL,
    inherit_settings INTEGER NOT NULL DEFAULT 1 CHECK(inherit_settings IN (0,1)),
    revision INTEGER NOT NULL DEFAULT 1 CHECK(revision >= 1),
    updated_at TEXT NOT NULL,
    ended_by_plugin TEXT NULL,
    ended_source_segment_id TEXT NULL REFERENCES segments(id) ON DELETE RESTRICT,
    ended_source_hash TEXT NULL,
    ended_reason TEXT NULL
  )''',
  '''CREATE TABLE IF NOT EXISTS novel_active_branches (
    id TEXT PRIMARY KEY REFERENCES projects(id) ON DELETE RESTRICT,
    branch_id TEXT NOT NULL REFERENCES novel_story_branches(id) ON DELETE RESTRICT
  )''',
  '''CREATE TABLE IF NOT EXISTS novel_segment_origins (
    id TEXT PRIMARY KEY REFERENCES segments(id) ON DELETE RESTRICT,
    origin_segment_id TEXT NOT NULL REFERENCES segments(id) ON DELETE RESTRICT
  )''',
  '''CREATE TABLE IF NOT EXISTS novel_plugin_candidates (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
    segment_id TEXT NOT NULL REFERENCES segments(id) ON DELETE RESTRICT,
    source_candidate_id TEXT NULL REFERENCES novel_plugin_candidates(id) ON DELETE RESTRICT,
    content TEXT NOT NULL,
    source_revision INTEGER NOT NULL CHECK(source_revision >= 1),
    created_at TEXT NOT NULL
  )''',
  '''CREATE TABLE IF NOT EXISTS novel_plugin_selections (
    id TEXT PRIMARY KEY REFERENCES segments(id) ON DELETE RESTRICT,
    candidate_id TEXT NOT NULL REFERENCES novel_plugin_candidates(id) ON DELETE RESTRICT
  )''',
  '''CREATE TABLE IF NOT EXISTS novel_plugin_reply_views (
    id TEXT PRIMARY KEY REFERENCES segments(id) ON DELETE RESTRICT,
    content_hash TEXT NOT NULL,
    data_json TEXT NOT NULL
  )''',
  'CREATE INDEX IF NOT EXISTS idx_novel_branches_story ON novel_story_branches(story_id)',
  'CREATE INDEX IF NOT EXISTS idx_novel_candidates_segment ON novel_plugin_candidates(segment_id)',
];
Future<void> createNovelPluginsV21Schema(DatabaseExecutor db) async {
  for (final statement in novelPluginV21Statements) {
    await db.execute(statement);
  }
}
