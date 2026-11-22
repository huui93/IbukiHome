enum MemoryGenerationStatus {
  valid,
  stale,
  generating,
  failed;

  String get jsonValue => name;

  static MemoryGenerationStatus fromJson(String value) {
    return MemoryGenerationStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () => MemoryGenerationStatus.stale,
    );
  }
}
