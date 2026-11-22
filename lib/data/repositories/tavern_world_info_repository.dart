import '../../domain/tavern/tavern_world_info.dart';

abstract class TavernWorldInfoRepository {
  Future<TavernWorldInfoSnapshot> loadWorldInfoState(
    String sessionId,
    String storyLineId,
  );
  Future<TavernWorldInfoJournal?> getWorldInfoJournal(String attemptId);
  Future<void> reconcileWorldInfo();
  Future<TavernReconciliationOutcome> reconcileWorldInfoAttempt(
    String attemptId,
  );
  Future<void> requireWorldInfoReady(String sessionId, String storyLineId);
}
