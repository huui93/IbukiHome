import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/plugins/plugin_storage.dart';
import 'package:ibukihome/core/errors/plugin_exceptions.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_plugin_storage_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('PluginStorage persists JSON after database restart', () async {
    final fixture = await _fixture();
    try {
      final first = PluginStorage(
        pluginId: 'plugin.a',
        repository: SQLitePluginStorageRepository(fixture.database),
      );
      await first.set('ui.displayMode', {
        'mode': 'compact',
        'sections': [true, false],
      });
      await fixture.database.close();

      final reopened = IbukiDatabase(
        pathResolver: () async => fixture.path,
        databaseFactory: databaseFactoryFfi,
      );
      final second = PluginStorage(
        pluginId: 'plugin.a',
        repository: SQLitePluginStorageRepository(reopened),
      );
      expect(await second.get('ui.displayMode'), {
        'mode': 'compact',
        'sections': [true, false],
      });
      await reopened.close();
    } finally {
      await fixture.dispose();
    }
  });

  test('SQLite namespaces identical keys by plugin id', () async {
    final fixture = await _fixture();
    try {
      final repository = SQLitePluginStorageRepository(fixture.database);
      final a = PluginStorage(pluginId: 'plugin.a', repository: repository);
      final b = PluginStorage(pluginId: 'plugin.b', repository: repository);
      await a.set('uiState', 'a');
      await b.set('uiState', 'b');
      expect(await a.get('uiState'), 'a');
      expect(await b.get('uiState'), 'b');
    } finally {
      await fixture.dispose();
    }
  });

  test('malformed stored JSON is isolated to that key', () async {
    final fixture = await _fixture();
    try {
      final database = await fixture.database.database;
      await database.insert('plugin_storage', {
        'plugin_id': 'plugin.a',
        'storage_key': 'broken',
        'value_json': '{broken',
        'updated_at': '2026-08-26T00:00:00.000Z',
      });
      final storage = PluginStorage(
        pluginId: 'plugin.a',
        repository: SQLitePluginStorageRepository(fixture.database),
      );
      await expectLater(
        storage.get('broken'),
        throwsA(
          isA<PluginException>().having(
            (error) => error.category,
            'category',
            PluginErrorCategory.storageFailure,
          ),
        ),
      );
      expect(await database.getVersion(), SqliteSchema.version);
      expect(
        await database.rawQuery('SELECT COUNT(*) AS count FROM projects'),
        isNotEmpty,
      );
    } finally {
      await fixture.dispose();
    }
  });

  test('remove and clear persist without touching other namespaces', () async {
    final fixture = await _fixture();
    try {
      final repository = SQLitePluginStorageRepository(fixture.database);
      final a = PluginStorage(pluginId: 'plugin.a', repository: repository);
      final b = PluginStorage(pluginId: 'plugin.b', repository: repository);
      await a.set('one', 1);
      await a.set('two', 2);
      await b.set('one', 3);
      await a.remove('one');
      expect(await a.get('one'), isNull);
      expect(await a.get('two'), 2);
      await a.clear();
      expect(await a.get('two'), isNull);
      expect(await b.get('one'), 3);
    } finally {
      await fixture.dispose();
    }
  });

  test(
    'fresh schema retains plugin foundation tables at the current version',
    () async {
      final fixture = await _fixture();
      try {
        final database = await fixture.database.database;
        expect(await database.getVersion(), SqliteSchema.version);
        final tables = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        );
        final names = tables.map((row) => row['name']).toSet();
        expect(names, containsAll(['installed_plugins', 'plugin_storage']));
        expect(names, containsAll(['projects', 'segments', 'chat_messages']));
      } finally {
        await fixture.dispose();
      }
    },
  );
}

class _Fixture {
  const _Fixture(this.directory, this.path, this.database);

  final Directory directory;
  final String path;
  final IbukiDatabase database;

  Future<void> dispose() async {
    await database.close();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

Future<_Fixture> _fixture() async {
  final directory = await Directory.systemTemp.createTemp('plugin_storage_');
  final path = p.join(directory.path, 'ibukihome.db');
  final database = IbukiDatabase(
    pathResolver: () async => path,
    databaseFactory: databaseFactoryFfi,
  );
  await database.open();
  return _Fixture(directory, path, database);
}
