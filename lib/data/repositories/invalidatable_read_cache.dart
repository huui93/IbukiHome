/// A process-lifetime read cache that can be cleared after an out-of-band
/// database replacement such as full archive restore.
abstract interface class InvalidatableReadCache {
  void invalidateAll();
}
