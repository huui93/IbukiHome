import 'dto_readers.dart';

class CapabilitiesResponseDto {
  const CapabilitiesResponseDto({
    required this.apiVersion,
    required this.readOnly,
    required this.supportsProjects,
    required this.supportsSegments,
    required this.supportsChanges,
    required this.supportsWrite,
    required this.supportsStreaming,
    required this.supportsAiProxy,
  });

  final int apiVersion;
  final bool readOnly;
  final bool supportsProjects;
  final bool supportsSegments;
  final bool supportsChanges;
  final bool supportsWrite;
  final bool supportsStreaming;
  final bool supportsAiProxy;

  factory CapabilitiesResponseDto.fromJson(Map<String, dynamic> json) {
    return CapabilitiesResponseDto(
      apiVersion: readRequiredInt(json, 'api_version', 'CapabilitiesResponse'),
      readOnly: readRequiredBool(json, 'read_only', 'CapabilitiesResponse'),
      supportsProjects: readRequiredBool(
        json,
        'supports_projects',
        'CapabilitiesResponse',
      ),
      supportsSegments: readRequiredBool(
        json,
        'supports_segments',
        'CapabilitiesResponse',
      ),
      supportsChanges: readRequiredBool(
        json,
        'supports_changes',
        'CapabilitiesResponse',
      ),
      supportsWrite: readRequiredBool(
        json,
        'supports_write',
        'CapabilitiesResponse',
      ),
      supportsStreaming: readRequiredBool(
        json,
        'supports_streaming',
        'CapabilitiesResponse',
      ),
      supportsAiProxy: readRequiredBool(
        json,
        'supports_ai_proxy',
        'CapabilitiesResponse',
      ),
    );
  }
}
