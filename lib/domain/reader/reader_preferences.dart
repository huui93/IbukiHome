enum ReaderThemeMode {
  light,
  warm,
  dark;

  String get jsonValue => name;

  static ReaderThemeMode fromJson(String value) {
    return ReaderThemeMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ReaderThemeMode.warm,
    );
  }
}

class ReaderPreferences {
  const ReaderPreferences({
    required this.projectId,
    required this.fontSize,
    required this.lineHeight,
    required this.horizontalMargin,
    required this.theme,
    required this.updatedAt,
  });

  factory ReaderPreferences.defaults(String projectId) => ReaderPreferences(
    projectId: projectId,
    fontSize: 18,
    lineHeight: 1.75,
    horizontalMargin: 24,
    theme: ReaderThemeMode.warm,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  final String projectId;
  final double fontSize;
  final double lineHeight;
  final double horizontalMargin;
  final ReaderThemeMode theme;
  final DateTime updatedAt;

  ReaderPreferences copyWith({
    double? fontSize,
    double? lineHeight,
    double? horizontalMargin,
    ReaderThemeMode? theme,
    DateTime? updatedAt,
  }) {
    return ReaderPreferences(
      projectId: projectId,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      horizontalMargin: horizontalMargin ?? this.horizontalMargin,
      theme: theme ?? this.theme,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ReaderProgress {
  const ReaderProgress({
    required this.projectId,
    required this.scrollOffset,
    required this.updatedAt,
    this.lastReadSegmentId,
  });

  factory ReaderProgress.empty(String projectId) => ReaderProgress(
    projectId: projectId,
    scrollOffset: 0,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  final String projectId;
  final String? lastReadSegmentId;
  final double scrollOffset;
  final DateTime updatedAt;

  ReaderProgress copyWith({
    String? lastReadSegmentId,
    double? scrollOffset,
    DateTime? updatedAt,
  }) {
    return ReaderProgress(
      projectId: projectId,
      lastReadSegmentId: lastReadSegmentId ?? this.lastReadSegmentId,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
