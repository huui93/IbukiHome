import '../../domain/characters/character_card.dart';
import '../../domain/chat/chat_message.dart';
import '../../domain/chat/chat_persona.dart';
import '../../domain/chat/chat_session.dart';
import '../../domain/projects/project.dart';
import '../../domain/segments/segment.dart';
import '../../domain/segments/segment_revision.dart';
import '../../domain/world/world_card.dart';
import '../repositories/character_repository.dart';
import '../repositories/committed_entity_cache.dart';
import '../repositories/invalidatable_read_cache.dart';
import '../repositories/chat_persona_repository.dart';
import '../repositories/chat_repository.dart';
import '../repositories/project_repository.dart';
import '../repositories/segment_repository.dart';
import '../repositories/world_repository.dart';
import 'repository_cache_metrics.dart';

/// Process-lifetime read-through caches for local data.
///
/// Widgets remain lazy, while domain snapshots survive tab switches and are
/// updated after successful writes. No timer-based eviction is used.
class CachedProjectRepository
    implements
        ProjectRepository,
        CommittedEntityCache<Project>,
        InvalidatableReadCache {
  CachedProjectRepository(this.delegate);

  final ProjectRepository delegate;
  final metrics = RepositoryCacheMetrics();
  final Map<String, Project> _entities = {};
  final Map<bool, List<Project>> _lists = {};

  int get retainedEntryCount => _entities.length;

  @override
  void invalidateAll() {
    _entities.clear();
    _lists.clear();
  }

  @override
  void acceptCommittedEntity(Project entity) => _store(entity);

  @override
  Future<List<Project>> listProjects({bool includeDeleted = false}) async {
    final cached = _lists[includeDeleted];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final items = await delegate.listProjects(includeDeleted: includeDeleted);
    _entities.addEntries(items.map((item) => MapEntry(item.id, item)));
    return _lists[includeDeleted] = List.unmodifiable(items);
  }

  @override
  Future<Project> getProject(String id) async {
    final cached = _entities[id];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final item = await delegate.getProject(id);
    _entities[id] = item;
    return item;
  }

  @override
  Future<void> upsertProject(Project project) async {
    await delegate.upsertProject(project);
    metrics.writes += 1;
    _store(project);
  }

  @override
  Future<void> softDeleteProject(String id, DateTime deletedAt) async {
    final current = await getProject(id);
    await delegate.softDeleteProject(id, deletedAt);
    metrics.writes += 1;
    _store(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: deletedAt.toUtc(),
          revision: current.revision + 1,
          deletedAt: deletedAt.toUtc(),
        ),
      ),
    );
  }

  @override
  Future<void> restoreProject(String id, DateTime updatedAt) async {
    final current = await getProject(id);
    await delegate.restoreProject(id, updatedAt);
    metrics.writes += 1;
    _store(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: updatedAt.toUtc(),
          revision: current.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }

  void _store(Project project) {
    _entities[project.id] = project;
    for (final entry in _lists.entries) {
      final items = [...entry.value]
        ..removeWhere((item) => item.id == project.id);
      if (entry.key || project.deletedAt == null) items.add(project);
      items.sort(_compareProjects);
      _lists[entry.key] = List.unmodifiable(items);
    }
  }
}

