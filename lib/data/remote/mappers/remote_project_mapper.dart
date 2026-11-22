import '../../../domain/common/entity_metadata.dart';
import '../../../domain/projects/project.dart';
import '../dto/project_detail_dto.dart';
import '../dto/project_summary_dto.dart';

Project projectFromRemoteDetail(ProjectDetailDto dto) {
  return Project(
    metadata: EntityMetadata(
      id: dto.id,
      createdAt: dto.createdAt,
      updatedAt: dto.updatedAt,
      revision: dto.revision,
    ),
    title: dto.title,
    description: dto.description,
  );
}

Project projectFromRemoteSummary(ProjectSummaryDto dto) {
  return Project(
    metadata: EntityMetadata(
      id: dto.id,
      createdAt: dto.updatedAt,
      updatedAt: dto.updatedAt,
      revision: dto.revision,
    ),
    title: dto.title,
    description: dto.description,
  );
}
