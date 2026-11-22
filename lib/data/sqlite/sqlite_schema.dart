import 'world_roleplay_schema.dart';
import 'tavern_schema.dart';
import 'tavern_world_info_schema.dart';
import 'chat_memory_v16_schema.dart';
import 'novel_prompt_preset_schema.dart';
import 'chat_controls_v18_schema.dart';
import 'novel_output_v19_schema.dart';
import 'novel_plugins_v21_schema.dart';

class SqliteSchema {
  const SqliteSchema._();

  static const int version = 21;
  static const String databaseName = 'ibukihome.db';

  static const List<String> baseCreateTableStatements = [
    ...chatMemoryV16Statements,
    ...novelPromptPresetStatements,
    ...chatControlsV18Statements,
    ...novelOutputV19Statements,
    ...novelPluginV21Statements,
    '''
CREATE TABLE projects (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  system_prompt TEXT NOT NULL DEFAULT '',
  ai_provider_config_id TEXT NULL,
  ai_model TEXT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  deleted_at TEXT NULL
)
''',
    '''
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
''',
    '''
CREATE TABLE segments (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  order_index INTEGER NOT NULL CHECK (order_index >= 0),
  content TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  deleted_at TEXT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT
)
''',
    '''
CREATE TABLE segment_revisions (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  segment_id TEXT NOT NULL,
  revision_number INTEGER NOT NULL CHECK (revision_number >= 1),
  content TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  user_instruction TEXT NOT NULL DEFAULT '',
  mode TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  deleted_at TEXT NULL,
  UNIQUE (segment_id, revision_number),
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT,
  FOREIGN KEY (segment_id) REFERENCES segments(id) ON DELETE RESTRICT
)
''',
    '''
CREATE TABLE character_cards (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  name TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT '',
  mode TEXT NULL CHECK (mode IS NULL OR mode IN ('fanfic', 'original')),
  source_work_title TEXT NOT NULL DEFAULT '',
  source_character_name TEXT NOT NULL DEFAULT '',
  source_version_hint TEXT NOT NULL DEFAULT '',
  fanfic_adaptation_notes TEXT NOT NULL DEFAULT '',
  original_idea TEXT NOT NULL DEFAULT '',
  avatar_reference TEXT NULL,
  source_format TEXT NOT NULL DEFAULT '',
  compatibility_payload_id TEXT NULL,
  sort_order INTEGER NOT NULL CHECK (sort_order >= 0),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  deleted_at TEXT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT
)
''',
    '''
CREATE TABLE world_cards (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL CHECK (sort_order >= 0),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  deleted_at TEXT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT
)
''',
    '''
CREATE TABLE chat_personas (
  id TEXT PRIMARY KEY,
  persona_prompt TEXT NULL,
  preset_messages_json TEXT NOT NULL DEFAULT '[]',
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
  auto_memory_enabled INTEGER NOT NULL DEFAULT 1 CHECK (auto_memory_enabled IN (0, 1)),
  use_long_term_memory INTEGER NOT NULL DEFAULT 1 CHECK (use_long_term_memory IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  deleted_at TEXT NULL
)
''',
    '''
CREATE TABLE chat_sessions (
  id TEXT PRIMARY KEY,
  project_id TEXT NULL,
  character_id TEXT NULL,
  persona_id TEXT NULL,
  ai_provider_config_id TEXT NULL,
  ai_model TEXT NULL,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  deleted_at TEXT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT,
  FOREIGN KEY (character_id) REFERENCES character_cards(id) ON DELETE RESTRICT,
  FOREIGN KEY (persona_id) REFERENCES chat_personas(id) ON DELETE RESTRICT
)
''',
    '''
CREATE TABLE chat_messages (
  image_json TEXT NULL,
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  project_id TEXT NULL,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
  content TEXT NOT NULL,
  finish_reason TEXT NULL CHECK (finish_reason IS NULL OR finish_reason IN ('stop', 'length', 'contentFiltered', 'cancelled', 'interrupted', 'providerError', 'unknown')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  deleted_at TEXT NULL,
  FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE RESTRICT,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT
)
''',
    '''
CREATE TABLE novel_summary_chunks (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  source_start_order INTEGER NOT NULL CHECK (source_start_order >= 0),
  source_end_order INTEGER NOT NULL CHECK (source_end_order >= source_start_order),
  source_start_segment_id TEXT NOT NULL,
  source_end_segment_id TEXT NOT NULL,
  summary TEXT NOT NULL DEFAULT '',
  source_fingerprint TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('valid', 'stale', 'generating', 'failed')),
  provider TEXT NULL,
  model TEXT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  deleted_at TEXT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT
)
''',
    '''
CREATE TABLE story_memory_digests (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL UNIQUE,
  content TEXT NOT NULL DEFAULT '',
  source_through_order INTEGER NOT NULL DEFAULT -1,
  source_fingerprint TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL CHECK (status IN ('valid', 'stale', 'generating', 'failed')),
  is_user_edited INTEGER NOT NULL DEFAULT 0 CHECK (is_user_edited IN (0, 1)),
  is_pinned INTEGER NOT NULL DEFAULT 0 CHECK (is_pinned IN (0, 1)),
  provider TEXT NULL,
  model TEXT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  deleted_at TEXT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT
)
''',
    '''
CREATE TABLE reader_preferences (
  project_id TEXT PRIMARY KEY,
  font_size REAL NOT NULL,
  line_height REAL NOT NULL,
  horizontal_margin REAL NOT NULL,
  theme TEXT NOT NULL CHECK (theme IN ('light', 'warm', 'dark')),
  updated_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT
)
''',
    '''
CREATE TABLE reader_progress (
  project_id TEXT PRIMARY KEY,
  last_read_segment_id TEXT NULL,
  scroll_offset REAL NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT
)
''',
    '''
CREATE TABLE chat_memory_entries (
  id TEXT PRIMARY KEY,
  persona_id TEXT NOT NULL,
  session_id TEXT NULL,
  category TEXT NOT NULL CHECK (category IN ('userFact', 'preference', 'relationship', 'sharedEvent', 'ongoingMatter', 'other')),
  content TEXT NOT NULL,
  topic TEXT NOT NULL DEFAULT '',
  source_fingerprint TEXT NOT NULL DEFAULT '',
  origin TEXT NOT NULL CHECK (origin IN ('auto', 'manual')),
  is_pinned INTEGER NOT NULL DEFAULT 0 CHECK (is_pinned IN (0, 1)),
  is_user_edited INTEGER NOT NULL DEFAULT 0 CHECK (is_user_edited IN (0, 1)),
  source_session_id TEXT NULL,
  source_start_message_id TEXT NULL,
  source_end_message_id TEXT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  deleted_at TEXT NULL,
  FOREIGN KEY (persona_id) REFERENCES chat_personas(id) ON DELETE RESTRICT,
  FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE RESTRICT,
  FOREIGN KEY (source_session_id) REFERENCES chat_sessions(id) ON DELETE RESTRICT
)
''',
    '''
CREATE TABLE conversation_summaries (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  source_start_message_id TEXT NOT NULL,
  source_end_message_id TEXT NOT NULL,
  summary TEXT NOT NULL DEFAULT '',
  source_fingerprint TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('valid', 'stale', 'generating', 'failed')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  deleted_at TEXT NULL,
  FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE RESTRICT
)
''',
    '''
CREATE TABLE installed_plugins (
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
''',
    '''
CREATE TABLE plugin_storage (
  plugin_id TEXT NOT NULL,
  storage_key TEXT NOT NULL,
  value_json TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (plugin_id, storage_key)
)
''',
    '''
CREATE TABLE external_compatibility_payloads (
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
''',
    ...WorldRoleplaySchema.createTableStatements,
    ...TavernSchema.tables,
  ];

