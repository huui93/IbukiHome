import 'package:ibukihome/core/network/api_client_exceptions.dart';
import 'package:ibukihome/data/remote/dto/capabilities_response_dto.dart';
import 'package:ibukihome/data/remote/dto/health_response_dto.dart';
import 'package:ibukihome/data/remote/dto/project_detail_dto.dart';
import 'package:ibukihome/data/remote/dto/project_summary_dto.dart';
import 'package:ibukihome/data/remote/dto/segment_dto.dart';
import 'package:ibukihome/data/remote/remote_ibuki_api.dart';

class FakeRemoteIbukiApi implements RemoteIbukiApi {
  int healthApiVersion = 1;
  bool supportsProjects = true;
  bool supportsSegments = true;
  bool supportsWrite = false;
  Object? healthError;
  Object? capabilitiesError;
  Object? projectListError;
  int projectListCalls = 0;
  int segmentListCalls = 0;

  List<ProjectSummaryDto> projects = [
    ProjectSummaryDto(
      id: 'remote-project-1',
      title: '电脑测试故事',
      description: '来自电脑端的只读项目',
      updatedAt: DateTime.utc(2026, 7, 29, 8),
      revision: 1,
      segmentCount: 2,
    ),
  ];

  ProjectDetailDto detail = ProjectDetailDto(
    id: 'remote-project-1',
    title: '电脑测试故事',
    description: '来自电脑端的只读项目',
    createdAt: DateTime.utc(2026, 7, 29, 7),
    updatedAt: DateTime.utc(2026, 7, 29, 8),
    revision: 1,
    segmentCount: 2,
  );

  List<SegmentDto> segments = [
    SegmentDto(
      id: 'remote-segment-1',
      projectId: 'remote-project-1',
      orderIndex: 0,
      content: '第一段电脑正文。',
      createdAt: DateTime.utc(2026, 7, 29, 7, 10),
      updatedAt: DateTime.utc(2026, 7, 29, 8),
      revision: 2,
    ),
    SegmentDto(
      id: 'remote-segment-2',
      projectId: 'remote-project-1',
      orderIndex: 1,
      content: '第二段电脑正文。',
      createdAt: DateTime.utc(2026, 7, 29, 7, 20),
      updatedAt: DateTime.utc(2026, 7, 29, 8),
      revision: 1,
    ),
  ];

  @override
  Future<HealthResponseDto> getHealth() async {
    _throwIfNeeded(healthError);
    return HealthResponseDto(
      apiVersion: healthApiVersion,
      appVersion: 'test',
      serverTimeUtc: DateTime.utc(2026, 7, 29, 9),
      status: 'ok',
    );
  }

  @override
  Future<CapabilitiesResponseDto> getCapabilities() async {
    _throwIfNeeded(capabilitiesError);
    return CapabilitiesResponseDto(
      apiVersion: 1,
      readOnly: true,
      supportsProjects: supportsProjects,
      supportsSegments: supportsSegments,
      supportsChanges: false,
      supportsWrite: supportsWrite,
      supportsStreaming: false,
      supportsAiProxy: false,
    );
  }

  @override
  Future<List<ProjectSummaryDto>> listProjects() async {
    projectListCalls += 1;
    _throwIfNeeded(projectListError);
    return projects;
  }

  @override
  Future<ProjectDetailDto> getProject(String projectId) async {
    if (projectId != detail.id) {
      throw const RemoteNotFoundException('missing');
    }
    return detail;
  }

  @override
  Future<List<SegmentDto>> listSegments(String projectId) async {
    segmentListCalls += 1;
    if (projectId != detail.id) {
      throw const RemoteNotFoundException('missing');
    }
    return segments;
  }

  @override
  Future<SegmentDto> getSegment(String projectId, String segmentId) async {
    return segments.firstWhere(
      (segment) => segment.projectId == projectId && segment.id == segmentId,
      orElse: () => throw const RemoteNotFoundException('missing'),
    );
  }

  @override
  void close() {}

  void _throwIfNeeded(Object? error) {
    if (error == null) {
      return;
    }
    if (error is RemoteApiException) {
      throw error;
    }
    throw StateError('$error');
  }
}
