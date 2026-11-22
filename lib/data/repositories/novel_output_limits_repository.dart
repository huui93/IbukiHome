import '../../domain/projects/novel_output_limits.dart';

abstract class NovelOutputLimitsRepository {
  Future<NovelOutputLimits> get(String projectId);
  Future<NovelOutputLimits> save(
    NovelOutputLimits value, {
    required int expectedRevision,
    required DateTime now,
  });
}
