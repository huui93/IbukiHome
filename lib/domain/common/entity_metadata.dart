import '../../core/errors/data_exceptions.dart';

const Object _unset = Object();

class EntityMetadata {
  const EntityMetadata({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    this.deletedAt,
  });

  /// Opaque stable identifier. Business code must not parse it.
  final String id;

  /// Creation time in UTC.
  final DateTime createdAt;

  /// Last update time in UTC.
  final DateTime updatedAt;

  /// Monotonic entity revision, starting from 1.
  final int revision;

  /// Non-null means the entity is soft-deleted.
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  EntityMetadata copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? revision,
    Object? deletedAt = _unset,
  }) {
    return EntityMetadata(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      revision: revision ?? this.revision,
      deletedAt: deletedAt == _unset ? this.deletedAt : deletedAt as DateTime?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'created_at': dateTimeToJson(createdAt),
      'updated_at': dateTimeToJson(updatedAt),
      'revision': revision,
      'deleted_at': deletedAt == null ? null : dateTimeToJson(deletedAt!),
    };
  }

  factory EntityMetadata.fromJson(
    Map<String, dynamic> json, {
    String modelName = 'EntityMetadata',
  }) {
    final id = readRequiredString(json, 'id', modelName);
    if (id.trim().isEmpty) {
      throw DataFormatException('$modelName.id must not be empty.');
    }

    final revision = readRequiredInt(json, 'revision', modelName);
    if (revision < 1) {
      throw DataFormatException('$modelName.revision must be 1 or greater.');
    }

    return EntityMetadata(
      id: id,
      createdAt: readRequiredDateTime(json, 'created_at', modelName),
      updatedAt: readRequiredDateTime(json, 'updated_at', modelName),
      revision: revision,
      deletedAt: readOptionalDateTime(json, 'deleted_at', modelName),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EntityMetadata &&
        id == other.id &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt &&
        revision == other.revision &&
        deletedAt == other.deletedAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, createdAt, updatedAt, revision, deletedAt);
}

String readRequiredString(
  Map<String, dynamic> json,
  String key,
  String modelName,
) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  throw DataFormatException('$modelName.$key must be a string.');
}

String readOptionalString(
  Map<String, dynamic> json,
  String key,
  String modelName, {
  String defaultValue = '',
}) {
  final value = json[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is String) {
    return value;
  }
  throw DataFormatException('$modelName.$key must be a string when present.');
}

int readRequiredInt(Map<String, dynamic> json, String key, String modelName) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw DataFormatException('$modelName.$key must be an integer.');
}

int readOptionalInt(
  Map<String, dynamic> json,
  String key,
  String modelName, {
  int defaultValue = 0,
}) {
  final value = json[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is int) {
    return value;
  }
  throw DataFormatException('$modelName.$key must be an integer when present.');
}

bool readOptionalBool(
  Map<String, dynamic> json,
  String key,
  String modelName, {
  bool defaultValue = false,
}) {
  final value = json[key];
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is int && (value == 0 || value == 1)) return value == 1;
  throw DataFormatException('$modelName.$key must be a boolean when present.');
}

DateTime readRequiredDateTime(
  Map<String, dynamic> json,
  String key,
  String modelName,
) {
  final value = json[key];
  if (value is! String) {
    throw DataFormatException('$modelName.$key must be an ISO 8601 string.');
  }
  return _parseUtcDateTime(value, '$modelName.$key');
}

DateTime? readOptionalDateTime(
  Map<String, dynamic> json,
  String key,
  String modelName,
) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw DataFormatException('$modelName.$key must be an ISO 8601 string.');
  }
  return _parseUtcDateTime(value, '$modelName.$key');
}

String? readOptionalNullableString(
  Map<String, dynamic> json,
  String key,
  String modelName,
) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw DataFormatException('$modelName.$key must be a string when present.');
}

String dateTimeToJson(DateTime value) => value.toUtc().toIso8601String();

DateTime _parseUtcDateTime(String value, String fieldName) {
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw DataFormatException('$fieldName must be a valid ISO 8601 date.');
  }
}
