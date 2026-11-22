import '../../domain/tavern/tavern_models.dart';
import '../../domain/tavern/tavern_world_info.dart';

abstract class TavernRepository {
  Future<Object> get generationScopeKey;
  Future<TavernSession> createSession(
    TavernSession session,
    TavernStoryLine root, {
    List<TavernParticipant> participants = const [],
  });
  Future<List<TavernSession>> listSessions({
    bool archived = false,
    int limit = 100,
  });
  Future<List<TavernStorySummary>> listStorySummaries({
    bool archived = false,
    int limit = 100,
  });
  Future<void> saveSession(TavernSession session);
  Future<List<TavernStoryLine>> listStoryLines(String sessionId);
  Future<TavernSession> getSession(String id);
  Future<TavernParticipant> addParticipant(TavernParticipant participant);
  Future<List<TavernParticipant>> listParticipants(String sessionId);
  Future<TavernStoryLine> createStoryLine(
    TavernStoryLine line, {
    bool activate = false,
  });
  Future<TavernStoryLine> getStoryLine(String id);
  Future<void> selectStoryLine(String sessionId, String storyLineId);
  Future<void> archiveStoryLine(String id);
  Future<TavernTurn> appendTurn(
    TavernTurn turn,
    TavernAlternative first, {
    TavernGenerationAttempt? attempt,
    TavernWorldInfoPlan? reconciliation,
    List<TavernContentPart> initialParts = const [],
  });
  Future<TavernAlternative> addAlternative(
    TavernAlternative alternative, {
    TavernGenerationAttempt? attempt,
    TavernWorldInfoPlan? reconciliation,
  });
  Future<void> selectAlternative(String turnId, String alternativeId);
  Future<void> deleteAlternative(String id);
  Future<TavernContentPart> appendContentPart(TavernContentPart part);
  Future<List<TavernContentPart>> listContentParts(String alternativeId);
  Future<void> persistGenerationBatch(
    String attemptId,
    List<TavernContentPart> parts, {
    TavernGenerationStatus? terminalStatus,
    String? reason,
    bool selectAlternative = false,
    String? expectedSelectedAlternativeId,
  });
  Future<List<TavernGenerationAttempt>> recoverInterruptedAttempts();
  Future<TavernGenerationAttempt> recordAttempt(
    TavernGenerationAttempt attempt, {
    TavernWorldInfoPlan? reconciliation,
  });
  Future<void> updateAttempt(
    String id,
    TavernGenerationStatus status, {
    String? reason,
    bool hasPartialContent = false,
  });
  Future<List<TavernGenerationAttempt>> listAttempts(String alternativeId);
  Future<TavernTranscriptProjection> loadTranscript(
    String sessionId, {
    String? storyLineId,
  });
  Future<void> archiveSession(String id);
  Future<void> deleteSession(String id);
}
