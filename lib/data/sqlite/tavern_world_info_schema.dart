class TavernWorldInfoSchema {
  static List<String> get tables => statements(jsonFunctions: true);

  // JSON SQL functions are optional on Android. Typed repository/archive
  // validation is mandatory on every platform; SQL checks are additional.
  static List<String> statements({required bool jsonFunctions}) => [
    '''CREATE TABLE IF NOT EXISTS tavern_world_info_states (
      id TEXT PRIMARY KEY, session_id TEXT NOT NULL, story_line_id TEXT NOT NULL UNIQUE,
      version INTEGER NOT NULL DEFAULT 0 CHECK(version >= 0),
      data_json TEXT NOT NULL ${jsonFunctions ? 'CHECK(json_valid(data_json))' : ''},
      initial_data_json TEXT NOT NULL ${jsonFunctions ? 'CHECK(json_valid(initial_data_json))' : ''},
      provenance TEXT NOT NULL CHECK(provenance IN ('fresh','legacyUnavailable','historicalUnavailable','forkCheckpoint')),
      last_attempt_id TEXT NULL, initial_attempt_id TEXT NULL,
      CHECK(id = story_line_id),
      FOREIGN KEY(session_id) REFERENCES tavern_sessions(id) ON DELETE CASCADE,
      FOREIGN KEY(story_line_id) REFERENCES tavern_story_lines(id) ON DELETE CASCADE,
      FOREIGN KEY(last_attempt_id) REFERENCES tavern_generation_attempts(id) ON DELETE RESTRICT,
      FOREIGN KEY(initial_attempt_id) REFERENCES tavern_generation_attempts(id) ON DELETE RESTRICT
    )''',
    '''CREATE TABLE IF NOT EXISTS tavern_world_info_journal (
      id TEXT PRIMARY KEY, attempt_id TEXT NOT NULL UNIQUE, session_id TEXT NOT NULL,
      story_line_id TEXT NOT NULL, turn_id TEXT NOT NULL, alternative_id TEXT NOT NULL,
      expected_version INTEGER NOT NULL CHECK(expected_version >= 0),
      compile_fingerprint TEXT NOT NULL, request_fingerprint TEXT NOT NULL,
      plan_identity TEXT NOT NULL, plan_json TEXT NOT NULL ${jsonFunctions ? 'CHECK(json_valid(plan_json))' : ''},
      outcome TEXT NOT NULL CHECK(outcome IN ('prepared','committed','discarded','conflict')),
      committed_version INTEGER NULL CHECK(committed_version > 0), reason TEXT NULL,
      original_plan_identity TEXT NULL,
      CHECK(id = attempt_id),
      ${jsonFunctions ? "CHECK(json_extract(plan_json,'\$.attempt') = attempt_id AND json_extract(plan_json,'\$.session') = session_id AND json_extract(plan_json,'\$.line') = story_line_id AND json_extract(plan_json,'\$.turn') = turn_id AND json_extract(plan_json,'\$.alternative') = alternative_id)," : ''}
      UNIQUE(story_line_id, committed_version),
      FOREIGN KEY(attempt_id) REFERENCES tavern_generation_attempts(id) ON DELETE RESTRICT,
      FOREIGN KEY(session_id) REFERENCES tavern_sessions(id) ON DELETE CASCADE,
      FOREIGN KEY(story_line_id) REFERENCES tavern_story_lines(id) ON DELETE RESTRICT,
      FOREIGN KEY(turn_id) REFERENCES tavern_turns(id) ON DELETE RESTRICT,
      FOREIGN KEY(alternative_id) REFERENCES tavern_alternatives(id) ON DELETE RESTRICT
    )''',
  ];
  static const indexes = [
    'CREATE INDEX IF NOT EXISTS idx_tavern_wi_pending ON tavern_world_info_journal(outcome, session_id, story_line_id, expected_version)',
    'CREATE INDEX IF NOT EXISTS idx_tavern_wi_history ON tavern_world_info_journal(alternative_id, outcome, committed_version)',
  ];
}
