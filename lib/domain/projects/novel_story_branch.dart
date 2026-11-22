class NovelStoryBranch {
  const NovelStoryBranch({
    required this.projectId,
    required this.storyId,
    required this.label,
    this.parentId,
    this.inheritSettings = true,
    this.revision = 1,
    this.endedByPlugin,
    this.endedSourceSegmentId,
    this.endedSourceHash,
    this.endedReason,
  });
  final String projectId;
  final String storyId;
  final String? parentId;
  final String label;
  final bool inheritSettings;
  final int revision;
  final String? endedByPlugin;
  final String? endedSourceSegmentId;
  final String? endedSourceHash;
  final String? endedReason;
  bool get ended => endedByPlugin != null;
  Map<String, Object?> toJson() => {
    'projectId': projectId,
    'storyId': storyId,
    'parentId': parentId,
    'label': label,
    'inheritSettings': inheritSettings,
    'revision': revision,
    'ended': ended,
    'endedByPlugin': endedByPlugin,
    'endedSourceSegmentId': endedSourceSegmentId,
    'endedSourceHash': endedSourceHash,
    'endedReason': endedReason,
  };
}
