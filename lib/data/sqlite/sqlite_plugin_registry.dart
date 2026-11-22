import 'package:sqflite/sqflite.dart';

import '../../domain/plugins/ibuki_plugin_manifest.dart';
import '../../domain/plugins/installed_plugin.dart';
import '../repositories/plugin_registry.dart';
import 'ibuki_database.dart';
import 'sqlite_repository_helpers.dart';

class SQLitePluginRegistry implements PluginRegistry {
  SQLitePluginRegistry(this.ibukiDatabase);

  final IbukiDatabase ibukiDatabase;

  @override
  Future<void> deletePlugin(String id) async {
    final database = await ibukiDatabase.database;
    await handleSqliteWrite(
      () async {
        await database.delete(
          'installed_plugins',
          where: 'id = ?',
          whereArgs: [id],
        );
      },
      entityName: 'Plugin',
      entityId: id,
    );
  }

  @override
  Future<InstalledPlugin?> getPlugin(String id) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'installed_plugins',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromSql(rows.single);
  }

  @override
  Future<List<InstalledPlugin>> listPlugins() async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'installed_plugins',
      orderBy: 'enabled DESC, name ASC, id ASC',
    );
    return List.unmodifiable(rows.map(_fromSql));
  }

  @override
  Future<void> upsertPlugin(InstalledPlugin plugin) async {
    final database = await ibukiDatabase.database;
    await handleSqliteWrite(
      () async {
        await database.insert(
          'installed_plugins',
          _toSql(plugin),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      },
      entityName: 'Plugin',
      entityId: plugin.id,
    );
  }

  Map<String, Object?> _toSql(InstalledPlugin plugin) => <String, Object?>{
    'id': plugin.id,
    'name': plugin.manifest.name,
    'version': plugin.manifest.version,
    'author': plugin.manifest.author,
    'description': plugin.manifest.description,
    'manifest_version': plugin.manifest.manifestVersion,
    'manifest_json': plugin.manifest.encode(),
    'installed_path': plugin.installedPath,
    'data_path': plugin.dataPath,
    'enabled': plugin.enabled ? 1 : 0,
    'status': plugin.status.name,
    'error_category': plugin.errorCategory,
    'package_size': plugin.packageSize,
    'extracted_size': plugin.extractedSize,
    'installed_at': plugin.installedAt.toUtc().toIso8601String(),
    'updated_at': plugin.updatedAt.toUtc().toIso8601String(),
  };

  InstalledPlugin _fromSql(Map<String, Object?> row) {
    IbukiPluginManifest manifest;
    var manifestBroken = false;
    try {
      manifest = IbukiPluginManifest.parse(row['manifest_json'] as String);
    } catch (_) {
      manifestBroken = true;
      manifest = IbukiPluginManifest(
        manifestVersion: row['manifest_version'] as int? ?? 1,
        id: row['id'] as String? ?? 'broken-plugin',
        name: row['name'] as String? ?? '损坏的插件',
        version: row['version'] as String? ?? '0.0.0',
        author: row['author'] as String? ?? '',
        description: row['description'] as String? ?? '',
      );
    }
    final statusName = row['status'] as String? ?? 'broken';
    final storedStatus = InstalledPluginStatus.values.firstWhere(
      (item) => item.name == statusName,
      orElse: () => InstalledPluginStatus.broken,
    );
    final installedAt = DateTime.tryParse(row['installed_at'] as String? ?? '');
    final updatedAt = DateTime.tryParse(row['updated_at'] as String? ?? '');
    return InstalledPlugin(
      manifest: manifest,
      installedPath: row['installed_path'] as String? ?? '',
      dataPath: row['data_path'] as String? ?? '',
      enabled: (row['enabled'] as int? ?? 0) == 1,
      status: manifestBroken ? InstalledPluginStatus.broken : storedStatus,
      errorCategory: manifestBroken
          ? 'registryManifestInvalid'
          : row['error_category'] as String?,
      packageSize: row['package_size'] as int? ?? 0,
      extractedSize: row['extracted_size'] as int? ?? 0,
      installedAt: (installedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .toUtc(),
      updatedAt: (updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).toUtc(),
    );
  }
}
