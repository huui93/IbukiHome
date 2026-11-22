import '../../../domain/world_roleplay/world_roleplay_models.dart';
import '../prompt/prompt_models.dart';
import 'world_info_models.dart';

/// Maps already-selected native lore assets into the Tavern runtime boundary.
/// References and session overrides are resolved by the caller before mapping.
class WorldInfoNativeAdapter {
  const WorldInfoNativeAdapter();

  WorldInfoEntry fromLoreEntry(
    LoreEntry lore, {
    required bool bookEnabled,
    int referencePriority = 0,
    Set<String> worldIds = const {},
    Set<String> characterIds = const {},
    Set<String> personaIds = const {},
  }) => WorldInfoEntry(
    bookId: lore.worldBookId,
    entryId: lore.id,
    title: lore.title,
    content: lore.content,
    bookEnabled: bookEnabled,
    enabled: lore.enabled,
    primaryKeys: lore.keywords,
    secondaryKeys: lore.secondaryKeywords,
    constant: lore.activationMode == LoreActivationMode.always,
    manualOnly: lore.activationMode == LoreActivationMode.manual,
    probabilityPercent: (lore.probability * 100).round().clamp(0, 100),
    priority: referencePriority,
    order: lore.priority,
    placement: switch (lore.insertionPosition) {
      'before_character' => const PromptPlacement(
        PromptPlacementKind.beforeCharacter,
      ),
      'after_character' => const PromptPlacement(
        PromptPlacementKind.afterCharacter,
      ),
      'after_history' => const PromptPlacement(
        PromptPlacementKind.afterHistory,
      ),
      _ => const PromptPlacement(PromptPlacementKind.beforeHistory),
    },
    worldIds: worldIds,
    characterIds: characterIds,
    personaIds: personaIds,
  );
}
