import '../../data/repositories/chat_persona_repository.dart';

class SoftDeleteChatPersona {
  const SoftDeleteChatPersona(this._personas);

  final ChatPersonaRepository _personas;

  Future<void> call({required String personaId, required DateTime nowUtc}) {
    return _personas.softDeletePersona(personaId, nowUtc.toUtc());
  }
}
