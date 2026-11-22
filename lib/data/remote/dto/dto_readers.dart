import '../../../core/network/api_client_exceptions.dart';

String readRequiredString(
  Map<String, dynamic> json,
  String key,
  String modelName,
) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  throw RemoteProtocolException('$modelName.$key must be a string.');
}

int readRequiredInt(Map<String, dynamic> json, String key, String modelName) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw RemoteProtocolException('$modelName.$key must be an integer.');
}

bool readRequiredBool(Map<String, dynamic> json, String key, String modelName) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw RemoteProtocolException('$modelName.$key must be a boolean.');
}

DateTime readRequiredUtcDate(
  Map<String, dynamic> json,
  String key,
  String modelName,
) {
  final value = readRequiredString(json, key, modelName);
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw RemoteProtocolException('$modelName.$key must be ISO 8601 UTC.');
  }
}

List<dynamic> readRequiredList(
  Map<String, dynamic> json,
  String key,
  String modelName,
) {
  final value = json[key];
  if (value is List<dynamic>) {
    return value;
  }
  throw RemoteProtocolException('$modelName.$key must be a list.');
}

Map<String, dynamic> requireObject(Object? value, String modelName) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw RemoteProtocolException('$modelName must be an object.');
}
