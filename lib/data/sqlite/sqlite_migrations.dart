import 'package:sqflite/sqflite.dart';

import '../../core/errors/data_exceptions.dart';
import 'sqlite_schema.dart';
import 'world_roleplay_schema.dart';
import 'tavern_schema.dart';
import 'tavern_world_info_schema.dart';
import 'chat_memory_v16_schema.dart';
import 'novel_prompt_preset_schema.dart';
import 'chat_controls_v18_schema.dart';
import 'novel_output_v19_schema.dart';
import 'chat_images_v20_schema.dart';
import 'novel_plugins_v21_schema.dart';

class UnsupportedDatabaseVersionException extends DataException {
  const UnsupportedDatabaseVersionException(int oldVersion, int newVersion)
    : super(
        'Database version $oldVersion is newer than supported version $newVersion.',
      );
}

Future<void> createLatestSchema(DatabaseExecutor db) async {
  for (final statement in SqliteSchema.baseCreateTableStatements) {
    await db.execute(statement);
  }
  await createTavernWorldInfoV14Schema(db);
  await ensureNovelOutputTemperature(db);
  for (final statement in SqliteSchema.createIndexStatements) {
    await db.execute(statement);
  }
}

Future<void> ensurePluginV8Schema(Database db) async {
  if (await db.getVersion() < 8) return;
  await db.transaction(_createPluginV8Schema);
}

Future<void> ensureWorldV9Schema(Database db) async {
  if (await db.getVersion() < 9) return;
  await db.transaction(_createWorldV9Schema);
}

Future<void> ensureCurrentSchema(Database db) async {
  if (await db.getVersion() >= 21) {
    await db.transaction(createNovelPluginsV21Schema);
  }
  if (await db.getVersion() >= 20) {
    await db.transaction(createChatImagesV20Schema);
  }
  if (await db.getVersion() >= 19) {
    await db.transaction(createNovelOutputV19Schema);
    if (await db.getVersion() >= 22) {
      await db.transaction(ensureNovelOutputTemperature);
    }
  }
  if (await db.getVersion() >= 18) {
    await db.transaction(createChatControlsV18Schema);
  }
  if (await db.getVersion() >= 17) {
    await db.transaction(createNovelPromptPresetSchema);
  }
  if (await db.getVersion() >= 16) {
    await db.transaction(createChatMemoryV16Schema);
  }
  if (await db.getVersion() >= 15) {
    await db.transaction(_createChatPersonaV15Schema);
  }
  await ensurePluginV8Schema(db);
  await ensureWorldV9Schema(db);
  await ensureWorldV10Schema(db);
  await ensureCompatibilityV11Schema(db);
  await ensureWorldBookV12Schema(db);
  if (await db.getVersion() >= 13) {
    await db.transaction(_createTavernV13Schema);
  }
  if (await db.getVersion() >= 14) {
    await db.transaction(createTavernWorldInfoV14Schema);
  }
}

Future<void> ensureWorldBookV12Schema(Database db) async {
  if (await db.getVersion() < 12) return;
  await db.transaction(_createWorldBookV12Schema);
}

Future<void> ensureCompatibilityV11Schema(Database db) async {
  if (await db.getVersion() < 11) return;
  await db.transaction(_createCompatibilityV11Schema);
}

Future<void> ensureWorldV10Schema(Database db) async {
  if (await db.getVersion() < 10) return;
  await db.transaction(_createWorldV10Schema);
}

