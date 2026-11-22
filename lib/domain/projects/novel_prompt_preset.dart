import '../common/entity_metadata.dart';

class NovelPromptPreset {
  const NovelPromptPreset({
    required this.metadata,
    required this.name,
    required this.content,
  });
  final EntityMetadata metadata;
  final String name;
  final String content;
  String get id => metadata.id;
}
