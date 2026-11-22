import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/network/api_client_exceptions.dart';
import '../../core/network/remote_api_config.dart';
import 'dto/api_error_dto.dart';
import 'dto/capabilities_response_dto.dart';
import 'dto/dto_readers.dart';
import 'dto/health_response_dto.dart';
import 'dto/project_detail_dto.dart';
import 'dto/project_summary_dto.dart';
import 'dto/segment_dto.dart';
import 'remote_ibuki_api.dart';

class HttpRemoteIbukiApi implements RemoteIbukiApi {
  HttpRemoteIbukiApi({required this.config, required this.client});

  factory HttpRemoteIbukiApi.withDefaultClient({
    required RemoteApiConfig config,
  }) {
    return HttpRemoteIbukiApi(config: config, client: defaultClient());
  }

  static http.Client defaultClient() => http.Client();

  final RemoteApiConfig config;
  final http.Client client;
  bool _closed = false;

  @override
  Future<HealthResponseDto> getHealth() async {
    final json = await _getObject('/health', authenticated: false);
    return HealthResponseDto.fromJson(json);
  }

  @override
  Future<CapabilitiesResponseDto> getCapabilities() async {
    final json = await _getObject('/capabilities');
    return CapabilitiesResponseDto.fromJson(json);
  }

  @override
  Future<List<ProjectSummaryDto>> listProjects() async {
    final json = await _getObject('/projects');
    final items = readRequiredList(json, 'items', 'ProjectListResponse');
    return [
      for (final item in items)
        ProjectSummaryDto.fromJson(requireObject(item, 'ProjectSummary')),
    ];
  }

  @override
  Future<ProjectDetailDto> getProject(String projectId) async {
    final json = await _getObject(
      '/projects/${Uri.encodeComponent(projectId)}',
    );
    return ProjectDetailDto.fromJson(json);
  }

  @override
  Future<List<SegmentDto>> listSegments(String projectId) async {
    final json = await _getObject(
      '/projects/${Uri.encodeComponent(projectId)}/segments',
    );
    final items = readRequiredList(json, 'items', 'SegmentListResponse');
    return [
      for (final item in items)
        SegmentDto.fromJson(requireObject(item, 'Segment')),
    ];
  }

  @override
  Future<SegmentDto> getSegment(String projectId, String segmentId) async {
    final json = await _getObject(
      '/projects/${Uri.encodeComponent(projectId)}/segments/'
      '${Uri.encodeComponent(segmentId)}',
    );
    return SegmentDto.fromJson(json);
  }

  @override
  void close() {
    _closed = true;
    client.close();
  }

  Future<Map<String, dynamic>> _getObject(
    String path, {
    bool authenticated = true,
  }) async {
    if (_closed) {
      throw const RemoteClientClosedException();
    }
    final response = await _send(path, authenticated: authenticated);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _decodeObject(response);
    }
    final error = _decodeApiError(response);
    switch (response.statusCode) {
      case 401:
        throw RemoteAuthException(
          error.message,
          statusCode: response.statusCode,
          requestId: error.requestId,
        );
      case 404:
        throw RemoteNotFoundException(
          error.message,
          statusCode: response.statusCode,
          requestId: error.requestId,
        );
      case 409:
        throw RemoteConflictException(
          error.message,
          statusCode: response.statusCode,
          requestId: error.requestId,
        );
      default:
        if (response.statusCode >= 500) {
          throw RemoteServerException(
            error.message,
            statusCode: response.statusCode,
            requestId: error.requestId,
          );
        }
        throw RemoteProtocolException(
          error.message,
          statusCode: response.statusCode,
          requestId: error.requestId,
        );
    }
  }

  Future<http.Response> _send(
    String path, {
    required bool authenticated,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (authenticated) {
      headers['Authorization'] = 'Bearer ${config.bearerToken}';
    }
    try {
      return await client
          .get(_endpoint(path), headers: headers)
          .timeout(config.timeout);
    } on TimeoutException {
      throw const RemoteNetworkException('请求超时。');
    } on SocketException {
      throw const RemoteNetworkException('无法连接到桌面端服务。');
    } on http.ClientException {
      throw const RemoteNetworkException('网络请求失败。');
    }
  }

  Uri _endpoint(String path) {
    final base = _apiBaseUri().toString().replaceFirst(RegExp(r'/$'), '');
    return Uri.parse('$base$path');
  }

  Uri _apiBaseUri() {
    final normalizedPath = config.baseUri.path.replaceFirst(RegExp(r'/+$'), '');
    if (normalizedPath.endsWith('/api/v1')) {
      return config.baseUri.replace(
        path: normalizedPath,
        query: null,
        fragment: null,
      );
    }
    final nextPath = normalizedPath.isEmpty
        ? '/api/v1'
        : '$normalizedPath/api/v1';
    return config.baseUri.replace(path: nextPath, query: null, fragment: null);
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return requireObject(decoded, 'Response');
    } on FormatException {
      throw RemoteProtocolException(
        '响应不是有效 JSON。',
        statusCode: response.statusCode,
      );
    }
  }

  ApiErrorDto _decodeApiError(http.Response response) {
    try {
      return ApiErrorDto.fromJson(_decodeObject(response));
    } on RemoteApiException {
      return ApiErrorDto(
        code: 'protocol_error',
        message: '服务返回了无法识别的错误响应。',
        requestId: response.headers['x-request-id'] ?? '',
      );
    }
  }
}
