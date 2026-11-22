import '../../domain/chat/chat_persona.dart';

abstract class ChatPersonaRepository {
  Future<List<ChatPersona>> listPersonas({bool includeDeleted = false});

  Future<ChatPersona> getPersona(String id);

  Future<void> upsertPersona(ChatPersona persona);

  Future<void> softDeletePersona(String id, DateTime deletedAt);

  Future<void> restorePersona(String id, DateTime updatedAt);
}
