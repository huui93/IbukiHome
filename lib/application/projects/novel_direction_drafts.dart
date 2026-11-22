import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Unsaved writing directions live only in this process and remain scoped to
/// a novel project when its editor is replaced by another project's editor.
final novelDirectionDraftsProvider =
    NotifierProvider<NovelDirectionDrafts, Map<String, String>>(
      NovelDirectionDrafts.new,
    );

class NovelDirectionDrafts extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};
  void save(String projectId, String value) {
    if ((state[projectId] ?? '') == value) return;
    final next = {...state};
    if (value.isEmpty) {
      next.remove(projectId);
    } else {
      next[projectId] = value;
    }
    state = Map.unmodifiable(next);
  }
}
