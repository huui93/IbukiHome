class EntityIdGenerator {
  EntityIdGenerator();

  var _counter = 0;

  String nextId(String prefix) {
    final normalizedPrefix = prefix.trim().isEmpty ? 'entity' : prefix.trim();
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    _counter += 1;
    return '${normalizedPrefix}_${timestamp}_${_counter.toRadixString(36)}';
  }
}
