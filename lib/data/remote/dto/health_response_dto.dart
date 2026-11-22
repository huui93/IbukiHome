import 'dto_readers.dart';

class HealthResponseDto {
  const HealthResponseDto({
    required this.apiVersion,
    required this.appVersion,
    required this.serverTimeUtc,
    required this.status,
  });

  final int apiVersion;
  final String appVersion;
  final DateTime serverTimeUtc;
  final String status;

  factory HealthResponseDto.fromJson(Map<String, dynamic> json) {
    return HealthResponseDto(
      apiVersion: readRequiredInt(json, 'api_version', 'HealthResponse'),
      appVersion: readRequiredString(json, 'app_version', 'HealthResponse'),
      serverTimeUtc: readRequiredUtcDate(
        json,
        'server_time_utc',
        'HealthResponse',
      ),
      status: readRequiredString(json, 'status', 'HealthResponse'),
    );
  }
}