class CachedSegmentRepository
    implements SegmentRepository, InvalidatableReadCache {
  CachedSegmentRepository(this.delegate);

  final SegmentRepository delegate;
  final metrics = RepositoryCacheMetrics();
  final Map<String, Segment> _segments = {};
  final Map<({String projectId, bool includeDeleted}), List<Segment>> _lists =
      {};
  final Map<String, SegmentRevision> _revisions = {};
  final Map<String, List<SegmentRevision>> _revisionLists = {};

  int get retainedEntryCount => _segments.length + _revisions.length;

  @override
  void invalidateAll() {
    _segments.clear();
    _lists.clear();
    _revisions.clear();
    _revisionLists.clear();
  }

  @override
  Future<List<Segment>> listSegments(
    String projectId, {
    bool includeDeleted = false,
  }) async {
    final key = (projectId: projectId, includeDeleted: includeDeleted);
    final cached = _lists[key];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final items = await delegate.listSegments(
      projectId,
      includeDeleted: includeDeleted,
    );
    _segments.addEntries(items.map((item) => MapEntry(item.id, item)));
    return _lists[key] = List.unmodifiable(items);
  }

  @override
  Future<Segment> getSegment(String id) async {
    final cached = _segments[id];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final item = await delegate.getSegment(id);
    _segments[id] = item;
    return item;
  }

  @override
  Future<void> upsertSegment(Segment segment) async {
    await delegate.upsertSegment(segment);
    metrics.writes += 1;
    _store(segment);
  }

  @override
  Future<void> softDeleteSegment(String id, DateTime deletedAt) async {
    final current = await getSegment(id);
    await delegate.softDeleteSegment(id, deletedAt);
    metrics.writes += 1;
    _store(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: deletedAt.toUtc(),
          revision: current.revision + 1,
          deletedAt: deletedAt.toUtc(),
        ),
      ),
    );
  }

  @override
  Future<void> restoreSegment(String id, DateTime updatedAt) async {
    final current = await getSegment(id);
    await delegate.restoreSegment(id, updatedAt);
    metrics.writes += 1;
    _store(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: updatedAt.toUtc(),
          revision: current.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }

  @override
  Future<List<SegmentRevision>> listRevisions(String segmentId) async {
    final cached = _revisionLists[segmentId];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final items = await delegate.listRevisions(segmentId);
    _revisions.addEntries(items.map((item) => MapEntry(item.id, item)));
    return _revisionLists[segmentId] = List.unmodifiable(items);
  }

  @override
  Future<SegmentRevision> getRevision(String id) async {
    final cached = _revisions[id];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final item = await delegate.getRevision(id);
    _revisions[id] = item;
    return item;
  }

  @override
  Future<void> appendRevision(SegmentRevision revision) async {
    await delegate.appendRevision(revision);
    metrics.writes += 1;
    _storeRevision(revision);
  }

  @override
  Future<Segment> insertSegmentAt({
    required Segment segment,
    required String anchorSegmentId,
    required SegmentInsertPosition position,
  }) async {
    final inserted = await delegate.insertSegmentAt(
      segment: segment,
      anchorSegmentId: anchorSegmentId,
      position: position,
    );
    metrics.writes += 1;
    final updatedAt = inserted.updatedAt;
    for (final item in _segments.values.toList()) {
      if (item.projectId == inserted.projectId &&
          item.deletedAt == null &&
          item.id != inserted.id &&
          item.orderIndex >= inserted.orderIndex) {
        _segments[item.id] = item.copyWith(
          orderIndex: item.orderIndex + 1,
          metadata: item.metadata.copyWith(
            updatedAt: updatedAt,
            revision: item.revision + 1,
          ),
        );
      }
    }
    _segments[inserted.id] = inserted;
    _refreshProjectLists(inserted.projectId, add: inserted);
    return inserted;
  }

  @override
  Future<void> reorderSegments({
    required String projectId,
    required List<String> orderedIds,
    required DateTime updatedAt,
  }) async {
    await delegate.reorderSegments(
      projectId: projectId,
      orderedIds: orderedIds,
      updatedAt: updatedAt,
    );
    metrics.writes += 1;
    final orderById = {
      for (var index = 0; index < orderedIds.length; index += 1)
        orderedIds[index]: index,
    };
    for (final item in _segments.values.toList()) {
      final order = orderById[item.id];
      if (item.projectId == projectId &&
          item.deletedAt == null &&
          order != null &&
          order != item.orderIndex) {
        _segments[item.id] = item.copyWith(
          orderIndex: order,
          metadata: item.metadata.copyWith(
            updatedAt: updatedAt.toUtc(),
            revision: item.revision + 1,
          ),
        );
      }
    }
    _refreshProjectLists(projectId);
  }

  @override
  Future<Segment> softDeleteAndReorder({
    required String projectId,
    required String segmentId,
    required DateTime deletedAt,
  }) async {
    final deleted = await delegate.softDeleteAndReorder(
      projectId: projectId,
      segmentId: segmentId,
      deletedAt: deletedAt,
    );
    metrics.writes += 1;
    for (final item in _segments.values.toList()) {
      if (item.projectId == projectId &&
          item.deletedAt == null &&
          item.id != deleted.id &&
          item.orderIndex > deleted.orderIndex) {
        _segments[item.id] = item.copyWith(
          orderIndex: item.orderIndex - 1,
          metadata: item.metadata.copyWith(
            updatedAt: deletedAt.toUtc(),
            revision: item.revision + 1,
          ),
        );
      }
    }
    _segments[deleted.id] = deleted;
    _refreshProjectLists(projectId, add: deleted);
    return deleted;
  }

  @override
  Future<Segment> restoreAndReorder({
    required String projectId,
    required String segmentId,
    required DateTime restoredAt,
  }) async {
    final restored = await delegate.restoreAndReorder(
      projectId: projectId,
      segmentId: segmentId,
      restoredAt: restoredAt,
    );
    metrics.writes += 1;
    for (final item in _segments.values.toList()) {
      if (item.projectId == projectId &&
          item.deletedAt == null &&
          item.id != restored.id &&
          item.orderIndex >= restored.orderIndex) {
        _segments[item.id] = item.copyWith(
          orderIndex: item.orderIndex + 1,
          metadata: item.metadata.copyWith(
            updatedAt: restoredAt.toUtc(),
            revision: item.revision + 1,
          ),
        );
      }
    }
    _segments[restored.id] = restored;
    _refreshProjectLists(projectId, add: restored);
    return restored;
  }

  @override
  Future<void> saveSegmentWithRevision({
    required Segment updatedSegment,
    required SegmentRevision revision,
  }) async {
    await delegate.saveSegmentWithRevision(
      updatedSegment: updatedSegment,
      revision: revision,
    );
    metrics.writes += 1;
    _store(updatedSegment);
    _storeRevision(revision);
  }

  void _store(Segment segment) {
    _segments[segment.id] = segment;
    _refreshProjectLists(segment.projectId, add: segment);
  }

  void _storeRevision(SegmentRevision revision) {
    _revisions[revision.id] = revision;
    final cached = _revisionLists[revision.segmentId];
    if (cached == null) return;
    final items = [...cached]
      ..removeWhere((item) => item.id == revision.id)
      ..add(revision)
      ..sort(_compareRevisions);
    _revisionLists[revision.segmentId] = List.unmodifiable(items);
  }

  void _refreshProjectLists(String projectId, {Segment? add}) {
    for (final key
        in _lists.keys.where((key) => key.projectId == projectId).toList()) {
      final ids = _lists[key]!.map((item) => item.id).toSet();
      if (add != null) ids.add(add.id);
      final items =
          ids
              .map((id) => _segments[id])
              .whereType<Segment>()
              .where((item) => key.includeDeleted || item.deletedAt == null)
              .toList()
            ..sort(_compareSegments);
      _lists[key] = List.unmodifiable(items);
    }
  }
}

