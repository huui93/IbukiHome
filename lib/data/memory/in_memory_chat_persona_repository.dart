import '../../core/errors/data_exceptions.dart';
import '../../domain/chat/chat_persona.dart';
import '../repositories/chat_persona_repository.dart';
import 'in_memory_ibuki_store.dart';

class InMemoryChatPersonaRepository implements ChatPersonaRepository {
  InMemoryChatPersonaRepository(this.store);

  final InMemoryIbukiStore store;

  @override
  Future<List<ChatPersona>> listPersonas({bool includeDeleted = false}) async {
    final items =
        store.chatPersonas
            .where((item) => includeDeleted || item.deletedAt == null)
            .toList()
          ..sort((left, right) {
            final name = left.name.compareTo(right.name);
            return name != 0 ? name : left.id.compareTo(right.id);
          });
    return List.unmodifiable(items);
  }

  @override
  Future<ChatPersona> getPersona(String id) async {
    final persona = store.chatPersona(id);
    if (persona == null) {
      throw EntityNotFoundException('ChatPersona', id);
    }
    return persona;
  }

  @override
  Future<void> upsertPersona(ChatPersona persona) async {
    store.putChatPersona(persona);
  }

  @override
  Future<void> softDeletePersona(String id, DateTime deletedAt) async {
    final persona = await getPersona(id);
    if (persona.deletedAt != null) {
      return;
    }
    final now = deletedAt.toUtc();
    store.putChatPersona(
      persona.copyWith(
        metadata: persona.metadata.copyWith(
          updatedAt: now,
          revision: persona.revision + 1,
          deletedAt: now,
        ),
      ),
    );
  }

  @override
  Future<void> restorePersona(String id, DateTime updatedAt) async {
    final persona = await getPersona(id);
    if (persona.deletedAt == null) {
      return;
    }
    final now = updatedAt.toUtc();
    store.putChatPersona(
      persona.copyWith(
        metadata: persona.metadata.copyWith(
          updatedAt: now,
          revision: persona.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }
}
