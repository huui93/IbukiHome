import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/chat_persona_repository.dart';
import '../../domain/chat/chat_persona.dart';
import '../../domain/chat/chat_preset_message.dart';

const _unsetSavedAvatar = Object();

class SaveChatPersona {
  const SaveChatPersona(this._personas);

  final ChatPersonaRepository _personas;

  Future<ChatPersona> call({
    required String personaId,
    required String name,
    ChatPersonaDescriptionMode? descriptionMode,
    String? shortDescription,
    String? speakingStyle,
    Object? avatarReference = _unsetSavedAvatar,
    String? personaPrompt,
    List<ChatPresetMessage>? presetMessages,
    String? coreIdentity,
    String? personality,
    String? background,
    String? relationshipToUser,
    String? behaviorHabits,
    String? preferences,
    String? scenario,
    String? notes,
    bool? autoMemoryEnabled,
    bool? useLongTermMemory,
    required DateTime nowUtc,
  }) async {
    final stored = await _personas.getPersona(personaId);
    if (stored.deletedAt != null) {
      throw const DataConflictException('已删除的聊天角色不能编辑。');
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const DataFormatException('聊天角色名字不能为空。');
    }
    final updated = stored.copyWith(
      metadata: stored.metadata.copyWith(
        updatedAt: nowUtc.toUtc(),
        revision: stored.revision + 1,
      ),
      name: trimmedName,
      personaPrompt: personaPrompt?.trim() ?? stored.personaPrompt,
      presetMessages: presetMessages == null
          ? stored.presetMessages
          : ChatPresetMessage.parseList(
              presetMessages.map((pair) => pair.toJson()).toList(),
            ),
      avatarReference: avatarReference == _unsetSavedAvatar
          ? stored.avatarReference
          : _emptyToNull(avatarReference as String?),
      descriptionMode: descriptionMode,
      shortDescription: shortDescription?.trim(),
      speakingStyle: speakingStyle?.trim(),
      coreIdentity: coreIdentity?.trim(),
      personality: personality?.trim(),
      background: background?.trim(),
      relationshipToUser: relationshipToUser?.trim(),
      behaviorHabits: behaviorHabits?.trim(),
      preferences: preferences?.trim(),
      scenario: scenario?.trim(),
      notes: notes?.trim(),
      autoMemoryEnabled: autoMemoryEnabled,
      useLongTermMemory: useLongTermMemory,
    );
    await _personas.upsertPersona(updated);
    return updated;
  }

  String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