class CachedCharacterRepository
    implements
        CharacterRepository,
        CommittedEntityCache<CharacterCard>,
        InvalidatableReadCache {
  CachedCharacterRepository(this.delegate);

  @override
  void acceptCommittedEntity(CharacterCard entity) => _store(entity);

  final CharacterRepository delegate;
  final metrics = RepositoryCacheMetrics();
  final Map<String, CharacterCard> _entities = {};
  final Map<({String projectId, bool includeDeleted}), List<CharacterCard>>
  _lists = {};

  int get retainedEntryCount => _entities.length;

  @override
  void invalidateAll() {
    _entities.clear();
    _lists.clear();
  }

  @override
  Future<List<CharacterCard>> listCharacters(
    String projectId, {
    bool includeDeleted = false,
  }) async {
    final key = (projectId: projectId, includeDeleted: includeDeleted);
    final cached = _lists[key];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final items = await delegate.listCharacters(
      projectId,
      includeDeleted: includeDeleted,
    );
    _entities.addEntries(items.map((item) => MapEntry(item.id, item)));
    return _lists[key] = List.unmodifiable(items);
  }

  @override
  Future<CharacterCard> getCharacter(String id) async {
    final cached = _entities[id];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final item = await delegate.getCharacter(id);
    _entities[id] = item;
    return item;
  }

  @override
  Future<void> upsertCharacter(CharacterCard character) async {
    await delegate.upsertCharacter(character);
    metrics.writes += 1;
    _store(character);
  }

  @override
  Future<void> softDeleteCharacter(String id, DateTime deletedAt) async {
    final current = await getCharacter(id);
    await delegate.softDeleteCharacter(id, deletedAt);
    metrics.writes += 1;
    _store(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: deletedAt.toUtc(),
          revision: current.revision + 1,
          deletedAt: deletedAt.toUtc(),
        ),
      ),
    );
  }

  @override
  Future<void> restoreCharacter(String id, DateTime updatedAt) async {
    final current = await getCharacter(id);
    await delegate.restoreCharacter(id, updatedAt);
    metrics.writes += 1;
    _store(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: updatedAt.toUtc(),
          revision: current.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }

  @override
  Future<void> reorderCharacters({
    required String projectId,
    required List<String> orderedIds,
    required DateTime updatedAt,
  }) async {
    await delegate.reorderCharacters(
      projectId: projectId,
      orderedIds: orderedIds,
      updatedAt: updatedAt,
    );
    metrics.writes += 1;
    final order = {
      for (var i = 0; i < orderedIds.length; i += 1) orderedIds[i]: i,
    };
    for (final item in _entities.values.toList()) {
      final next = order[item.id];
      if (item.projectId == projectId &&
          item.deletedAt == null &&
          next != null &&
          next != item.sortOrder) {
        _entities[item.id] = item.copyWith(
          sortOrder: next,
          metadata: item.metadata.copyWith(
            updatedAt: updatedAt.toUtc(),
            revision: item.revision + 1,
          ),
        );
      }
    }
    _refresh(projectId);
  }

  void _store(CharacterCard item) {
    _entities[item.id] = item;
    _refresh(item.projectId, add: item);
  }

  void _refresh(String projectId, {CharacterCard? add}) {
    for (final key
        in _lists.keys.where((key) => key.projectId == projectId).toList()) {
      final ids = _lists[key]!.map((item) => item.id).toSet();
      if (add != null) ids.add(add.id);
      final items =
          ids
              .map((id) => _entities[id])
              .whereType<CharacterCard>()
              .where((item) => key.includeDeleted || item.deletedAt == null)
              .toList()
            ..sort(_compareCharacters);
      _lists[key] = List.unmodifiable(items);
    }
  }
}