  static List<String> get createTableStatements => [
    ...baseCreateTableStatements,
    ...TavernWorldInfoSchema.tables,
  ];

  static const List<String> createIndexStatements = [
    '''
CREATE INDEX idx_projects_updated_at
ON projects(updated_at DESC, title ASC, id ASC)
''',
    '''
CREATE INDEX idx_segments_project_id
ON segments(project_id)
''',
    '''
CREATE INDEX idx_outline_nodes_project_order
ON outline_nodes(project_id, order_index ASC, id ASC)
''',
    '''
CREATE UNIQUE INDEX idx_outline_nodes_single_current
ON outline_nodes(project_id)
WHERE status = 'current' AND deleted_at IS NULL
''',
    '''
CREATE INDEX idx_segments_project_order
ON segments(project_id, order_index ASC, created_at ASC, id ASC)
''',
    '''
CREATE INDEX idx_segment_revisions_project_id
ON segment_revisions(project_id)
''',
    '''
CREATE INDEX idx_segment_revisions_segment_revision
ON segment_revisions(segment_id, revision_number ASC, created_at ASC, id ASC)
''',
    '''
CREATE INDEX idx_character_cards_project_sort
ON character_cards(project_id, sort_order ASC, created_at ASC, id ASC)
''',
    '''
CREATE INDEX idx_world_cards_project_sort
ON world_cards(project_id, sort_order ASC, created_at ASC, id ASC)
''',
    '''
CREATE INDEX idx_chat_sessions_project_created
ON chat_sessions(project_id, created_at ASC, id ASC)
''',
    '''
CREATE INDEX idx_chat_sessions_character_updated
ON chat_sessions(character_id, updated_at DESC, id ASC)
''',
    '''
CREATE INDEX idx_chat_personas_name
ON chat_personas(name ASC, id ASC)
''',
    '''
CREATE INDEX idx_chat_sessions_persona_updated
ON chat_sessions(persona_id, updated_at DESC, id ASC)
''',
    '''
CREATE INDEX idx_chat_messages_session_created
ON chat_messages(session_id, created_at ASC, id ASC)
''',
    '''
CREATE INDEX idx_chat_messages_project_id
ON chat_messages(project_id)
''',
    '''
CREATE INDEX idx_novel_summary_chunks_project_range
ON novel_summary_chunks(project_id, source_start_order ASC, source_end_order ASC)
''',
    '''
CREATE INDEX idx_chat_memory_entries_persona_updated
ON chat_memory_entries(persona_id, is_pinned DESC, updated_at DESC)
''',
    '''
CREATE INDEX idx_chat_memory_entries_session_updated
ON chat_memory_entries(session_id, is_pinned DESC, updated_at DESC)
''',
    '''
CREATE INDEX idx_conversation_summaries_session_created
ON conversation_summaries(session_id, created_at ASC)
''',
    '''
CREATE INDEX idx_installed_plugins_enabled_name
ON installed_plugins(enabled DESC, name ASC, id ASC)
''',
    '''
CREATE INDEX idx_plugin_storage_plugin
ON plugin_storage(plugin_id, storage_key)
''',
    '''
CREATE INDEX idx_compatibility_payloads_source_sha
ON external_compatibility_payloads(source_sha256, created_at DESC)
''',
    '''
CREATE INDEX idx_compatibility_payloads_linked_entity
ON external_compatibility_payloads(linked_entity_type, linked_entity_id, created_at DESC)
''',
    ...WorldRoleplaySchema.createIndexStatements,
    ...TavernSchema.indexes,
    ...TavernWorldInfoSchema.indexes,
  ];
}
