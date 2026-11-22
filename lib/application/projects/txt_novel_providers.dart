import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/data_exceptions.dart';
import '../../data/memory/in_memory_novel_import_repository.dart';
import '../../data/repositories/novel_import_repository.dart';
import '../../data/repositories/committed_entity_cache.dart';
import '../../data/repositories/invalidatable_read_cache.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/projects/project.dart';
import '../../domain/segments/segment.dart';
import '../providers/repository_providers.dart';
import 'txt_novel_source.dart';

final txtNovelPickerProvider = Provider<TxtNovelPicker>(
  (ref) => const SafTxtNovelPicker(),
);
final txtNovelDecoderProvider = Provider((ref) => const TxtNovelDecoder());
final novelImportRepositoryProvider = Provider<NovelImportRepository>(
  (ref) => InMemoryNovelImportRepository(ref.watch(inMemoryIbukiStoreProvider)),
);
final importTxtNovelProvider = Provider((ref) => ImportTxtNovel(ref));

class ImportTxtNovel {
  const ImportTxtNovel(this.ref);
  final Ref ref;
  Future<Project> call(PreparedTxtNovel novel, String title) async {
    if (title.trim().isEmpty ||
        !novel.parts.any((part) => part.trim().isNotEmpty)) {
      throw const DataFormatException('小说名称和正文不能为空。');
    }
    final ids = ref.read(entityIdGeneratorProvider);
    final now = ref.read(utcClockProvider).now().toUtc();
    EntityMetadata metadata(String kind) => EntityMetadata(
      id: ids.nextId(kind),
      createdAt: now,
      updatedAt: now,
      revision: 1,
    );
    final project = Project(
      metadata: metadata('project'),
      title: title.trim(),
      description: '',
    );
    final segments = [
      for (var i = 0; i < novel.parts.length; i++)
        Segment(
          metadata: metadata('segment'),
          projectId: project.id,
          orderIndex: i,
          content: novel.parts[i],
        ),
    ];
    await ref
        .read(novelImportRepositoryProvider)
        .insertNovel(project, segments);
    final projects = ref.read(projectRepositoryProvider);
    if (projects is CommittedEntityCache<Project>) {
      (projects as CommittedEntityCache<Project>).acceptCommittedEntity(
        project,
      );
    }
    final segmentCache = ref.read(segmentRepositoryProvider);
    if (segmentCache is InvalidatableReadCache) {
      (segmentCache as InvalidatableReadCache).invalidateAll();
    }
    return project;
  }
}