class CachedWorldRepository implements WorldRepository, InvalidatableReadCache {
  CachedWorldRepository(this.delegate);

  final WorldRepository delegate;
  final metrics = RepositoryCacheMetrics();
  final Map<String, WorldCard> _entities = {};
  final Map<({String projectId, bool includeDeleted}), List<WorldCard>> _lists =
      {};

  int get retainedEntryCount => _entities.length;

  @override
  void invalidateAll() {
    _entities.clear();
    _lists.clear();
  }

  @override
  Future<List<WorldCard>> listWorldCards(
    String projectId, {
    bool includeDeleted = false,
  }) async {
    final key = (projectId: projectId, includeDeleted: includeDeleted);
    final cached = _lists[key];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final items = await delegate.listWorldCards(
      projectId,
      includeDeleted: includeDeleted,
    );
    _entities.addEntries(items.map((item) => MapEntry(item.id, item)));
    return _lists[key] = List.unmodifiable(items);
  }

  @override
  Future<WorldCard> getWorldCard(String id) async {
    final cached = _entities[id];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final item = await delegate.getWorldCard(id);
    _entities[id] = item;
    return item;
  }

  @override
  Future<void> upsertWorldCard(WorldCard card) async {
    await delegate.upsertWorldCard(card);
    metrics.writes += 1;
    _store(card);
  }

