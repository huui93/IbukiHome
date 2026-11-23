import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/chat_repository.dart';
import '../repositories/latest_chat_mutation.dart';
import '../../domain/chat/chat_image.dart';
import '../../domain/chat/chat_message.dart';
import '../../domain/chat/chat_session.dart';
import 'in_memory_ibuki_store.dart';

class InMemoryChatRepository implements ChatRepository {
  InMemoryChatRepository(this.store);

  final InMemoryIbukiStore store;

  @override
  Future<List<ChatSession>> listSessions({
    String? projectId,
    String? characterId,
    String? personaId,
    bool includeDeleted = false,
  }) async {
    final items = store.chatSessions.where((session) {
      final projectMatches =
          projectId == null || session.projectId == projectId;
      final characterMatches =
          characterId == null || session.characterId == characterId;
      final personaMatches =
          personaId == null || session.personaId == personaId;
      return projectMatches &&
          characterMatches &&
          personaMatches &&
          (includeDeleted || session.deletedAt == null);
    }).toList()..sort(_compareActiveSessions);
    return List.unmodifiable(items);
  }

  @override
  Future<ChatSession> getSession(String id) async {
    final session = store.chatSession(id);
    if (session == null) {
      throw EntityNotFoundException('ChatSession', id);
    }
    return session;
  }

  @override
  Future<void> upsertSession(ChatSession session) async {
    if (session.projectId != null || session.characterId != null) {
      throw const DataConflictException('聊天会话不能关联小说资料。');
    }
    if (session.personaId != null) {
      _requirePersona(session.personaId!);
    }
    final existing = store.chatSession(session.id);
    if (existing != null && existing.projectId != session.projectId) {
      throw DataConflictException(
        'ChatSession ${session.id} cannot move between projects.',
      );
    }
    if (existing != null && existing.characterId != session.characterId) {
      throw DataConflictException(
        'ChatSession ${session.id} cannot change its character binding.',
      );
    }
    if (existing != null && existing.personaId != session.personaId) {
      throw DataConflictException(
        'ChatSession ${session.id} cannot change its persona binding.',
      );
    }
    store.putChatSession(session);
  }

  @override
  Future<void> softDeleteSession(String id, DateTime deletedAt) async {
    final session = await getSession(id);
    if (session.deletedAt != null) {
      return;
    }
    final deletedUtc = deletedAt.toUtc();
    store.putChatSession(
      session.copyWith(
        metadata: session.metadata.copyWith(
          updatedAt: deletedUtc,
          revision: session.revision + 1,
          deletedAt: deletedUtc,
        ),
      ),
    );
  }

