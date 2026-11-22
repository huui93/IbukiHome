import '../../domain/chat/chat_memory_entry.dart';
import '../../domain/chat/conversation_summary.dart';
import '../../domain/chat/chat_memory_state.dart';
import '../../domain/memory/novel_summary_chunk.dart';
import '../../domain/memory/story_memory_digest.dart';
import '../../domain/reader/reader_preferences.dart';
import '../repositories/chat_memory_repository.dart';
import '../repositories/novel_memory_repository.dart';
import '../repositories/reader_repository.dart';
import '../repositories/invalidatable_read_cache.dart';
import 'repository_cache_metrics.dart';

class CachedNovelMemoryRepository
    implements NovelMemoryRepository, InvalidatableReadCache {
  CachedNovelMemoryRepository(this.delegate);

  final NovelMemoryRepository delegate;
  final metrics = RepositoryCacheMetrics();
  final Map<String, List<NovelSummaryChunk>> _chunks = {};
  final Map<String, StoryMemoryDigest?> _digests = {};

  @override
  void invalidateAll() {
    _chunks.clear();
    _digests.clear();
  }

  @override
  Future<List<NovelSummaryChunk>> listChunks(String projectId) async {
    final cached = _chunks[projectId];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    return _chunks[projectId] = await delegate.listChunks(projectId);
  }

  @override
  Future<NovelSummaryChunk?> getChunk(String id) async {
    for (final list in _chunks.values) {
      for (final chunk in list) {
        if (chunk.id == id) {
          metrics.cacheHits += 1;
          return chunk;
        }
      }
    }
    metrics.delegateReads += 1;
    return delegate.getChunk(id);
  }

  @override
  Future<void> upsertChunk(NovelSummaryChunk chunk) async {
    await delegate.upsertChunk(chunk);
    metrics.writes += 1;
    final list = [...?_chunks[chunk.projectId]]
      ..removeWhere((item) => item.id == chunk.id)
      ..add(chunk)
      ..sort((a, b) => a.sourceStartOrder.compareTo(b.sourceStartOrder));
    _chunks[chunk.projectId] = List.unmodifiable(list);
  }

  @override
  Future<void> deleteChunksFromOrder(String projectId, int fromOrder) async {
    await delegate.deleteChunksFromOrder(projectId, fromOrder);
    metrics.writes += 1;
    final cached = _chunks[projectId];
    if (cached != null) {
      _chunks[projectId] = List.unmodifiable(
        cached.where((item) => item.sourceEndOrder < fromOrder),
      );
    }
  }

  @override
  Future<StoryMemoryDigest?> getDigest(String projectId) async {
    if (_digests.containsKey(projectId)) {
      metrics.cacheHits += 1;
      return _digests[projectId];
    }
    metrics.delegateReads += 1;
    return _digests[projectId] = await delegate.getDigest(projectId);
  }

  @override
  Future<void> upsertDigest(StoryMemoryDigest digest) async {
    await delegate.upsertDigest(digest);
    metrics.writes += 1;
    _digests[digest.projectId] = digest;
  }
}

class CachedReaderRepository
    implements ReaderRepository, InvalidatableReadCache {
  CachedReaderRepository(this.delegate);

  final ReaderRepository delegate;
  final Map<String, ReaderPreferences> _preferences = {};
  final Map<String, ReaderProgress> _progress = {};

  @override
  void invalidateAll() {
    _preferences.clear();
    _progress.clear();
  }

  @override
  Future<ReaderPreferences> loadPreferences(String projectId) async =>
      _preferences[projectId] ??= await delegate.loadPreferences(projectId);

  @override
  Future<void> savePreferences(ReaderPreferences preferences) async {
    await delegate.savePreferences(preferences);
    _preferences[preferences.projectId] = preferences;
  }

  @override
  Future<ReaderProgress> loadProgress(String projectId) async =>
      _progress[projectId] ??= await delegate.loadProgress(projectId);

  @override
  Future<void> saveProgress(ReaderProgress progress) async {
    await delegate.saveProgress(progress);
    _progress[progress.projectId] = progress;
  }
}

