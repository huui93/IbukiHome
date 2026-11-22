import '../../data/repositories/chat_persona_repository.dart';
import '../../data/repositories/chat_repository.dart';
import '../../domain/chat/chat_message.dart';
import '../../domain/chat/chat_persona.dart';
import '../../domain/chat/chat_session.dart';
import 'plugin_permissions.dart';

class PluginChatSessionView {
  const PluginChatSessionView({
    required this.id,
    required this.title,
    required this.projectId,
    required this.personaId,
  });

  final String id;
  final String title;
  final String? projectId;
  final String? personaId;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'projectId': projectId,
    'personaId': personaId,
  };

  factory PluginChatSessionView.fromDomain(ChatSession session) {
    return PluginChatSessionView(
      id: session.id,
      title: session.title,
      projectId: session.projectId,
      personaId: session.personaId,
    );
  }
}

class PluginChatMessageView {
  const PluginChatMessageView({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String role;
  final String content;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory PluginChatMessageView.fromDomain(ChatMessage message) {
    return PluginChatMessageView(
      id: message.id,
      role: message.role.jsonValue,
      content: message.content,
      createdAt: message.createdAt,
    );
  }
}

class PluginCharacterView {
  const PluginCharacterView({
    required this.id,
    required this.name,
    required this.shortDescription,
  });

  final String id;
  final String name;
  final String shortDescription;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'shortDescription': shortDescription,
  };

  factory PluginCharacterView.fromDomain(ChatPersona persona) {
    return PluginCharacterView(
      id: persona.id,
      name: persona.name,
      shortDescription: persona.shortDescription,
    );
  }
}

abstract class IbukiChatApi {
  Future<PluginChatSessionView?> getCurrentSession();

  Future<List<PluginChatMessageView>> getMessages();

  Future<List<PluginChatMessageView>> getRecentMessages({int limit = 30});

  Future<PluginCharacterView?> getCurrentPersona();

  Future<PluginCharacterView?> getSafeCharacterContext();
}

class CoreIbukiChatApi implements IbukiChatApi {
  CoreIbukiChatApi({
    required this.sessionId,
    required this.permissions,
    required this.chats,
    required this.personas,
  });

  final String? sessionId;
  final PluginPermissionGuard permissions;
  final ChatRepository chats;
  final ChatPersonaRepository personas;

  @override
  Future<PluginChatSessionView?> getCurrentSession() async {
    permissions.require(PluginPermissions.chatRead);
    final id = sessionId;
    if (id == null) return null;
    return PluginChatSessionView.fromDomain(await chats.getSession(id));
  }

  @override
  Future<List<PluginChatMessageView>> getMessages() async {
    permissions.require(PluginPermissions.chatRead);
    final id = sessionId;
    if (id == null) return const [];
    final messages = await chats.listMessages(id);
    return List.unmodifiable(messages.map(PluginChatMessageView.fromDomain));
  }

  @override
  Future<List<PluginChatMessageView>> getRecentMessages({
    int limit = 30,
  }) async {
    if (limit < 1 || limit > 200) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 200');
    }
    final messages = await getMessages();
    final start = messages.length > limit ? messages.length - limit : 0;
    return List.unmodifiable(messages.sublist(start));
  }

  @override
  Future<PluginCharacterView?> getCurrentPersona() async {
    permissions.require(PluginPermissions.characterRead);
    final id = sessionId;
    if (id == null) return null;
    final session = await chats.getSession(id);
    final personaId = session.personaId;
    if (personaId == null) return null;
    return PluginCharacterView.fromDomain(await personas.getPersona(personaId));
  }

  @override
  Future<PluginCharacterView?> getSafeCharacterContext() {
    return getCurrentPersona();
  }
}
