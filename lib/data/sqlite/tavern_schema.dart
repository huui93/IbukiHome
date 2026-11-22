class TavernSchema {
  const TavernSchema._();

  static const tables = <String>[
    '''CREATE TABLE IF NOT EXISTS tavern_sessions (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, world_asset_type TEXT NULL,
      world_asset_id TEXT NULL, persona_type TEXT NULL, persona_id TEXT NULL,
      runtime_config_id TEXT NULL, active_story_line_id TEXT NULL,
      metadata_json TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL, archived_at TEXT NULL, deleted_at TEXT NULL,
      FOREIGN KEY (active_story_line_id) REFERENCES tavern_story_lines(id) ON DELETE RESTRICT
    )''',
    '''CREATE TABLE IF NOT EXISTS tavern_participants (
      id TEXT PRIMARY KEY, session_id TEXT NOT NULL, kind TEXT NOT NULL
        CHECK (kind IN ('persona','character','system','tool','external')),
      entity_id TEXT NULL, display_name TEXT NOT NULL DEFAULT '',
      position INTEGER NOT NULL CHECK (position >= 0), metadata_json TEXT NOT NULL DEFAULT '{}',
      UNIQUE (session_id, position),
      FOREIGN KEY (session_id) REFERENCES tavern_sessions(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS tavern_story_lines (
      id TEXT PRIMARY KEY, session_id TEXT NOT NULL, parent_id TEXT NULL,
      origin_turn_id TEXT NULL, origin_alternative_id TEXT NULL,
      name TEXT NOT NULL, position INTEGER NOT NULL CHECK (position >= 0),
      metadata_json TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL,
      archived_at TEXT NULL,
      UNIQUE (session_id, position),
      FOREIGN KEY (session_id) REFERENCES tavern_sessions(id) ON DELETE CASCADE,
      FOREIGN KEY (parent_id) REFERENCES tavern_story_lines(id) ON DELETE RESTRICT,
      FOREIGN KEY (origin_turn_id) REFERENCES tavern_turns(id) ON DELETE RESTRICT,
      FOREIGN KEY (origin_alternative_id) REFERENCES tavern_alternatives(id) ON DELETE RESTRICT
    )''',
    '''CREATE TABLE IF NOT EXISTS tavern_turns (
      id TEXT PRIMARY KEY, session_id TEXT NOT NULL, story_line_id TEXT NOT NULL,
      position INTEGER NOT NULL CHECK (position >= 0),
      participant_id TEXT NOT NULL, role TEXT NOT NULL
        CHECK (role IN ('player','character','narrator','system','tool')),
      selected_alternative_id TEXT NULL, created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL, edited_at TEXT NULL, metadata_json TEXT NOT NULL DEFAULT '{}',
      UNIQUE (story_line_id, position),
      FOREIGN KEY (session_id) REFERENCES tavern_sessions(id) ON DELETE CASCADE,
      FOREIGN KEY (story_line_id) REFERENCES tavern_story_lines(id) ON DELETE RESTRICT,
      FOREIGN KEY (participant_id) REFERENCES tavern_participants(id) ON DELETE RESTRICT,
      FOREIGN KEY (selected_alternative_id) REFERENCES tavern_alternatives(id) ON DELETE RESTRICT
    )''',
    '''CREATE TABLE IF NOT EXISTS tavern_alternatives (
      id TEXT PRIMARY KEY, turn_id TEXT NOT NULL, position INTEGER NOT NULL CHECK (position >= 0),
      origin TEXT NOT NULL CHECK (origin IN ('manual','generated','imported')),
      created_at TEXT NOT NULL, edited_at TEXT NULL, metadata_json TEXT NOT NULL DEFAULT '{}',
      UNIQUE (turn_id, position),
      FOREIGN KEY (turn_id) REFERENCES tavern_turns(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS tavern_line_selections (
      id TEXT PRIMARY KEY, story_line_id TEXT NOT NULL,
      turn_id TEXT NOT NULL, alternative_id TEXT NOT NULL,
      UNIQUE (story_line_id, turn_id),
      FOREIGN KEY (story_line_id) REFERENCES tavern_story_lines(id) ON DELETE CASCADE,
      FOREIGN KEY (turn_id) REFERENCES tavern_turns(id) ON DELETE RESTRICT,
      FOREIGN KEY (alternative_id) REFERENCES tavern_alternatives(id) ON DELETE RESTRICT
    )''',
    '''CREATE TABLE IF NOT EXISTS tavern_content_parts (
      id TEXT PRIMARY KEY, alternative_id TEXT NOT NULL,
      position INTEGER NOT NULL CHECK (position >= 0),
      kind TEXT NOT NULL,
      text_value TEXT NULL, tool_name TEXT NULL, tool_call_id TEXT NULL,
      arguments_json TEXT NULL, result_json TEXT NULL, error_text TEXT NULL,
      asset_reference TEXT NULL, mime_type TEXT NULL, generation_attempt_id TEXT NULL,
      created_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}',
      UNIQUE (alternative_id, position),
      FOREIGN KEY (alternative_id) REFERENCES tavern_alternatives(id) ON DELETE CASCADE,
      FOREIGN KEY (generation_attempt_id) REFERENCES tavern_generation_attempts(id) ON DELETE RESTRICT
    )''',
    '''CREATE TABLE IF NOT EXISTS tavern_generation_attempts (
      id TEXT PRIMARY KEY, session_id TEXT NOT NULL, story_line_id TEXT NOT NULL,
      turn_id TEXT NOT NULL, alternative_id TEXT NOT NULL,
      position INTEGER NOT NULL CHECK (position >= 0),
      status TEXT NOT NULL CHECK (status IN ('queued','preparing','running','streaming','cancelled','failed','completed')),
      generation_type TEXT NOT NULL CHECK (generation_type IN ('normal','regenerate','alternative','continue','impersonate','group','quiet')),
      provider_reference TEXT NULL, model_reference TEXT NULL,
      failure_reason TEXT NULL, cancel_reason TEXT NULL, has_partial_content INTEGER NOT NULL DEFAULT 0 CHECK (has_partial_content IN (0,1)),
      created_at TEXT NOT NULL, started_at TEXT NULL, ended_at TEXT NULL,
      metadata_json TEXT NOT NULL DEFAULT '{}',
      UNIQUE (alternative_id, position),
      FOREIGN KEY (session_id) REFERENCES tavern_sessions(id) ON DELETE CASCADE,
      FOREIGN KEY (story_line_id) REFERENCES tavern_story_lines(id) ON DELETE RESTRICT,
      FOREIGN KEY (turn_id) REFERENCES tavern_turns(id) ON DELETE RESTRICT,
      FOREIGN KEY (alternative_id) REFERENCES tavern_alternatives(id) ON DELETE RESTRICT
    )''',
  ];

  static const indexes = <String>[
    'CREATE INDEX IF NOT EXISTS idx_tavern_lines_parent ON tavern_story_lines(parent_id, position)',
    'CREATE INDEX IF NOT EXISTS idx_tavern_turns_line ON tavern_turns(story_line_id, position)',
    'CREATE INDEX IF NOT EXISTS idx_tavern_alternatives_turn ON tavern_alternatives(turn_id, position)',
    'CREATE INDEX IF NOT EXISTS idx_tavern_parts_alternative ON tavern_content_parts(alternative_id, position)',
    'CREATE INDEX IF NOT EXISTS idx_tavern_attempts_alternative ON tavern_generation_attempts(alternative_id, position)',
  ];
}