  @override
  Future<void> softDeleteWorldCard(String id, DateTime deletedAt) async {
    final current = await getWorldCard(id);
    await delegate.softDeleteWorldCard(id, deletedAt);
    metrics.writes += 1;
    _store(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: deletedAt.toUtc(),
          revision: current.revision + 1,
          deletedAt: deletedAt.toUtc(),
        ),
      ),
    );
  }

  @override
  Future<void> restoreWorldCard(String id, DateTime updatedAt) async {
    final current = await getWorldCard(id);
    await delegate.restoreWorldCard(id, updatedAt);
    metrics.writes += 1;
    _store(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: updatedAt.toUtc(),
          revision: current.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }

  @override
  Future<void> reorderWorldCards({
    required String projectId,
    required List<String> orderedIds,
    required DateTime updatedAt,
  }) async {
    await delegate.reorderWorldCards(
      projectId: projectId,
      orderedIds: orderedIds,
      updatedAt: updatedAt,
    );
    metrics.writes += 1;
    final order = {
      for (var i = 0; i < orderedIds.length; i += 1) orderedIds[i]: i,
    };
    for (final item in _entities.values.toList()) {
      final next = order[item.id];
      if (item.projectId == projectId &&
          item.deletedAt == null &&
          next != null &&
          next != item.sortOrder) {
        _entities[item.id] = item.copyWith(
          sortOrder: next,
          metadata: item.metadata.copyWith(
            updatedAt: updatedAt.toUtc(),
            revision: item.revision + 1,
          ),
        );
      }
    }
    _refresh(projectId);
  }

  void _store(WorldCard item) {
    _entities[item.id] = item;
    _refresh(item.projectId, add: item);
  }

  void _refresh(String projectId, {WorldCard? add}) {
    for (final key
        in _lists.keys.where((key) => key.projectId == projectId).toList()) {
      final ids = _lists[key]!.map((item) => item.id).toSet();
      if (add != null) ids.add(add.id);
      final items =
          ids
              .map((id) => _entities[id])
              .whereType<WorldCard>()
              .where((item) => key.includeDeleted || item.deletedAt == null)
              .toList()
            ..sort(_compareWorldCards);
      _lists[key] = List.unmodifiable(items);
    }
  }
}

typedef _SessionQuery = ({
  String? projectId,
  String? characterId,
  String? personaId,
  bool includeDeleted,
});

class CachedChatRepository implements ChatRepository, InvalidatableReadCache {
  CachedChatRepository(this.delegate);

  final ChatRepository delegate;
  final metrics = RepositoryCacheMetrics();
  final Map<String, ChatSession> _sessions = {};
  final Map<_SessionQuery, List<ChatSession>> _sessionLists = {};
  final Map<String, ChatMessage> _messages = {};
  final Map<({String sessionId, bool includeDeleted}), List<ChatMessage>>
  _messageLists = {};

  int get retainedEntryCount => _sessions.length + _messages.length;

  @override
  void invalidateAll() {
    _sessions.clear();
    _sessionLists.clear();
    _messages.clear();
    _messageLists.clear();
  }

  @override
  Future<List<ChatSession>> listSessions({
    String? projectId,
    String? characterId,
    String? personaId,
    bool includeDeleted = false,
  }) async {
    final key = (
      projectId: projectId,
      characterId: characterId,
      personaId: personaId,
      includeDeleted: includeDeleted,
    );
    final cached = _sessionLists[key];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final items = await delegate.listSessions(
      projectId: projectId,
      characterId: characterId,
      personaId: personaId,
      includeDeleted: includeDeleted,
    );
    _sessions.addEntries(items.map((item) => MapEntry(item.id, item)));
    return _sessionLists[key] = List.unmodifiable(items);
  }

  @override
  Future<ChatSession> getSession(String id) async {
    final cached = _sessions[id];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final item = await delegate.getSession(id);
    _sessions[id] = item;
    return item;
  }

  @override
  Future<void> upsertSession(ChatSession session) async {
    await delegate.upsertSession(session);
    metrics.writes += 1;
    _storeSession(session);
  }

