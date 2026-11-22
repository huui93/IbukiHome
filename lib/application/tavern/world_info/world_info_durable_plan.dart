import '../../../domain/tavern/tavern_models.dart';
import '../../../domain/tavern/tavern_world_info.dart';
import '../prompt/prompt_models.dart';
import 'world_info_models.dart';

WorldInfoRuntimeState restoreWorldInfoSnapshot(
  TavernWorldInfoSnapshot snapshot,
) => WorldInfoRuntimeState(
  sessionId: snapshot.sessionId,
  storyLineId: snapshot.storyLineId,
  observedMessageCount: snapshot.data.messageCount,
  historyMarker: snapshot.data.historyMarker,
  timed: Map.unmodifiable({
    for (final timer in snapshot.data.timers)
      timer.identity: WorldInfoTimedState(
        activatedAtMessage: timer.activatedAt,
        definitionFingerprint: timer.definitionFingerprint,
        definitionSignature: int.parse(
          timer.definitionFingerprint.substring(0, 15),
          radix: 16,
        ),
      ),
  }),
);

TavernWorldInfoPlan durableWorldInfoPlan({
  required TavernGenerationAttempt attempt,
  required TavernWorldInfoSnapshot base,
  required WorldInfoRuntimeState eligible,
  required List<WorldInfoEntry> entries,
  required CompiledPrompt compiled,
  required String requestFingerprint,
}) {
  final definitions = {for (final entry in entries) entry.identity: entry};
  final included = compiled.trace.decisions
      .where(
        (d) =>
            d.origin.type == 'worldInfoEntry' &&
            (d.outcome == PromptCompileOutcome.included ||
                d.outcome == PromptCompileOutcome.trimmed),
      )
      .map((d) => (d.origin.parentId!, d.origin.id))
      .toList();
  final next = TavernWorldInfoData(
    messageCount: eligible.observedMessageCount,
    historyMarker: eligible.historyMarker,
    timers: List.unmodifiable(
      eligible.timed.entries.map((item) {
        final entry = definitions[item.key]!;
        return TavernLoreTimer(
          bookId: item.key.$1,
          entryId: item.key.$2,
          activatedAt: item.value.activatedAtMessage,
          definitionFingerprint: entry.definitionFingerprint,
          stickyUntil: item.value.activatedAtMessage + entry.stickyMessages,
          cooldownUntil:
              item.value.activatedAtMessage +
              entry.stickyMessages +
              entry.cooldownMessages,
          delayMessages: entry.delayMessages,
        );
      }),
    ),
  );
  final compileHash = tavernDigest(
    compiled.segments
        .map(
          (s) => [
            s.sourceId,
            s.role.name,
            s.atoms.map((a) => [a.id, a.kind.name, a.text]).toList(),
          ],
        )
        .toList(),
  );
  return TavernWorldInfoPlan(
    attemptId: attempt.id,
    sessionId: attempt.sessionId,
    storyLineId: attempt.storyLineId,
    turnId: attempt.turnId,
    alternativeId: attempt.alternativeId,
    compileFingerprint: compileHash,
    requestFingerprint: requestFingerprint,
    expectedVersion: base.version,
    baseFingerprint: base.data.fingerprint,
    delta: TavernWorldInfoDelta.between(base.data, next),
    included: List.unmodifiable(included),
  );
}
