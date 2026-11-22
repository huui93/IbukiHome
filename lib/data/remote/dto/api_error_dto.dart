import 'dto_readers.dart';

class ApiErrorDto {
  const ApiErrorDto({
    required this.code,
    required this.message,
    required this.requestId,
    this.details,
  });

  final String code;
  final String message;
  final String requestId;
  final Map<String, dynamic>? details;

  factory ApiErrorDto.fromJson(Map<String, dynamic> json) {
    final details = json['details'];
    return ApiErrorDto(
      code: readRequiredString(json, 'code', 'ApiError'),
      message: readRequiredString(json, 'message', 'ApiError'),
      requestId: readRequiredString(json, 'request_id', 'ApiError'),
      details: details == null
          ? null
          : requireObject(details, 'ApiError.details'),
    );
  }
}