Future<void> runMigrations(Database db, int oldVersion, int newVersion) async {
  if (oldVersion > SqliteSchema.version) {
    throw UnsupportedDatabaseVersionException(oldVersion, newVersion);
  }
  if (oldVersion == newVersion) {
    return;
  }
  await db.transaction((txn) async {
    if (oldVersion < 1 && newVersion >= 1) {
      await createLatestSchema(txn);
      return;
    }
    if (oldVersion < 2 && newVersion >= 2) {
      await txn.execute('''
ALTER TABLE chat_sessions
ADD COLUMN character_id TEXT NULL
REFERENCES character_cards(id) ON DELETE RESTRICT
''');
      await txn.execute('''
CREATE INDEX idx_chat_sessions_character_updated
ON chat_sessions(character_id, updated_at DESC, id ASC)
''');
    }
    if (oldVersion < 3 && newVersion >= 3) {
      await txn.execute('''
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
      await txn.execute('''
ALTER TABLE chat_sessions
ADD COLUMN persona_id TEXT NULL
REFERENCES chat_personas(id) ON DELETE RESTRICT
''');
      await txn.execute('''
INSERT INTO chat_personas (
  id, name, avatar_reference, description_mode, short_description,
  speaking_style, core_identity, personality, background,
  relationship_to_user, behavior_habits, preferences, scenario, notes,
  created_at, updated_at, revision, deleted_at
)
SELECT
  'legacy-character:' || character_cards.id,
  character_cards.name,
  NULL,
  'simple',
  character_cards.content,
  '', '', '', '', '', '', '', '', '',
  character_cards.created_at,
  character_cards.updated_at,
  1,
  character_cards.deleted_at
FROM character_cards
WHERE character_cards.id IN (
  SELECT DISTINCT character_id
  FROM chat_sessions
  WHERE character_id IS NOT NULL
)
''');
      await txn.execute('''
UPDATE chat_sessions
SET persona_id = 'legacy-character:' || character_id
WHERE character_id IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM character_cards
    WHERE character_cards.id = chat_sessions.character_id
  )
''');
      await txn.execute('''
CREATE INDEX idx_chat_personas_name
ON chat_personas(name ASC, id ASC)
''');
      await txn.execute('''
CREATE INDEX idx_chat_sessions_persona_updated
ON chat_sessions(persona_id, updated_at DESC, id ASC)
''');
    }
    if (oldVersion < 4 && newVersion >= 4) {
      await txn.execute('''
ALTER TABLE projects
ADD COLUMN system_prompt TEXT NOT NULL DEFAULT ''
''');
      await txn.execute('''
CREATE TABLE outline_nodes (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  title TEXT NOT NULL,
  summary TEXT NOT NULL DEFAULT '',
  order_index INTEGER NOT NULL CHECK (order_index >= 0),
  status TEXT NOT NULL CHECK (status IN ('planned', 'current', 'completed')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  deleted_at TEXT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT
)
''');
      await txn.execute('''
CREATE INDEX idx_outline_nodes_project_order
ON outline_nodes(project_id, order_index ASC, id ASC)
''');
      await txn.execute('''
CREATE UNIQUE INDEX idx_outline_nodes_single_current
ON outline_nodes(project_id)
WHERE status = 'current' AND deleted_at IS NULL
''');
    }
    if (oldVersion < 5 && newVersion >= 5) {
      await txn.execute('''
ALTER TABLE chat_personas
ADD COLUMN auto_memory_enabled INTEGER NOT NULL DEFAULT 1
CHECK (auto_memory_enabled IN (0, 1))
''');
      await txn.execute('''
ALTER TABLE chat_personas
ADD COLUMN use_long_term_memory INTEGER NOT NULL DEFAULT 1
CHECK (use_long_term_memory IN (0, 1))
''');
      for (final statement in _version5Tables) {
        await txn.execute(statement);
      }
      for (final statement in _version5Indexes) {
        await txn.execute(statement);
      }
    }
    if (oldVersion < 6 && newVersion >= 6) {
      await _addColumnIfMissing(
        txn,
        'projects',
        'ai_provider_config_id',
        'TEXT NULL',
      );
      await _addColumnIfMissing(txn, 'projects', 'ai_model', 'TEXT NULL');
      await _addColumnIfMissing(
        txn,
        'chat_sessions',
        'ai_provider_config_id',
        'TEXT NULL',
      );
      await _addColumnIfMissing(txn, 'chat_sessions', 'ai_model', 'TEXT NULL');
      await _addColumnIfMissing(
        txn,
        'chat_messages',
        'finish_reason',
        'TEXT NULL',
      );
      await _addColumnIfMissing(
        txn,
        'chat_memory_entries',
        'session_id',
        'TEXT NULL REFERENCES chat_sessions(id) ON DELETE RESTRICT',
      );
      await txn.execute('''
UPDATE chat_memory_entries
SET session_id = source_session_id
WHERE source_session_id IS NOT NULL
''');
      await txn.execute('''
CREATE INDEX IF NOT EXISTS idx_chat_memory_entries_session_updated
ON chat_memory_entries(session_id, is_pinned DESC, updated_at DESC)
''');
    }
    if (oldVersion < 7 && newVersion >= 7) {
      await _addColumnIfMissing(
        txn,
        'character_cards',
        'mode',
        "TEXT NULL CHECK (mode IS NULL OR mode IN ('fanfic', 'original'))",
      );
      await _addColumnIfMissing(
        txn,
        'character_cards',
        'source_work_title',
        "TEXT NOT NULL DEFAULT ''",
      );
      await _addColumnIfMissing(
        txn,
        'character_cards',
        'source_character_name',
        "TEXT NOT NULL DEFAULT ''",
      );
      await _addColumnIfMissing(
        txn,
        'character_cards',
        'source_version_hint',
        "TEXT NOT NULL DEFAULT ''",
      );
      await _addColumnIfMissing(
        txn,
        'character_cards',
        'fanfic_adaptation_notes',
        "TEXT NOT NULL DEFAULT ''",
      );
      await _addColumnIfMissing(
        txn,
        'character_cards',
        'original_idea',
        "TEXT NOT NULL DEFAULT ''",
      );
    }
    if (oldVersion < 8 && newVersion >= 8) {
      await _createPluginV8Schema(txn);
    }
    if (oldVersion < 9 && newVersion >= 9) {
      await _createWorldV9Schema(txn);
    }
    if (oldVersion < 10 && newVersion >= 10) {
      await _createWorldV10Schema(txn);
    }
    if (oldVersion < 11 && newVersion >= 11) {
      await _createCompatibilityV11Schema(txn);
    }
    if (oldVersion < 12 && newVersion >= 12) {
      await _createWorldBookV12Schema(txn);
    }
    if (oldVersion < 13 && newVersion >= 13) {
      await _createTavernV13Schema(txn);
    }
    if (oldVersion < 14 && newVersion >= 14) {
      await createTavernWorldInfoV14Schema(txn);
      await txn.execute('''INSERT INTO tavern_world_info_states
        (id, session_id, story_line_id, data_json, initial_data_json, provenance)
        SELECT id, session_id, id, '{"messageCount":0,"historyMarker":"","timers":[]}',
          '{"messageCount":0,"historyMarker":"","timers":[]}', 'legacyUnavailable'
        FROM tavern_story_lines''');
    }
    if (oldVersion < 15 && newVersion >= 15) {
      await _createChatPersonaV15Schema(txn);
      await detachLegacyChatLinks(txn);
    }
    if (oldVersion < 16 && newVersion >= 16) {
      final columns = await txn.rawQuery(
        'PRAGMA table_info(chat_memory_entries)',
      );
      for (final column in ['topic', 'source_fingerprint']) {
        if (!columns.any((row) => row['name'] == column)) {
          await txn.execute(
            "ALTER TABLE chat_memory_entries ADD COLUMN $column TEXT NOT NULL DEFAULT ''",
          );
        }
      }
      await createChatMemoryV16Schema(txn);
    }
    if (oldVersion < 17 && newVersion >= 17) {
      await createNovelPromptPresetSchema(txn);
    }
    if (oldVersion < 21 && newVersion >= 21) {
      await createNovelPluginsV21Schema(txn);
    }
    if (oldVersion < 20 && newVersion >= 20) {
      await createChatImagesV20Schema(txn);
    }
    if (oldVersion < 19 && newVersion >= 19) {
      await createNovelOutputV19Schema(txn);
    }
    if (oldVersion < 22 && newVersion >= 22) {
      await ensureNovelOutputTemperature(txn);
    }
    if (oldVersion < 18 && newVersion >= 18) {
      await createChatControlsV18Schema(txn);
    }
  });
}

Future<void> createTavernWorldInfoV14Schema(
  DatabaseExecutor db, {
  bool? jsonFunctions,
}) async {
  if (jsonFunctions == null) {
    try {
      await db.rawQuery(
        "SELECT json_valid('{}'), json_extract('{}', '\$.probe')",
      );
      jsonFunctions = true;
    } on DatabaseException catch (error) {
      if (!error.toString().contains('no such function: json_')) rethrow;
      jsonFunctions = false;
    }
  }
  for (final statement in TavernWorldInfoSchema.statements(
    jsonFunctions: jsonFunctions,
  )) {
    await db.execute(statement);
  }
  for (final statement in TavernWorldInfoSchema.indexes) {
    await db.execute(statement);
  }
}

Future<void> _createTavernV13Schema(DatabaseExecutor db) async {
  for (final statement in TavernSchema.tables) {
    await db.execute(statement);
  }
  for (final statement in TavernSchema.indexes) {
    await db.execute(statement);
  }
}

Future<void> _createWorldBookV12Schema(DatabaseExecutor db) async {
  const names = <String>{
    'world_world_book_references',
    'world_session_world_book_overrides',
    'character_world_book_references',
    'persona_world_book_references',
  };
  for (final statement in WorldRoleplaySchema.createTableStatements) {
    if (names.any((name) => statement.contains('IF NOT EXISTS $name'))) {
      await db.execute(statement);
    }
  }
  for (final statement in WorldRoleplaySchema.createIndexStatements) {
    if (statement.contains('book_refs_') ||
        statement.contains('book_overrides_')) {
      await db.execute(statement);
    }
  }
}

Future<void> _createCompatibilityV11Schema(DatabaseExecutor db) async {
  await _addColumnIfMissing(
    db,
    'character_cards',
    'avatar_reference',
    'TEXT NULL',
  );
  await _addColumnIfMissing(
    db,
    'character_cards',
    'source_format',
    "TEXT NOT NULL DEFAULT ''",
  );
  await _addColumnIfMissing(
    db,
    'character_cards',
    'compatibility_payload_id',
    'TEXT NULL',
  );
  await db.execute('''
CREATE TABLE IF NOT EXISTS external_compatibility_payloads (
  id TEXT PRIMARY KEY,
  source_type TEXT NOT NULL,
  source_format TEXT NOT NULL,
  source_version TEXT NOT NULL DEFAULT '',
  source_sha256 TEXT NOT NULL,
  linked_entity_type TEXT NOT NULL,
  linked_entity_id TEXT NOT NULL,
  normalized_payload_json TEXT NOT NULL DEFAULT '{}',
  unsupported_payload_json TEXT NOT NULL DEFAULT '{}',
  security_flags_json TEXT NOT NULL DEFAULT '[]',
  import_warnings_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}'
)
''');
  await db.execute('''
CREATE INDEX IF NOT EXISTS idx_compatibility_payloads_source_sha
ON external_compatibility_payloads(source_sha256, created_at DESC)
''');
  await db.execute('''
CREATE INDEX IF NOT EXISTS idx_compatibility_payloads_linked_entity
ON external_compatibility_payloads(linked_entity_type, linked_entity_id, created_at DESC)
''');
}

Future<void> _createWorldV10Schema(DatabaseExecutor db) async {
  await _addColumnIfMissing(
    db,
    'world_sessions',
    'ai_provider_config_id',
    'TEXT NULL',
  );
  await _addColumnIfMissing(db, 'world_sessions', 'ai_model', 'TEXT NULL');
  await _addColumnIfMissing(
    db,
    'world_sessions',
    'lore_context_budget',
    'INTEGER NOT NULL DEFAULT 1800 CHECK (lore_context_budget BETWEEN 256 AND 12000)',
  );
  await _addColumnIfMissing(
    db,
    'world_sessions',
    'speaker_mode',
    "TEXT NOT NULL DEFAULT 'natural' CHECK (speaker_mode IN ('natural', 'manual', 'sequence'))",
  );
  final turnStatement = WorldRoleplaySchema.createTableStatements.firstWhere(
    (statement) => statement.contains('CREATE TABLE IF NOT EXISTS world_turns'),
  );
  await db.execute(turnStatement);
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_world_turns_session_created '
    'ON world_turns(world_session_id, created_at DESC, id ASC)',
  );
}

Future<void> _createWorldV9Schema(DatabaseExecutor db) async {
  for (final statement in WorldRoleplaySchema.createTableStatements) {
    await db.execute(statement);
  }
  for (final statement in WorldRoleplaySchema.createIndexStatements) {
    await db.execute(statement);
  }
}

Future<void> _createPluginV8Schema(DatabaseExecutor db) async {
  await db.execute('''
CREATE TABLE IF NOT EXISTS installed_plugins (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  version TEXT NOT NULL,
  author TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  manifest_version INTEGER NOT NULL CHECK (manifest_version >= 1),
  manifest_json TEXT NOT NULL,
  installed_path TEXT NOT NULL,
  data_path TEXT NOT NULL DEFAULT '',
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  status TEXT NOT NULL DEFAULT 'installed' CHECK (status IN ('installed', 'broken')),
  error_category TEXT NULL,
  package_size INTEGER NOT NULL DEFAULT 0 CHECK (package_size >= 0),
  extracted_size INTEGER NOT NULL DEFAULT 0 CHECK (extracted_size >= 0),
  installed_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');
  await _addColumnIfMissing(
    db,
    'installed_plugins',
    'data_path',
    "TEXT NOT NULL DEFAULT ''",
  );
  await db.execute('''
CREATE INDEX IF NOT EXISTS idx_installed_plugins_enabled_name
ON installed_plugins(enabled DESC, name ASC, id ASC)
''');
  await db.execute('''
CREATE TABLE IF NOT EXISTS plugin_storage (
  plugin_id TEXT NOT NULL,
  storage_key TEXT NOT NULL,
  value_json TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (plugin_id, storage_key)
)
''');
  await db.execute('''
CREATE INDEX IF NOT EXISTS idx_plugin_storage_plugin
ON plugin_storage(plugin_id, storage_key)
''');
}

Future<void> _addColumnIfMissing(
  DatabaseExecutor db,
  String table,
  String column,
  String definition,
) async {
  final columns = await db.rawQuery('PRAGMA table_info($table)');
  if (columns.any((item) => item['name'] == column)) return;
  await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
}

const _version5Tables = <String>[
  '''
CREATE TABLE novel_summary_chunks (
  id TEXT PRIMARY KEY, project_id TEXT NOT NULL,
  source_start_order INTEGER NOT NULL CHECK (source_start_order >= 0),
  source_end_order INTEGER NOT NULL CHECK (source_end_order >= source_start_order),
  source_start_segment_id TEXT NOT NULL, source_end_segment_id TEXT NOT NULL,
  summary TEXT NOT NULL DEFAULT '', source_fingerprint TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('valid', 'stale', 'generating', 'failed')),
  provider TEXT NULL, model TEXT NULL,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1), deleted_at TEXT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT
)
''',
  '''
CREATE TABLE story_memory_digests (
  id TEXT PRIMARY KEY, project_id TEXT NOT NULL UNIQUE,
  content TEXT NOT NULL DEFAULT '', source_through_order INTEGER NOT NULL DEFAULT -1,
  source_fingerprint TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL CHECK (status IN ('valid', 'stale', 'generating', 'failed')),
  is_user_edited INTEGER NOT NULL DEFAULT 0 CHECK (is_user_edited IN (0, 1)),
  is_pinned INTEGER NOT NULL DEFAULT 0 CHECK (is_pinned IN (0, 1)),
  provider TEXT NULL, model TEXT NULL,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1), deleted_at TEXT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT
)
''',
  '''
CREATE TABLE reader_preferences (
  project_id TEXT PRIMARY KEY, font_size REAL NOT NULL,
  line_height REAL NOT NULL, horizontal_margin REAL NOT NULL,
  theme TEXT NOT NULL CHECK (theme IN ('light', 'warm', 'dark')),
  updated_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT
)
''',
  '''
CREATE TABLE reader_progress (
  project_id TEXT PRIMARY KEY, last_read_segment_id TEXT NULL,
  scroll_offset REAL NOT NULL DEFAULT 0, updated_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT
)
''',
  '''
CREATE TABLE chat_memory_entries (
  id TEXT PRIMARY KEY, persona_id TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('userFact', 'preference', 'relationship', 'sharedEvent', 'ongoingMatter', 'other')),
  content TEXT NOT NULL, origin TEXT NOT NULL CHECK (origin IN ('auto', 'manual')),
  is_pinned INTEGER NOT NULL DEFAULT 0 CHECK (is_pinned IN (0, 1)),
  is_user_edited INTEGER NOT NULL DEFAULT 0 CHECK (is_user_edited IN (0, 1)),
  source_session_id TEXT NULL, source_start_message_id TEXT NULL,
  source_end_message_id TEXT NULL, created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL, revision INTEGER NOT NULL CHECK (revision >= 1),
  deleted_at TEXT NULL,
  FOREIGN KEY (persona_id) REFERENCES chat_personas(id) ON DELETE RESTRICT,
  FOREIGN KEY (source_session_id) REFERENCES chat_sessions(id) ON DELETE RESTRICT
)
''',
  '''
CREATE TABLE conversation_summaries (
  id TEXT PRIMARY KEY, session_id TEXT NOT NULL,
  source_start_message_id TEXT NOT NULL, source_end_message_id TEXT NOT NULL,
  summary TEXT NOT NULL DEFAULT '', source_fingerprint TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('valid', 'stale', 'generating', 'failed')),
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1), deleted_at TEXT NULL,
  FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE RESTRICT
)
''',
];

const _version5Indexes = <String>[
  '''CREATE INDEX idx_novel_summary_chunks_project_range
ON novel_summary_chunks(project_id, source_start_order ASC, source_end_order ASC)''',
  '''CREATE INDEX idx_chat_memory_entries_persona_updated
ON chat_memory_entries(persona_id, is_pinned DESC, updated_at DESC)''',
  '''CREATE INDEX idx_conversation_summaries_session_created
ON conversation_summaries(session_id, created_at ASC)''',
];

Future<void> _createChatPersonaV15Schema(DatabaseExecutor db) async {
  await _addColumnIfMissing(db, 'chat_personas', 'persona_prompt', 'TEXT NULL');
  await _addColumnIfMissing(
    db,
    'chat_personas',
    'preset_messages_json',
    "TEXT NOT NULL DEFAULT '[]'",
  );
}

// Used only during upgrade/archive restore. Runtime never resolves novel sources.
Future<void> detachLegacyChatLinks(DatabaseExecutor db) async {
  await db.execute(
    """INSERT OR IGNORE INTO chat_personas
    (id, name, description_mode, short_description, speaking_style,
      persona_prompt, created_at, updated_at, revision, deleted_at)
    SELECT 'legacy-isolation:' || c.id, c.name, 'simple', '', '', c.content,
      c.created_at, c.updated_at, 1, c.deleted_at
    FROM character_cards c WHERE c.id IN
      (SELECT character_id FROM chat_sessions WHERE persona_id IS NULL AND character_id IS NOT NULL)""",
  );
  await db.execute(
    """UPDATE chat_sessions
    SET persona_id = 'legacy-isolation:' || character_id
    WHERE persona_id IS NULL AND character_id IS NOT NULL AND EXISTS
      (SELECT 1 FROM chat_personas WHERE id = 'legacy-isolation:' || chat_sessions.character_id)""",
  );
  await db.execute(
    'UPDATE chat_messages SET project_id = NULL WHERE project_id IS NOT NULL',
  );
  await db.execute(
    'UPDATE chat_sessions SET project_id = NULL, character_id = NULL WHERE project_id IS NOT NULL OR character_id IS NOT NULL',
  );
}
