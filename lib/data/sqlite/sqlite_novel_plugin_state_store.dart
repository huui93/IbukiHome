import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../domain/plugins/novel_history_fingerprint.dart';
import '../../domain/plugins/novel_plugin_storage_keys.dart';
import '../repositories/plugin_storage_repository.dart';
import 'ibuki_database.dart';

/// Novel state can be restored before the optional executable package is installed.
class SQLiteNovelPluginStateStore implements PluginStorageRepository {
  SQLiteNovelPluginStateStore(this.database);
  final IbukiDatabase database;
  @override
  Future<Map<String, Object?>> listValues(String pluginId) async {
    final rows = await (await database.database).query(
      'novel_plugin_state',
      where: 'plugin_id=?',
      whereArgs: [pluginId],
    );
    return {
      for (final row in rows)
        row['storage_key'] as String: jsonDecode(row['value_json'] as String),
    };
  }

  @override
  Future<Object?> getValue(String pluginId, String key) async {
    final rows = await (await database.database).query(
      'novel_plugin_state',
      columns: ['value_json'],
      where: 'plugin_id=? AND storage_key=?',
      whereArgs: [pluginId, key],
    );
    return rows.isEmpty
        ? null
        : jsonDecode(rows.single['value_json'] as String);
  }

  @override
  Future<void> setValue(String pluginId, String key, Object? value) async {
    if (!isNovelPluginStorageKey(key)) {
      throw const FormatException('小说插件存储键无效。');
    }
    final db = await database.database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'novel_plugin_state',
        columns: ['id'],
        where: 'plugin_id=? AND storage_key=?',
        whereArgs: [pluginId, key],
      );
      await txn.insert('novel_plugin_state', {
        'id': existing.isEmpty
            ? 'novel_state:${novelContentHash('$pluginId|$key')}'
            : existing.single['id'],
        'project_id': novelPluginStorageOwner(key),
        'plugin_id': pluginId,
        'storage_key': key,
        'value_json': jsonEncode(value),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> removeValue(String pluginId, String key) async {
    await (await database.database).delete(
      'novel_plugin_state',
      where: 'plugin_id=? AND storage_key=?',
      whereArgs: [pluginId, key],
    );
  }

  @override
  Future<void> clearPlugin(String pluginId) async {
    await (await database.database).delete(
      'novel_plugin_state',
      where: 'plugin_id=?',
      whereArgs: [pluginId],
    );
  }

  @override
  Future<void> clearPluginUserValues(String pluginId) async {} // All keys are protected, scope-owned host namespaces.
}

class NovelRoutingPluginStorage implements PluginStorageRepository {
  const NovelRoutingPluginStorage(this.legacy, this.novel);
  final PluginStorageRepository legacy;
  final PluginStorageRepository novel;
  PluginStorageRepository _store(String key) =>
      isNovelPluginStorageKey(key) ? novel : legacy;
  @override
  Future<Map<String, Object?>> listValues(String pluginId) async => {
    ...await legacy.listValues(pluginId),
    ...await novel.listValues(pluginId),
  };
  @override
  Future<Object?> getValue(String pluginId, String key) =>
      _store(key).getValue(pluginId, key);
  @override
  Future<void> setValue(String pluginId, String key, Object? value) =>
      _store(key).setValue(pluginId, key, value);
  @override
  Future<void> removeValue(String pluginId, String key) =>
      _store(key).removeValue(pluginId, key);
  @override
  Future<void> clearPlugin(String pluginId) async {
    await legacy.clearPlugin(pluginId);
    await novel.clearPlugin(pluginId);
  }

  @override
  Future<void> clearPluginUserValues(String pluginId) =>
      legacy.clearPluginUserValues(pluginId);
}