  @override
  Future<void> softDeleteSession(String id, DateTime deletedAt) async {
    final current = await getSession(id);
    await delegate.softDeleteSession(id, deletedAt);
    if (current.deletedAt != null) return;
    metrics.writes += 1;
    _storeSession(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: deletedAt.toUtc(),
          revision: current.revision + 1,
          deletedAt: deletedAt.toUtc(),
        ),
      ),
    );
  }

  @override
  Future<void> restoreSession(String id, DateTime updatedAt) async {
    final current = await getSession(id);
    await delegate.restoreSession(id, updatedAt);
    if (current.deletedAt == null) return;
    metrics.writes += 1;
    _storeSession(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: updatedAt.toUtc(),
          revision: current.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }

  @override
  Future<List<ChatMessage>> listMessages(
    String sessionId, {
    bool includeDeleted = false,
  }) async {
    final key = (sessionId: sessionId, includeDeleted: includeDeleted);
    final cached = _messageLists[key];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final items = await delegate.listMessages(
      sessionId,
      includeDeleted: includeDeleted,
    );
    _messages.addEntries(items.map((item) => MapEntry(item.id, item)));
    return _messageLists[key] = List.unmodifiable(items);
  }

  @override
  Future<ChatMessage> getMessage(String id) async {
    metrics.delegateReads += 1;
    final persisted = await delegate.getMessage(id);
    _storeMessage(persisted);
    return persisted;
  }

  @override
  Future<void> appendMessage(ChatMessage message) async {
    await delegate.appendMessage(message);
    metrics.writes += 1;
    _storeMessage(message);
  }

  @override
  Future<void> upsertMessage(ChatMessage message) async {
    await delegate.upsertMessage(message);
    metrics.writes += 1;
    _storeMessage(message);
  }

  @override
  Future<ChatSession> appendMessageAndTouchSession(
    ChatMessage message,
    DateTime updatedAt,
  ) async {
    final touched = await delegate.appendMessageAndTouchSession(
      message,
      updatedAt,
    );
    metrics.writes += 1;
    _storeMessage(message);
    _storeSession(touched);
    return touched;
  }

  @override
  Future<void> softDeleteMessage(String id, DateTime deletedAt) async {
    await delegate.softDeleteMessage(id, deletedAt);
    metrics.writes += 1;
    final current = _messages[id];
    if (current == null) return;
    _storeMessage(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: deletedAt.toUtc(),
          revision: current.revision + 1,
          deletedAt: deletedAt.toUtc(),
        ),
      ),
    );
  }

  @override
  Future<ChatMessage> mutateLatestMessage({
    required ChatMessage expected,
    required DateTime nowUtc,
    ChatMessage? replacement,
    bool append = false,
    String? expectedPersonaId,
  }) async {
    final updated = await delegate.mutateLatestMessage(
      expected: expected,
      nowUtc: nowUtc,
      replacement: replacement,
      append: append,
      expectedPersonaId: expectedPersonaId,
    );
    metrics.writes += 1;
    _storeMessage(updated);
    _sessions.remove(expected.sessionId);
    _sessionLists.clear();
    return updated;
  }

  void _storeSession(ChatSession session) {
    _sessions[session.id] = session;
    for (final entry in _sessionLists.entries) {
      final items = [...entry.value]
        ..removeWhere((item) => item.id == session.id);
      if (_matchesSession(session, entry.key)) items.add(session);
      items.sort(_compareSessions);
      _sessionLists[entry.key] = List.unmodifiable(items);
    }
  }

  void _storeMessage(ChatMessage message) {
    _messages[message.id] = message;
    for (final key
        in _messageLists.keys
            .where((key) => key.sessionId == message.sessionId)
            .toList()) {
      final items = [..._messageLists[key]!]
        ..removeWhere((item) => item.id == message.id);
      if (key.includeDeleted || message.deletedAt == null) items.add(message);
      items.sort(_compareMessages);
      _messageLists[key] = List.unmodifiable(items);
    }
  }
}

