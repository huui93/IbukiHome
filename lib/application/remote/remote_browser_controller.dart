import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client_exceptions.dart';
import '../../data/remote/dto/project_detail_dto.dart';
import '../../data/remote/dto/project_summary_dto.dart';
import '../../data/remote/dto/segment_dto.dart';
import 'remote_connection_controller.dart';

final remoteBrowserControllerProvider =
    NotifierProvider<RemoteBrowserController, RemoteBrowserState>(
      RemoteBrowserController.new,
    );

class RemoteBrowserState {
  const RemoteBrowserState({
    this.projects = const [],
    this.projectDetails = const {},
    this.segmentsByProject = const {},
    this.segmentDetails = const {},
    this.isLoading = false,
    this.errorMessage,
    this.staleMessage,
  });

  final List<ProjectSummaryDto> projects;
  final Map<String, ProjectDetailDto> projectDetails;
  final Map<String, List<SegmentDto>> segmentsByProject;
  final Map<String, SegmentDto> segmentDetails;
  final bool isLoading;
  final String? errorMessage;
  final String? staleMessage;

  RemoteBrowserState copyWith({
    List<ProjectSummaryDto>? projects,
    Map<String, ProjectDetailDto>? projectDetails,
    Map<String, List<SegmentDto>>? segmentsByProject,
    Map<String, SegmentDto>? segmentDetails,
    bool? isLoading,
    String? errorMessage,
    String? staleMessage,
    bool clearMessages = false,
  }) {
    return RemoteBrowserState(
      projects: projects ?? this.projects,
      projectDetails: projectDetails ?? this.projectDetails,
      segmentsByProject: segmentsByProject ?? this.segmentsByProject,
      segmentDetails: segmentDetails ?? this.segmentDetails,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearMessages ? null : errorMessage,
      staleMessage: clearMessages ? null : staleMessage,
    );
  }
}

class RemoteBrowserController extends Notifier<RemoteBrowserState> {
  @override
  RemoteBrowserState build() => const RemoteBrowserState();

  void clear() {
    state = const RemoteBrowserState();
  }

  Future<void> loadProjects() async {
    await _load(() async {
      final projects = await ref
          .read(remoteConnectionControllerProvider.notifier)
          .withVerifiedApi((api) => api.listProjects());
      state = state.copyWith(
        projects: projects,
        isLoading: false,
        clearMessages: true,
      );
    }, hasCache: state.projects.isNotEmpty);
  }

  Future<void> loadProject(String projectId) async {
    await _load(() async {
      final detail = await ref
          .read(remoteConnectionControllerProvider.notifier)
          .withVerifiedApi((api) => api.getProject(projectId));
      state = state.copyWith(
        projectDetails: {...state.projectDetails, projectId: detail},
        isLoading: false,
        clearMessages: true,
      );
    }, hasCache: state.projectDetails.containsKey(projectId));
  }

  Future<void> loadSegments(String projectId) async {
    await _load(() async {
      final segments = await ref
          .read(remoteConnectionControllerProvider.notifier)
          .withVerifiedApi((api) => api.listSegments(projectId));
      state = state.copyWith(
        segmentsByProject: {...state.segmentsByProject, projectId: segments},
        isLoading: false,
        clearMessages: true,
      );
    }, hasCache: state.segmentsByProject.containsKey(projectId));
  }

  Future<void> loadSegment(String projectId, String segmentId) async {
    await _load(() async {
      final segment = await ref
          .read(remoteConnectionControllerProvider.notifier)
          .withVerifiedApi((api) => api.getSegment(projectId, segmentId));
      state = state.copyWith(
        segmentDetails: {...state.segmentDetails, segmentId: segment},
        isLoading: false,
        clearMessages: true,
      );
    }, hasCache: state.segmentDetails.containsKey(segmentId));
  }

  Future<void> _load(
    Future<void> Function() run, {
    required bool hasCache,
  }) async {
    state = state.copyWith(isLoading: true, clearMessages: true);
    try {
      await run();
    } catch (error) {
      final message = _friendlyRemoteError(error);
      state = state.copyWith(
        isLoading: false,
        errorMessage: hasCache ? null : message,
        staleMessage: hasCache ? '连接已断开，内容可能不是最新。' : null,
      );
    }
  }
}

String _friendlyRemoteError(Object error) {
  if (error is RemoteConnectionRequiredException) {
    return '请先连接电脑。';
  }
  if (error is RemoteAuthException) {
    return 'Token 错误，请重新连接电脑。';
  }
  if (error is RemoteNotFoundException) {
    return '电脑端没有找到这个内容。';
  }
  if (error is RemoteNetworkException) {
    return '无法连接电脑，请稍后手动刷新。';
  }
  if (error is RemoteProtocolException) {
    return '电脑端返回的数据格式无法识别。';
  }
  if (error is RemoteServerException) {
    return '电脑端服务暂时无法完成请求。';
  }
  return '远程内容读取失败。';
}
