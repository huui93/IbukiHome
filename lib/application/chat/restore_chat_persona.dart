import '../../data/repositories/chat_persona_repository.dart';

class RestoreChatPersona {
  const RestoreChatPersona(this._personas);

  final ChatPersonaRepository _personas;

  Future<void> call({required String personaId, required DateTime nowUtc}) {
    return _personas.restorePersona(personaId, nowUtc.toUtc());
  }
}
