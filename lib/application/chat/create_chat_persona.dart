import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/chat_persona_repository.dart';
import '../../domain/chat/chat_persona.dart';
import '../../domain/chat/chat_preset_message.dart';
import '../../domain/common/entity_metadata.dart';

class CreateChatPersona {
  const CreateChatPersona(this._personas);

  final ChatPersonaRepository _personas;

  Future<ChatPersona> call({
    required String id,
    required String name,
    ChatPersonaDescriptionMode descriptionMode =
        ChatPersonaDescriptionMode.simple,
    String shortDescription = '',
    String speakingStyle = '',
    String? avatarReference,
    String? personaPrompt,
    List<ChatPresetMessage> presetMessages = const [],
    String coreIdentity = '',
    String personality = '',
    String background = '',
    String relationshipToUser = '',
    String behaviorHabits = '',
    String preferences = '',
    String scenario = '',
    String notes = '',
    bool autoMemoryEnabled = true,
    bool useLongTermMemory = true,
    required DateTime nowUtc,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const DataFormatException('聊天角色名字不能为空。');
    }
    final now = nowUtc.toUtc();
    final persona = ChatPersona(
      metadata: EntityMetadata(
        id: id,
        createdAt: now,
        updatedAt: now,
        revision: 1,
      ),
      name: trimmedName,
      personaPrompt: personaPrompt?.trim(),
      presetMessages: ChatPresetMessage.parseList(
        presetMessages.map((pair) => pair.toJson()).toList(),
      ),
      avatarReference: _emptyToNull(avatarReference),
      descriptionMode: descriptionMode,
      shortDescription: shortDescription.trim(),
      speakingStyle: speakingStyle.trim(),
      coreIdentity: coreIdentity.trim(),
      personality: personality.trim(),
      background: background.trim(),
      relationshipToUser: relationshipToUser.trim(),
      behaviorHabits: behaviorHabits.trim(),
      preferences: preferences.trim(),
      scenario: scenario.trim(),
      notes: notes.trim(),
      autoMemoryEnabled: autoMemoryEnabled,
      useLongTermMemory: useLongTermMemory,
    );
    await _personas.upsertPersona(persona);
    return persona;
  }

  String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