class CachedChatPersonaRepository
    implements ChatPersonaRepository, InvalidatableReadCache {
  CachedChatPersonaRepository(this.delegate);

  final ChatPersonaRepository delegate;
  final metrics = RepositoryCacheMetrics();
  final Map<String, ChatPersona> _entities = {};
  final Map<bool, List<ChatPersona>> _lists = {};

  int get retainedEntryCount => _entities.length;

  @override
  void invalidateAll() {
    _entities.clear();
    _lists.clear();
  }

  @override
  Future<List<ChatPersona>> listPersonas({bool includeDeleted = false}) async {
    final cached = _lists[includeDeleted];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final items = await delegate.listPersonas(includeDeleted: includeDeleted);
    _entities.addEntries(items.map((item) => MapEntry(item.id, item)));
    return _lists[includeDeleted] = List.unmodifiable(items);
  }

  @override
  Future<ChatPersona> getPersona(String id) async {
    final cached = _entities[id];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final item = await delegate.getPersona(id);
    _entities[id] = item;
    return item;
  }

  @override
  Future<void> upsertPersona(ChatPersona persona) async {
    await delegate.upsertPersona(persona);
    metrics.writes += 1;
    _store(persona);
  }

  @override
  Future<void> softDeletePersona(String id, DateTime deletedAt) async {
    final current = await getPersona(id);
    await delegate.softDeletePersona(id, deletedAt);
    if (current.deletedAt != null) return;
    metrics.writes += 1;
    _store(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: deletedAt.toUtc(),
          revision: current.revision + 1,
          deletedAt: deletedAt.toUtc(),
        ),
      ),
    );
  }

  @override
  Future<void> restorePersona(String id, DateTime updatedAt) async {
    final current = await getPersona(id);
    await delegate.restorePersona(id, updatedAt);
    if (current.deletedAt == null) return;
    metrics.writes += 1;
    _store(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: updatedAt.toUtc(),
          revision: current.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }

  void _store(ChatPersona persona) {
    _entities[persona.id] = persona;
    for (final entry in _lists.entries) {
      final items = [...entry.value]
        ..removeWhere((item) => item.id == persona.id);
      if (entry.key || persona.deletedAt == null) items.add(persona);
      items.sort(_comparePersonas);
      _lists[entry.key] = List.unmodifiable(items);
    }
  }
}

bool _matchesSession(ChatSession session, _SessionQuery query) {
  return (query.includeDeleted || session.deletedAt == null) &&
      (query.projectId == null || session.projectId == query.projectId) &&
      (query.characterId == null || session.characterId == query.characterId) &&
      (query.personaId == null || session.personaId == query.personaId);
}

int _compareProjects(Project left, Project right) {
  final updated = right.updatedAt.compareTo(left.updatedAt);
  if (updated != 0) return updated;
  final title = left.title.compareTo(right.title);
  return title != 0 ? title : left.id.compareTo(right.id);
}

int _compareSegments(Segment left, Segment right) {
  final order = left.orderIndex.compareTo(right.orderIndex);
  if (order != 0) return order;
  final created = left.createdAt.compareTo(right.createdAt);
  return created != 0 ? created : left.id.compareTo(right.id);
}

int _compareRevisions(SegmentRevision left, SegmentRevision right) {
  final revision = left.revisionNumber.compareTo(right.revisionNumber);
  if (revision != 0) return revision;
  final created = left.createdAt.compareTo(right.createdAt);
  return created != 0 ? created : left.id.compareTo(right.id);
}

int _compareCharacters(CharacterCard left, CharacterCard right) {
  final order = left.sortOrder.compareTo(right.sortOrder);
  if (order != 0) return order;
  final updated = left.updatedAt.compareTo(right.updatedAt);
  return updated != 0 ? updated : left.id.compareTo(right.id);
}

int _compareWorldCards(WorldCard left, WorldCard right) {
  final order = left.sortOrder.compareTo(right.sortOrder);
  if (order != 0) return order;
  final updated = left.updatedAt.compareTo(right.updatedAt);
  return updated != 0 ? updated : left.id.compareTo(right.id);
}

int _compareSessions(ChatSession left, ChatSession right) {
  final updated = right.updatedAt.compareTo(left.updatedAt);
  if (updated != 0) return updated;
  final title = left.title.compareTo(right.title);
  return title != 0 ? title : left.id.compareTo(right.id);
}

int _compareMessages(ChatMessage left, ChatMessage right) {
  final created = left.createdAt.compareTo(right.createdAt);
  return created != 0 ? created : left.id.compareTo(right.id);
}

int _comparePersonas(ChatPersona left, ChatPersona right) {
  final name = left.name.compareTo(right.name);
  return name != 0 ? name : left.id.compareTo(right.id);
}