class CachedChatMemoryRepository
    implements ChatMemoryRepository, InvalidatableReadCache {
  CachedChatMemoryRepository(this.delegate);

  final ChatMemoryRepository delegate;
  @override
  Future<ChatMemoryState?> getState(String sessionId) =>
      delegate.getState(sessionId);
  @override
  Future<bool> commitSessionMemory(
    ChatMemoryState state, {
    required int expectedRevision,
    List<ChatMemoryEntry> entries = const [],
    List<ConversationSummary> summaries = const [],
  }) async {
    final committed = await delegate.commitSessionMemory(
      state,
      expectedRevision: expectedRevision,
      entries: entries,
      summaries: summaries,
    );
    if (committed) {
      metrics.writes += 1;
      invalidateAll();
    }
    return committed;
  }

  @override
  Future<void> saveUsage(ChatMemoryUsage usage) => delegate.saveUsage(usage);
  @override
  Future<ChatMemoryUsage?> getUsage(String sessionId, String messageId) =>
      delegate.getUsage(sessionId, messageId);
  final RepositoryCacheMetrics metrics = RepositoryCacheMetrics();
  final Map<(String, bool), List<ChatMemoryEntry>> _entries = {};
  final Map<(String, bool), List<ChatMemoryEntry>> _sessionEntries = {};
  final Map<String, List<ConversationSummary>> _summaries = {};

  @override
  void invalidateAll() {
    _entries.clear();
    _sessionEntries.clear();
    _summaries.clear();
  }

  @override
  Future<List<ChatMemoryEntry>> listEntries(
    String personaId, {
    bool includeDeleted = false,
  }) async {
    final key = (personaId, includeDeleted);
    final cached = _entries[key];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    return _entries[key] = await delegate.listEntries(
      personaId,
      includeDeleted: includeDeleted,
    );
  }

  @override
  Future<ChatMemoryEntry> getEntry(String id) async {
    for (final list in [..._entries.values, ..._sessionEntries.values]) {
      for (final item in list) {
        if (item.id == id) return item;
      }
    }
    return delegate.getEntry(id);
  }

  @override
  Future<List<ChatMemoryEntry>> listEntriesForSession(
    String sessionId, {
    bool includeDeleted = false,
  }) async {
    final key = (sessionId, includeDeleted);
    final cached = _sessionEntries[key];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    return _sessionEntries[key] = await delegate.listEntriesForSession(
      sessionId,
      includeDeleted: includeDeleted,
    );
  }

  @override
  Future<void> upsertEntry(ChatMemoryEntry entry) async {
    await delegate.upsertEntry(entry);
    metrics.writes += 1;
    _storeEntry(entry);
  }

  @override
  Future<void> softDeleteEntry(String id, DateTime deletedAt) async {
    final current = await getEntry(id);
    await delegate.softDeleteEntry(id, deletedAt);
    final at = deletedAt.toUtc();
    _storeEntry(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: at,
          revision: current.revision + 1,
          deletedAt: at,
        ),
      ),
    );
  }

  @override
  Future<void> restoreEntry(String id, DateTime updatedAt) async {
    final current = await getEntry(id);
    await delegate.restoreEntry(id, updatedAt);
    final at = updatedAt.toUtc();
    _storeEntry(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: at,
          revision: current.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }

  @override
  Future<List<ConversationSummary>> listSummaries(String sessionId) async =>
      _summaries[sessionId] ??= await delegate.listSummaries(sessionId);

  @override
  Future<void> upsertSummary(ConversationSummary summary) async {
    await delegate.upsertSummary(summary);
    metrics.writes += 1;
    final list = [...?_summaries[summary.sessionId]]
      ..removeWhere((item) => item.id == summary.id)
      ..add(summary)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _summaries[summary.sessionId] = List.unmodifiable(list);
  }

  void _storeEntry(ChatMemoryEntry entry) {
    for (final key
        in _entries.keys
            .where((key) => key.$1 == entry.personaId)
            .toList(growable: false)) {
      final list = [..._entries[key]!]
        ..removeWhere((item) => item.id == entry.id);
      if (key.$2 || entry.deletedAt == null) list.add(entry);
      list.sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      _entries[key] = List.unmodifiable(list);
    }
    final sessionId = entry.sessionId;
    if (sessionId != null) {
      for (final key
          in _sessionEntries.keys
              .where((key) => key.$1 == sessionId)
              .toList(growable: false)) {
        final list = [..._sessionEntries[key]!]
          ..removeWhere((item) => item.id == entry.id);
        if (key.$2 || entry.deletedAt == null) list.add(entry);
        list.sort((a, b) {
          if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
          return b.updatedAt.compareTo(a.updatedAt);
        });
        _sessionEntries[key] = List.unmodifiable(list);
      }
    }
  }
}
