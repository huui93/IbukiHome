import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/errors/data_exceptions.dart';
import 'sqlite_migrations.dart';
import 'sqlite_schema.dart';

class DatabaseClosedException extends DataException {
  const DatabaseClosedException() : super('The SQLite database is closed.');
}

class IbukiDatabase {
  IbukiDatabase({
    Future<String> Function()? pathResolver,
    this._databaseFactory,
  }) : _pathResolver = pathResolver ?? _productionPath;

  final Future<String> Function() _pathResolver;
  final DatabaseFactory? _databaseFactory;

  Database? _database;
  Future<Database>? _opening;
  bool _closed = false;
  String? _path;
  int _openCount = 0;

  String? get path => _path;
  int get openCount => _openCount;

  Future<Database> get database => open();

  Future<Database> open() async {
    if (_closed) {
      throw const DatabaseClosedException();
    }
    final existing = _database;
    if (existing != null && existing.isOpen) {
      return existing;
    }
    final opening = _opening;
    if (opening != null) {
      return opening;
    }

    final future = _openDatabase();
    _opening = future;
    try {
      final database = await future;
      _database = database;
      _openCount += 1;
      return database;
    } finally {
      _opening = null;
    }
  }

  Future<void> close() async {
    _closed = true;
    final database = _database;
    _database = null;
    if (database != null && database.isOpen) {
      await database.close();
    }
  }

  Future<Database> _openDatabase() async {
    final resolved = await _pathResolver();
    _path = resolved;
    final options = OpenDatabaseOptions(
      version: SqliteSchema.version,
      onConfigure: _configure,
      onCreate: (db, version) async {
        await createLatestSchema(db);
      },
      onUpgrade: runMigrations,
      onOpen: ensureCurrentSchema,
      onDowngrade: (db, oldVersion, newVersion) {
        throw UnsupportedDatabaseVersionException(oldVersion, newVersion);
      },
    );

    final factory = _databaseFactory;
    if (factory != null) {
      return factory.openDatabase(resolved, options: options);
    }
    return openDatabase(
      resolved,
      version: options.version,
      onConfigure: options.onConfigure,
      onCreate: options.onCreate,
      onUpgrade: options.onUpgrade,
      onOpen: options.onOpen,
      onDowngrade: options.onDowngrade,
    );
  }

  static Future<void> _configure(Database db) async {
    await db.rawQuery('PRAGMA foreign_keys = ON');
    await db.rawQuery('PRAGMA busy_timeout = 3000');
  }

  static Future<String> _productionPath() async {
    final databaseDirectory = await getDatabasesPath();
    return p.join(databaseDirectory, SqliteSchema.databaseName);
  }
}
