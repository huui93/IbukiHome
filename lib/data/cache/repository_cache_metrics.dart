class RepositoryCacheMetrics {
  int delegateReads = 0;
  int cacheHits = 0;
  int writes = 0;

  int get totalReads => delegateReads + cacheHits;

  double get hitRate => totalReads == 0 ? 0 : cacheHits / totalReads;
}
