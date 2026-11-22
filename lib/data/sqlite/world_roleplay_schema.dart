class WorldRoleplaySchema {
  const WorldRoleplaySchema._();

  static const createTableStatements = <String>[
    '''
CREATE TABLE IF NOT EXISTS roleplay_worlds (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  default_session_id TEXT NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  FOREIGN KEY (default_session_id) REFERENCES world_sessions(id) ON DELETE SET NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS world_sessions (
  id TEXT PRIMARY KEY,
  world_id TEXT NOT NULL,
  name TEXT NOT NULL,
  current_player_instance_id TEXT NULL,
  current_scene_id TEXT NULL,
  current_branch_id TEXT NULL,
  world_time TEXT NOT NULL DEFAULT '',
  ai_provider_config_id TEXT NULL,
  ai_model TEXT NULL,
  lore_context_budget INTEGER NOT NULL DEFAULT 1800 CHECK (lore_context_budget BETWEEN 256 AND 12000),
  speaker_mode TEXT NOT NULL DEFAULT 'natural' CHECK (speaker_mode IN ('natural', 'manual', 'sequence')),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  FOREIGN KEY (world_id) REFERENCES roleplay_worlds(id) ON DELETE CASCADE,
  FOREIGN KEY (current_player_instance_id) REFERENCES world_player_instances(id) ON DELETE SET NULL,
  FOREIGN KEY (current_scene_id) REFERENCES world_scenes(id) ON DELETE SET NULL,
  FOREIGN KEY (current_branch_id) REFERENCES world_branches(id) ON DELETE SET NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS world_books (
  id TEXT PRIMARY KEY,
  world_id TEXT NOT NULL,
  name TEXT NOT NULL,
  is_primary INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0, 1)),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  FOREIGN KEY (world_id) REFERENCES roleplay_worlds(id) ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS lore_entries (
  id TEXT PRIMARY KEY,
  world_book_id TEXT NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT '',
  keywords_json TEXT NOT NULL DEFAULT '[]',
  secondary_keywords_json TEXT NOT NULL DEFAULT '[]',
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  priority INTEGER NOT NULL DEFAULT 0,
  activation_mode TEXT NOT NULL CHECK (activation_mode IN ('always', 'keyword', 'manual')),
  insertion_position TEXT NOT NULL DEFAULT 'context',
  probability REAL NOT NULL DEFAULT 1 CHECK (probability >= 0 AND probability <= 1),
  scope TEXT NOT NULL DEFAULT 'world',
  token_budget_hint INTEGER NULL CHECK (token_budget_hint IS NULL OR token_budget_hint >= 0),
  source_world_card_id TEXT NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  FOREIGN KEY (world_book_id) REFERENCES world_books(id) ON DELETE CASCADE,
  FOREIGN KEY (source_world_card_id) REFERENCES world_cards(id) ON DELETE SET NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS world_world_book_references (
  id TEXT PRIMARY KEY,
  world_id TEXT NOT NULL,
  world_book_id TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  priority INTEGER NOT NULL DEFAULT 0,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  UNIQUE (world_id, world_book_id),
  FOREIGN KEY (world_id) REFERENCES roleplay_worlds(id) ON DELETE CASCADE,
  FOREIGN KEY (world_book_id) REFERENCES world_books(id) ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS world_session_world_book_overrides (
  id TEXT PRIMARY KEY,
  world_session_id TEXT NOT NULL,
  world_book_id TEXT NOT NULL,
  override_mode TEXT NOT NULL DEFAULT 'inherit' CHECK (override_mode IN ('inherit', 'enabled', 'disabled')),
  priority INTEGER NOT NULL DEFAULT 0,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  UNIQUE (world_session_id, world_book_id),
  FOREIGN KEY (world_session_id) REFERENCES world_sessions(id) ON DELETE CASCADE,
  FOREIGN KEY (world_book_id) REFERENCES world_books(id) ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS character_world_book_references (
  id TEXT PRIMARY KEY,
  character_card_id TEXT NOT NULL,
  world_book_id TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  priority INTEGER NOT NULL DEFAULT 0,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  UNIQUE (character_card_id, world_book_id),
  FOREIGN KEY (character_card_id) REFERENCES character_cards(id) ON DELETE CASCADE,
  FOREIGN KEY (world_book_id) REFERENCES world_books(id) ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS persona_world_book_references (
  id TEXT PRIMARY KEY,
  player_persona_id TEXT NOT NULL,
  world_book_id TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  priority INTEGER NOT NULL DEFAULT 0,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  UNIQUE (player_persona_id, world_book_id),
  FOREIGN KEY (player_persona_id) REFERENCES player_personas(id) ON DELETE CASCADE,
  FOREIGN KEY (world_book_id) REFERENCES world_books(id) ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS player_personas (
  id TEXT PRIMARY KEY,
  world_id TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  appearance TEXT NOT NULL DEFAULT '',
  background TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  avatar_reference TEXT NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  FOREIGN KEY (world_id) REFERENCES roleplay_worlds(id) ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS world_player_instances (
  id TEXT PRIMARY KEY,
  world_session_id TEXT NOT NULL,
  player_persona_id TEXT NOT NULL,
  display_name_override TEXT NULL,
  current_location TEXT NOT NULL DEFAULT '',
  current_status TEXT NOT NULL DEFAULT '',
  current_mood TEXT NOT NULL DEFAULT '',
  current_goal TEXT NOT NULL DEFAULT '',
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
  last_active_at TEXT NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  UNIQUE (world_session_id, player_persona_id),
  FOREIGN KEY (world_session_id) REFERENCES world_sessions(id) ON DELETE CASCADE,
  FOREIGN KEY (player_persona_id) REFERENCES player_personas(id) ON DELETE NO ACTION
)
''',
    '''
CREATE TABLE IF NOT EXISTS world_character_instances (
  id TEXT PRIMARY KEY,
  world_session_id TEXT NOT NULL,
  character_card_id TEXT NOT NULL,
  display_name_override TEXT NULL,
  current_location TEXT NOT NULL DEFAULT '',
  current_status TEXT NOT NULL DEFAULT '',
  current_mood TEXT NOT NULL DEFAULT '',
  current_goal TEXT NOT NULL DEFAULT '',
  is_present INTEGER NOT NULL DEFAULT 0 CHECK (is_present IN (0, 1)),
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
  last_active_at TEXT NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  UNIQUE (world_session_id, character_card_id),
  FOREIGN KEY (world_session_id) REFERENCES world_sessions(id) ON DELETE CASCADE,
  FOREIGN KEY (character_card_id) REFERENCES character_cards(id) ON DELETE RESTRICT
)
''',
    '''
CREATE TABLE IF NOT EXISTS world_scenes (
  id TEXT PRIMARY KEY,
  world_session_id TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  location TEXT NOT NULL DEFAULT '',
  time_text TEXT NOT NULL DEFAULT '',
  weather TEXT NOT NULL DEFAULT '',
  atmosphere TEXT NOT NULL DEFAULT '',
  current_event TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  FOREIGN KEY (world_session_id) REFERENCES world_sessions(id) ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS world_scene_cast (
  scene_id TEXT NOT NULL,
  character_instance_id TEXT NOT NULL,
  PRIMARY KEY (scene_id, character_instance_id),
  FOREIGN KEY (scene_id) REFERENCES world_scenes(id) ON DELETE CASCADE,
  FOREIGN KEY (character_instance_id) REFERENCES world_character_instances(id) ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS world_state_entries (
  id TEXT PRIMARY KEY,
  world_session_id TEXT NOT NULL,
  state_key TEXT NOT NULL,
  value_json TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'general',
  source TEXT NOT NULL DEFAULT 'manual',
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  UNIQUE (world_session_id, state_key),
  FOREIGN KEY (world_session_id) REFERENCES world_sessions(id) ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS world_relationships (
  id TEXT PRIMARY KEY,
  world_session_id TEXT NOT NULL,
  source_entity_type TEXT NOT NULL,
  source_entity_id TEXT NOT NULL,
  target_entity_type TEXT NOT NULL,
  target_entity_id TEXT NOT NULL,
  relation_type TEXT NOT NULL,
  summary TEXT NOT NULL DEFAULT '',
  state_json TEXT NOT NULL DEFAULT '{}',
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  FOREIGN KEY (world_session_id) REFERENCES world_sessions(id) ON DELETE CASCADE
)
''',
    '''
CREATE TABLE IF NOT EXISTS world_memory_entries (
  id TEXT PRIMARY KEY,
  world_session_id TEXT NOT NULL,
  memory_type TEXT NOT NULL,
  summary TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT '',
  importance REAL NOT NULL DEFAULT 0.5 CHECK (importance >= 0 AND importance <= 1),
  related_character_ids_json TEXT NOT NULL DEFAULT '[]',
  related_scene_id TEXT NULL,
  last_referenced_at TEXT NULL,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  FOREIGN KEY (world_session_id) REFERENCES world_sessions(id) ON DELETE CASCADE,
  FOREIGN KEY (related_scene_id) REFERENCES world_scenes(id) ON DELETE SET NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS world_timeline_events (
  id TEXT PRIMARY KEY,
  world_session_id TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  world_time TEXT NOT NULL DEFAULT '',
  scene_id TEXT NULL,
  character_ids_json TEXT NOT NULL DEFAULT '[]',
  event_type TEXT NOT NULL DEFAULT 'manual',
  importance REAL NOT NULL DEFAULT 0.5 CHECK (importance >= 0 AND importance <= 1),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  FOREIGN KEY (world_session_id) REFERENCES world_sessions(id) ON DELETE CASCADE,
  FOREIGN KEY (scene_id) REFERENCES world_scenes(id) ON DELETE SET NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS world_branches (
  id TEXT PRIMARY KEY,
  world_session_id TEXT NOT NULL,
  name TEXT NOT NULL,
  parent_branch_id TEXT NULL,
  branch_point_message_id TEXT NULL,
  branch_point_event_id TEXT NULL,
  is_current INTEGER NOT NULL DEFAULT 0 CHECK (is_current IN (0, 1)),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  FOREIGN KEY (world_session_id) REFERENCES world_sessions(id) ON DELETE CASCADE,
  FOREIGN KEY (parent_branch_id) REFERENCES world_branches(id) ON DELETE SET NULL,
  FOREIGN KEY (branch_point_event_id) REFERENCES world_timeline_events(id) ON DELETE SET NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS world_feed_entries (
  id TEXT PRIMARY KEY,
  world_session_id TEXT NOT NULL,
  branch_id TEXT NOT NULL,
  entry_type TEXT NOT NULL CHECK (entry_type IN ('userAction', 'characterSpeech', 'narration', 'systemEvent')),
  speaker_character_instance_id TEXT NULL,
  content TEXT NOT NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  FOREIGN KEY (world_session_id) REFERENCES world_sessions(id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id) REFERENCES world_branches(id) ON DELETE RESTRICT,
  FOREIGN KEY (speaker_character_instance_id) REFERENCES world_character_instances(id) ON DELETE SET NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS world_turns (
  id TEXT PRIMARY KEY,
  world_session_id TEXT NOT NULL,
  branch_id TEXT NOT NULL,
  user_feed_entry_id TEXT NOT NULL,
  director_decision_json TEXT NOT NULL DEFAULT '{}',
  selected_speaker_ids_json TEXT NOT NULL DEFAULT '[]',
  generated_feed_entry_ids_json TEXT NOT NULL DEFAULT '[]',
  mutation_proposal_json TEXT NOT NULL DEFAULT '{}',
  status TEXT NOT NULL CHECK (status IN ('pending', 'directing', 'generating', 'committing', 'completed', 'failed', 'cancelled')),
  completed_at TEXT NULL,
  error_category TEXT NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  FOREIGN KEY (world_session_id) REFERENCES world_sessions(id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id) REFERENCES world_branches(id) ON DELETE RESTRICT,
  FOREIGN KEY (user_feed_entry_id) REFERENCES world_feed_entries(id) ON DELETE CASCADE
)
''',
  ];

  static const createIndexStatements = <String>[
    'CREATE INDEX IF NOT EXISTS idx_roleplay_worlds_updated ON roleplay_worlds(updated_at DESC, id ASC)',
    'CREATE INDEX IF NOT EXISTS idx_world_sessions_world_updated ON world_sessions(world_id, updated_at DESC, id ASC)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_world_books_primary ON world_books(world_id) WHERE is_primary = 1',
    'CREATE INDEX IF NOT EXISTS idx_lore_entries_book_priority ON lore_entries(world_book_id, enabled DESC, priority DESC, title ASC)',
    'CREATE INDEX IF NOT EXISTS idx_world_book_refs_world ON world_world_book_references(world_id, enabled DESC, priority DESC, world_book_id)',
    'CREATE INDEX IF NOT EXISTS idx_world_book_overrides_session ON world_session_world_book_overrides(world_session_id, world_book_id)',
    'CREATE INDEX IF NOT EXISTS idx_character_book_refs_character ON character_world_book_references(character_card_id, enabled DESC, priority DESC)',
    'CREATE INDEX IF NOT EXISTS idx_persona_book_refs_persona ON persona_world_book_references(player_persona_id, enabled DESC, priority DESC)',
    'CREATE INDEX IF NOT EXISTS idx_player_personas_world_name ON player_personas(world_id, name ASC)',
    'CREATE INDEX IF NOT EXISTS idx_world_player_instances_session ON world_player_instances(world_session_id, is_active DESC, id ASC)',
    'CREATE INDEX IF NOT EXISTS idx_world_character_instances_session ON world_character_instances(world_session_id, is_active DESC, is_present DESC, id ASC)',
    'CREATE INDEX IF NOT EXISTS idx_world_scenes_session_updated ON world_scenes(world_session_id, updated_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_world_state_session_key ON world_state_entries(world_session_id, state_key ASC)',
    'CREATE INDEX IF NOT EXISTS idx_world_relationships_session ON world_relationships(world_session_id, updated_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_world_memory_session_importance ON world_memory_entries(world_session_id, enabled DESC, importance DESC, created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_world_timeline_session_time ON world_timeline_events(world_session_id, world_time ASC, created_at ASC)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_world_branches_current ON world_branches(world_session_id) WHERE is_current = 1',
    'CREATE INDEX IF NOT EXISTS idx_world_feed_session_branch_created ON world_feed_entries(world_session_id, branch_id, created_at ASC, id ASC)',
    'CREATE INDEX IF NOT EXISTS idx_world_turns_session_created ON world_turns(world_session_id, created_at DESC, id ASC)',
  ];
}
