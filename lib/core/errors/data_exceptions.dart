class DataException implements Exception {
  const DataException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class DataFormatException extends DataException {
  const DataFormatException(super.message);
}

class EntityNotFoundException extends DataException {
  EntityNotFoundException(this.entityType, this.id)
    : super('$entityType was not found: $id');

  final String entityType;
  final String id;
}

class DuplicateEntityException extends DataException {
  DuplicateEntityException(this.entityType, this.id)
    : super('$entityType already exists: $id');

  final String entityType;
  final String id;
}

class DataConflictException extends DataException {
  const DataConflictException(super.message);
}

enum AiPersistenceStage {
  segmentSave,
  revisionSave,
  projectSave,
  summarySave,
  digestSave,
}

class AiPersistenceException extends DataException {
  const AiPersistenceException({
    required this.stage,
    required this.causeType,
    required String message,
  }) : super(message);

  final AiPersistenceStage stage;
  final String causeType;
}
