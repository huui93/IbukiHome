import '../../domain/plugins/novel_plugin_models.dart';
import '../../domain/projects/novel_story_branch.dart';
import '../../domain/segments/segment.dart';

abstract class NovelPluginRepository {
  Future<NovelStoryBranch> branch(String projectId);
  Future<List<NovelStoryBranch>> branches(String storyId);
  Future<Set<String>> childProjectIds();
  Future<String> activeProject(String storyId);
  Future<void> selectBranch(String storyId, String projectId);
  Future<List<NovelHistoryMessage>> history(String projectId);
  Future<NovelStoryBranch> fork({
    required String projectId,
    required String newProjectId,
    required String label,
    String? atMessageId,
    String? expectedCandidateId,
    required DateTime now,
  });
  Future<void> setInheritance(
    String projectId,
    bool inherit,
    int expectedRevision,
  );
  Future<Segment> selectCandidate({
    required String projectId,
    required String messageId,
    required String candidateId,
    required DateTime now,
  });
  Future<void> endBranch({
    required String projectId,
    required String pluginId,
    required String segmentId,
    required int revision,
    required String contentHash,
    required String reason,
  });
  Future<void> saveReplyView(
    String segmentId,
    String contentHash,
    Map<String, Object?> data,
  );
  Future<Map<String, Object?>?> replyView(String segmentId, String contentHash);
  Future<void> deleteStory(String projectId, DateTime now);
}
