import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/errors/plugin_exceptions.dart';
import '../repositories/plugin_storage_repository.dart';
import 'ibuki_database.dart';

class SQLitePluginStorageRepository implements PluginStorageRepository {
  SQLitePluginStorageRepository(this.ibukiDatabase);

  final IbukiDatabase ibukiDatabase;
  @override
  Future<Map<String, Object?>> listValues(String pluginId) async {
    final rows = await (await ibukiDatabase.database).query(
      'plugin_storage',
      columns: ['storage_key', 'value_json'],
      where: 'plugin_id=?',
      whereArgs: [pluginId],
    );
    return {
      for (final row in rows)
        row['storage_key'] as String: jsonDecode(row['value_json'] as String),
    };
  }

  @override
  Future<void> clearPlugin(String pluginId) async {
    final database = await ibukiDatabase.database;
    await database.delete(
      'plugin_storage',
      where: 'plugin_id = ?',
      whereArgs: [pluginId],
    );
  }

  @override
  Future<void> clearPluginUserValues(String pluginId) async {
    final database = await ibukiDatabase.database;
    await database.delete(
      'plugin_storage',
      where: "plugin_id = ? AND storage_key NOT LIKE '__ibuki_host__:%'",
      whereArgs: [pluginId],
    );
  }

  @override
  Future<Object?> getValue(String pluginId, String key) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'plugin_storage',
      columns: const ['value_json'],
      where: 'plugin_id = ? AND storage_key = ?',
      whereArgs: [pluginId, key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      return jsonDecode(rows.single['value_json'] as String);
    } on FormatException {
      throw const PluginException(
        PluginErrorCategory.storageFailure,
        '插件设置数据已损坏。',
      );
    }
  }

  @override
  Future<void> removeValue(String pluginId, String key) async {
    final database = await ibukiDatabase.database;
    await database.delete(
      'plugin_storage',
      where: 'plugin_id = ? AND storage_key = ?',
      whereArgs: [pluginId, key],
    );
  }

  @override
  Future<void> setValue(String pluginId, String key, Object? value) async {
    final database = await ibukiDatabase.database;
    try {
      await database.insert('plugin_storage', <String, Object?>{
        'plugin_id': pluginId,
        'storage_key': key,
        'value_json': jsonEncode(value),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } on DatabaseException catch (error) {
      throw PluginException(
        PluginErrorCategory.storageFailure,
        '插件设置保存失败。',
        detail: error.toString(),
      );
    }
  }
}
