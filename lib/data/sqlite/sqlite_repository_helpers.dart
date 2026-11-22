import 'package:sqflite/sqflite.dart';

import '../../core/errors/data_exceptions.dart';

String activeWhere(String baseWhere, {required bool includeDeleted}) {
  if (includeDeleted) {
    return baseWhere;
  }
  return '($baseWhere) AND deleted_at IS NULL';
}

List<Object?> activeWhereArgs(List<Object?> args) => args;

Future<void> handleSqliteWrite(
  Future<void> Function() action, {
  required String entityName,
  required String entityId,
}) async {
  try {
    await action();
  } on DatabaseException catch (error) {
    throw _mapDatabaseException(error, entityName, entityId);
  }
}

DataException _mapDatabaseException(
  DatabaseException error,
  String entityName,
  String entityId,
) {
  final message = error.toString().toLowerCase();
  if (message.contains('unique') || message.contains('primary key')) {
    return DuplicateEntityException(entityName, entityId);
  }
  if (message.contains('foreign key') ||
      message.contains('check constraint') ||
      message.contains('constraint failed')) {
    return DataConflictException(
      '$entityName $entityId violates database constraints.',
    );
  }
  return DataConflictException('$entityName $entityId could not be saved.');
}