  @override
  Future<void> restoreSession(String id, DateTime updatedAt) async {
    final session = await getSession(id);
    if (session.deletedAt == null) {
      return;
    }
    final updatedUtc = updatedAt.toUtc();
    store.putChatSession(
      session.copyWith(
        metadata: session.metadata.copyWith(
          updatedAt: updatedUtc,
          revision: session.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }

  @override
  Future<List<ChatMessage>> listMessages(
    String sessionId, {
    bool includeDeleted = false,
    bool includeImageData = true,
  }) async {
    final items =
        store.chatMessages.where((message) {
          return message.sessionId == sessionId &&
              (includeDeleted || message.deletedAt == null);
        }).toList()..sort((left, right) {
          final time = left.createdAt.compareTo(right.createdAt);
          return time != 0 ? time : left.id.compareTo(right.id);
        });
    return List.unmodifiable(
      includeImageData ? items : items.map((item) => item.withoutImage()),
    );
  }

  @override
  Future<ChatMessage> getMessage(String id) async {
    final message = store.chatMessage(id);
    if (message == null) throw EntityNotFoundException('ChatMessage', id);
    return message;
  }

  @override
  Future<ChatImage?> getMessageImage(String id) async =>
      (await getMessage(id)).image;

  @override
  Future<void> appendMessage(ChatMessage message) async {
    if (store.hasChatMessage(message.id)) {
      throw DuplicateEntityException('ChatMessage', message.id);
    }
    final session = store.chatSession(message.sessionId);
    if (session == null) {
      throw EntityNotFoundException('ChatSession', message.sessionId);
    }
    if (session.deletedAt != null) {
      throw DataConflictException(
        'ChatSession ${session.id} is deleted and cannot receive messages.',
      );
    }
    if (message.projectId != null) {
      throw const DataConflictException('聊天消息不能关联小说资料。');
    }
    if (session.projectId != null && session.projectId != message.projectId) {
      throw DataConflictException(
        'ChatMessage ${message.id} project does not match session.',
      );
    }
    store.putChatMessage(message);
  }

  @override
  Future<void> upsertMessage(ChatMessage message) async {
    if (message.projectId != null) {
      throw const DataConflictException('聊天消息不能关联小说资料。');
    }
    final current = store.chatMessage(message.id);
    if (current == null) {
      throw EntityNotFoundException('ChatMessage', message.id);
    }
    if (current.sessionId != message.sessionId) {
      throw DataConflictException(
        'ChatMessage ${message.id} cannot move sessions.',
      );
    }
    store.putChatMessage(message);
  }

  @override
  Future<ChatSession> appendMessageAndTouchSession(
    ChatMessage message,
    DateTime updatedAt,
  ) async {
    if (store.hasChatMessage(message.id)) {
      throw DuplicateEntityException('ChatMessage', message.id);
    }
    final session = store.chatSession(message.sessionId);
    if (session == null) {
      throw EntityNotFoundException('ChatSession', message.sessionId);
    }
    if (session.deletedAt != null) {
      throw DataConflictException(
        'ChatSession ${session.id} is deleted and cannot receive messages.',
      );
    }
    if (message.projectId != null) {
      throw const DataConflictException('聊天消息不能关联小说资料。');
    }
    if (session.projectId != message.projectId) {
      throw DataConflictException(
        'ChatMessage ${message.id} project does not match session.',
      );
    }
    final updatedUtc = updatedAt.toUtc();
    final touched = session.copyWith(
      metadata: session.metadata.copyWith(
        updatedAt: updatedUtc,
        revision: session.revision + 1,
      ),
    );
    store.putChatMessage(message);
    store.putChatSession(touched);
    return touched;
  }

  @override
  Future<void> softDeleteMessage(String id, DateTime deletedAt) async {
    final message = store.chatMessage(id);
    if (message == null) {
      throw EntityNotFoundException('ChatMessage', id);
    }
    final deletedUtc = deletedAt.toUtc();
    store.putChatMessage(
      message.copyWith(
        metadata: message.metadata.copyWith(
          updatedAt: deletedUtc,
          revision: message.revision + 1,
          deletedAt: deletedUtc,
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
    final session = store.chatSession(expected.sessionId);
    if (session == null ||
        session.deletedAt != null ||
        (expectedPersonaId != null && session.personaId != expectedPersonaId)) {
      throw const DataConflictException('会话不存在、已删除或人格已经变化。');
    }
    if (expectedPersonaId != null) _requirePersona(expectedPersonaId);
    final messages =
        store.chatMessages
            .where(
              (m) => m.sessionId == expected.sessionId && m.deletedAt == null,
            )
            .toList()
          ..sort((a, b) {
            final time = a.createdAt.compareTo(b.createdAt);
            return time == 0 ? a.id.compareTo(b.id) : time;
          });
    if (messages.isEmpty) throw const DataConflictException('会话已经没有消息。');
    final updated = prepareLatestChatMutation(
      expected: expected,
      latest: messages.last,
      nowUtc: nowUtc,
      replacement: replacement,
      append: append,
    );
    if (append && store.hasChatMessage(updated.id)) {
      throw DuplicateEntityException('ChatMessage', updated.id);
    }
    store.putChatMessage(updated);
    store.putChatSession(
      session.copyWith(
        metadata: session.metadata.copyWith(
          updatedAt: updated.updatedAt,
          revision: session.revision + 1,
        ),
      ),
    );
    return updated;
  }

  void _requirePersona(String personaId) {
    final persona = store.chatPersona(personaId);
    if (persona == null) {
      throw EntityNotFoundException('ChatPersona', personaId);
    }
    if (persona.deletedAt != null) {
      throw DataConflictException('ChatPersona $personaId is deleted.');
    }
  }

  int _compareActiveSessions(ChatSession left, ChatSession right) {
    final time = right.updatedAt.compareTo(left.updatedAt);
    if (time != 0) {
      return time;
    }
    final title = left.title.compareTo(right.title);
    return title != 0 ? title : left.id.compareTo(right.id);
  }
}
