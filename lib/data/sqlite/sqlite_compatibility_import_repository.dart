import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../application/import/sillytavern_import_plan.dart';
import '../../core/errors/data_exceptions.dart';
import '../../domain/import/external_compatibility_payload.dart';
import '../../domain/world_roleplay/world_roleplay_models.dart';
import '../repositories/compatibility_import_repository.dart';
import 'ibuki_database.dart';
import 'sqlite_repository_helpers.dart';
import 'sqlite_value_codec.dart';

class SQLiteCompatibilityImportRepository
    implements CompatibilityImportRepository {
  SQLiteCompatibilityImportRepository(this.ibukiDatabase);

  final IbukiDatabase ibukiDatabase;

  @override
  Future<List<ExternalCompatibilityPayload>> listPayloads() async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'external_compatibility_payloads',
      columns: _summaryColumns,
      orderBy: 'created_at DESC, id ASC',
    );
    return List.unmodifiable(rows.map(_payloadFromSql));
  }

  @override
  Future<ExternalCompatibilityPayload> getPayload(String id) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'external_compatibility_payloads',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw EntityNotFoundException('ExternalCompatibilityPayload', id);
    }
    return _payloadFromSql(rows.single);
  }

  @override
  Future<List<ExternalCompatibilityPayload>> findBySourceSha256(
    String sha256,
  ) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'external_compatibility_payloads',
      columns: _summaryColumns,
      where: 'source_sha256 = ?',
      whereArgs: [sha256],
      orderBy: 'created_at DESC, id ASC',
    );
    return List.unmodifiable(rows.map(_payloadFromSql));
  }

  @override
  Future<List<ExternalCompatibilityPayload>> listForEntity(
    String linkedEntityType,
    String linkedEntityId,
  ) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'external_compatibility_payloads',
      columns: [
        ..._identityColumns,
        'normalized_payload_json',
        "'{}' AS unsupported_payload_json",
      ],
      where: 'linked_entity_type = ? AND linked_entity_id = ?',
      whereArgs: [linkedEntityType, linkedEntityId],
      orderBy: 'created_at DESC, id ASC',
    );
    return List.unmodifiable(rows.map(_payloadFromSql));
  }

  @override
  Future<void> commitImport(SillyTavernImportWrite write) async {
    final db = await ibukiDatabase.database;
    await handleSqliteWrite(
      () => db.transaction((txn) async {
        if (write.project != null) {
          await txn.insert(
            'projects',
            projectToSql(write.project!),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
        if (write.character != null) {
          await txn.insert(
            'character_cards',
            characterCardToSql(write.character!),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
        if (write.worldBook != null) {
          if (write.worldBook!.worldId == null) {
            final now = DateTime.now().toUtc().toIso8601String();
            await txn.insert('roleplay_worlds', {
              'id': worldBookLibraryOwnerId,
              'name': 'WorldBook Library',
              'description': '',
              'default_session_id': null,
              'metadata_json': '{"hidden":true}',
              'created_at': now,
              'updated_at': now,
              'revision': 1,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
          await txn.insert(
            'world_books',
            _bookToSql(write.worldBook!),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
        for (final entry in write.loreEntries) {
          await txn.insert(
            'lore_entries',
            _loreToSql(entry),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
        if (write.worldBookReference != null) {
          await txn.insert(
            'world_world_book_references',
            _worldBookReferenceToSql(write.worldBookReference!),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
        if (write.characterBookReference != null) {
          await txn.insert(
            'character_world_book_references',
            _entityBookReferenceToSql(
              write.characterBookReference!,
              'character_card_id',
            ),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
        if (write.persona != null) {
          await txn.insert(
            'player_personas',
            _personaToSql(write.persona!),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
        if (write.updatedWorld != null) {
          final values = _promptUpdateToSql(write.updatedWorld!);
          final changed = await txn.update(
            'roleplay_worlds',
            values,
            where: 'id = ? AND revision = ?',
            whereArgs: [
              write.updatedWorld!.id,
              write.updatedWorld!.entity.revision - 1,
            ],
          );
          if (changed != 1) {
            throw const DataConflictException('世界设置已变化，请重新预览后导入。');
          }
        }
        if (write.updatedSession != null) {
          final values = _promptUpdateToSql(write.updatedSession!);
          final changed = await txn.update(
            'world_sessions',
            values,
            where: 'id = ? AND revision = ?',
            whereArgs: [
              write.updatedSession!.id,
              write.updatedSession!.entity.revision - 1,
            ],
          );
          if (changed != 1) {
            throw const DataConflictException('故事已变化，请重新预览后导入。');
          }
        }
        await txn.insert(
          'external_compatibility_payloads',
          _payloadToSql(write.payload),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }),
      entityName: 'SillyTavernImport',
      entityId: write.payload.id,
    );
  }

  @override
  Future<void> deletePayload(String id) async {
    final db = await ibukiDatabase.database;
    final changed = await db.delete(
      'external_compatibility_payloads',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed == 0) {
      throw EntityNotFoundException('ExternalCompatibilityPayload', id);
    }
  }
}

const _identityColumns = [
  'id',
  'source_type',
  'source_format',
  'source_version',
  'source_sha256',
  'linked_entity_type',
  'linked_entity_id',
  'security_flags_json',
  'import_warnings_json',
  'created_at',
  'metadata_json',
];
const _summaryColumns = [
  ..._identityColumns,
  "'{}' AS normalized_payload_json",
  "'{}' AS unsupported_payload_json",
];

Map<String, Object?> _payloadToSql(ExternalCompatibilityPayload payload) => {
  'id': payload.id,
  'source_type': payload.sourceType.name,
  'source_format': payload.sourceFormat,
  'source_version': payload.sourceVersion,
  'source_sha256': payload.sourceSha256,
  'linked_entity_type': payload.linkedEntityType,
  'linked_entity_id': payload.linkedEntityId,
  'normalized_payload_json': jsonEncode(payload.normalizedPayload),
  'unsupported_payload_json': jsonEncode(payload.unsupportedPayload),
  'security_flags_json': jsonEncode(payload.securityFlags),
  'import_warnings_json': jsonEncode(payload.importWarnings),
  'created_at': payload.createdAt.toUtc().toIso8601String(),
  'metadata_json': jsonEncode(payload.metadata),
};

ExternalCompatibilityPayload _payloadFromSql(Map<String, Object?> row) {
  const model = 'ExternalCompatibilityPayload';
  return ExternalCompatibilityPayload(
    id: _requiredString(row, 'id', model),
    sourceType: ExternalCompatibilitySourceType.values.firstWhere(
      (item) => item.name == _requiredString(row, 'source_type', model),
      orElse: () => ExternalCompatibilitySourceType.sillyTavern,
    ),
    sourceFormat: _requiredString(row, 'source_format', model),
    sourceVersion: _requiredString(row, 'source_version', model),
    sourceSha256: _requiredString(row, 'source_sha256', model),
    linkedEntityType: _requiredString(row, 'linked_entity_type', model),
    linkedEntityId: _requiredString(row, 'linked_entity_id', model),
    normalizedPayload: _mapJson(row, 'normalized_payload_json', model),
    unsupportedPayload: _mapJson(row, 'unsupported_payload_json', model),
    securityFlags: _stringList(row, 'security_flags_json', model),
    importWarnings: _stringList(row, 'import_warnings_json', model),
    createdAt: DateTime.parse(
      _requiredString(row, 'created_at', model),
    ).toUtc(),
    metadata: _mapJson(row, 'metadata_json', model),
  );
}

Map<String, Object?> _entityToSql(WorldRoleplayEntity value) => {
  'id': value.id,
  'created_at': value.createdAt.toUtc().toIso8601String(),
  'updated_at': value.updatedAt.toUtc().toIso8601String(),
  'revision': value.revision,
  'metadata_json': jsonEncode(value.metadata),
};

Map<String, Object?> _bookToSql(WorldBook value) => {
  ..._entityToSql(value),
  'world_id': value.worldId ?? worldBookLibraryOwnerId,
  'name': value.name,
  'is_primary': value.isPrimary ? 1 : 0,
};

Map<String, Object?> _worldBookReferenceToSql(WorldWorldBookReference value) =>
    {
      ..._entityToSql(value),
      'world_id': value.worldId,
      'world_book_id': value.worldBookId,
      'enabled': value.enabled ? 1 : 0,
      'priority': value.priority,
    };

Map<String, Object?> _entityBookReferenceToSql(
  EntityWorldBookReference value,
  String ownerColumn,
) => {
  ..._entityToSql(value),
  ownerColumn: value.entityId,
  'world_book_id': value.worldBookId,
  'enabled': value.enabled ? 1 : 0,
  'priority': value.priority,
};

Map<String, Object?> _loreToSql(LoreEntry value) => {
  ..._entityToSql(value),
  'world_book_id': value.worldBookId,
  'title': value.title,
  'content': value.content,
  'keywords_json': jsonEncode(value.keywords),
  'secondary_keywords_json': jsonEncode(value.secondaryKeywords),
  'enabled': value.enabled ? 1 : 0,
  'priority': value.priority,
  'activation_mode': value.activationMode.name,
  'insertion_position': value.insertionPosition,
  'probability': value.probability,
  'scope': value.scope,
  'token_budget_hint': value.tokenBudgetHint,
  'source_world_card_id': value.sourceWorldCardId,
};

Map<String, Object?> _personaToSql(PlayerPersona value) => {
  ..._entityToSql(value),
  'world_id': value.worldId,
  'name': value.name,
  'description': value.description,
  'appearance': value.appearance,
  'background': value.background,
  'notes': value.notes,
  'avatar_reference': value.avatarReference,
};

Map<String, Object?> _promptUpdateToSql(WorldRoleplayEntity value) => {
  'metadata_json': jsonEncode(value.metadata),
  'updated_at': value.updatedAt.toUtc().toIso8601String(),
  'revision': value.entity.revision,
};

String _requiredString(Map<String, Object?> row, String key, String model) {
  final value = row[key];
  if (value is! String) throw DataFormatException('$model.$key is invalid.');
  return value;
}

Map<String, Object?> _mapJson(
  Map<String, Object?> row,
  String key,
  String model,
) {
  final decoded = jsonDecode(_requiredString(row, key, model));
  if (decoded is! Map) throw DataFormatException('$model.$key is invalid.');
  return Map.unmodifiable(Map<String, Object?>.from(decoded));
}

List<String> _stringList(Map<String, Object?> row, String key, String model) {
  final decoded = jsonDecode(_requiredString(row, key, model));
  if (decoded is! List || decoded.any((item) => item is! String)) {
    throw DataFormatException('$model.$key is invalid.');
  }
  return List.unmodifiable(decoded.cast<String>());
}
