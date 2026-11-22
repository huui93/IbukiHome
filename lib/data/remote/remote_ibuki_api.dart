import 'dto/capabilities_response_dto.dart';
import 'dto/health_response_dto.dart';
import 'dto/project_detail_dto.dart';
import 'dto/project_summary_dto.dart';
import 'dto/segment_dto.dart';

abstract class RemoteIbukiApi {
  Future<HealthResponseDto> getHealth();
  Future<CapabilitiesResponseDto> getCapabilities();
  Future<List<ProjectSummaryDto>> listProjects();
  Future<ProjectDetailDto> getProject(String projectId);
  Future<List<SegmentDto>> listSegments(String projectId);
  Future<SegmentDto> getSegment(String projectId, String segmentId);
  void close();
}
