import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../domain/tavern/tavern_models.dart';
import '../prompt/prompt_history_assembler.dart';
import '../prompt/prompt_models.dart';
import 'world_info_models.dart';

class WorldInfoScanContextBuilder {
  const WorldInfoScanContextBuilder();

  WorldInfoActivationContext fromProjection(
    TavernTranscriptProjection projection, {
    required PromptCompileMode mode,
    String? targetTurnId,
    String? worldId,
    String? personaId,
    Set<String> characterIds = const {},
    Set<String> characterTags = const {},
    Map<WorldInfoAdditionalScanSource, String> additionalScanText = const {},
    bool scanToolResultText = false,
  }) {
    final assembly = const PromptHistoryAssembler().assemble(
      projection,
      mode: mode,
      targetTurnId: targetTurnId,
    );
    final messages = <WorldInfoScanMessage>[];
    for (final source in assembly.sources) {
      if (source.role == PromptRoleIntent.context) continue;
      final parts = <String>[];
      for (final atom in source.atoms) {
        if (atom.kind == PromptAtomKind.text && atom.text != null) {
          parts.add(atom.text!);
        } else if (scanToolResultText &&
            atom.kind == PromptAtomKind.toolResult &&
            atom.result?['text'] is String) {
          parts.add(atom.result!['text']! as String);
        }
      }
      messages.add(
        WorldInfoScanMessage(turnId: source.origin.id, text: parts.join('\n')),
      );
    }
    return WorldInfoActivationContext(
      sessionId: projection.session.id,
      storyLineId: projection.storyLine.id,
      generationType: switch (mode) {
        PromptCompileMode.normal => WorldInfoGenerationType.normal,
        PromptCompileMode.regenerate => WorldInfoGenerationType.regenerate,
        PromptCompileMode.continueTurn => WorldInfoGenerationType.continueTurn,
      },
      messages: List.unmodifiable(messages),
      historyMarker: sha256
          .convert(
            utf8.encode(
              jsonEncode([
                assembly.sources
                    .where((s) => s.role != PromptRoleIntent.context)
                    .map((s) => s.role.name)
                    .toList(),
                messages.map((m) => m.text).toList(),
              ]),
            ),
          )
          .toString(),
      worldId: worldId,
      personaId: personaId,
      characterIds: Set.unmodifiable(characterIds),
      characterTags: Set.unmodifiable(characterTags),
      additionalScanText: Map.unmodifiable(additionalScanText),
    );
  }
}
