/// Synchronizes a read cache after another repository commits a transaction.
/// Implementations must only update memory, never issue another database write.
abstract interface class CommittedEntityCache<T> {
  void acceptCommittedEntity(T entity);
}
