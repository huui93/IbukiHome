import '../../core/errors/data_exceptions.dart';
import '../common/entity_metadata.dart';
import 'ai_provider_type.dart';

enum AiProviderConnectionStatus { untested, connected, failed }

class AiProviderConfig {
  const AiProviderConfig({
    required this.id,
    required this.type,
    required this.displayName,
    required this.baseUrl,
    required this.apiKeyRef,
    required this.selectedModel,
    required this.enabled,
    required this.connectionStatus,
    required this.availableModels,
    this.verifiedModels = const [],
    this.incompatibleModels = const [],
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.lastVerifiedAtUtc,
  });

  final String id;
  final AiProviderType type;
  final String displayName;
  final String baseUrl;
  final String apiKeyRef;
  final String selectedModel;
  final bool enabled;
  final AiProviderConnectionStatus connectionStatus;
  final List<String> availableModels;
  final List<String> verifiedModels;
  final List<String> incompatibleModels;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? lastVerifiedAtUtc;

  bool get isCustom => type == AiProviderType.custom;

  AiProviderConfig copyWith({
    String? displayName,
    String? baseUrl,
    String? selectedModel,
    bool? enabled,
    AiProviderConnectionStatus? connectionStatus,
    List<String>? availableModels,
    List<String>? verifiedModels,
    List<String>? incompatibleModels,
    DateTime? updatedAtUtc,
    Object? lastVerifiedAtUtc = _unset,
  }) {
    return AiProviderConfig(
      id: id,
      type: type,
      displayName: displayName ?? this.displayName,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKeyRef: apiKeyRef,
      selectedModel: selectedModel ?? this.selectedModel,
      enabled: enabled ?? this.enabled,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      availableModels: List.unmodifiable(
        availableModels ?? this.availableModels,
      ),
      verifiedModels: List.unmodifiable(verifiedModels ?? this.verifiedModels),
      incompatibleModels: List.unmodifiable(
        incompatibleModels ?? this.incompatibleModels,
      ),
      createdAtUtc: createdAtUtc,
      updatedAtUtc: (updatedAtUtc ?? this.updatedAtUtc).toUtc(),
      lastVerifiedAtUtc: lastVerifiedAtUtc == _unset
          ? this.lastVerifiedAtUtc
          : (lastVerifiedAtUtc as DateTime?)?.toUtc(),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'display_name': displayName,
    'base_url': baseUrl,
    'api_key_ref': apiKeyRef,
    'selected_model': selectedModel,
    'enabled': enabled,
    'connection_status': connectionStatus.name,
    'available_models': availableModels,
    'verified_models': verifiedModels,
    'incompatible_models': incompatibleModels,
    'created_at_utc': dateTimeToJson(createdAtUtc),
    'updated_at_utc': dateTimeToJson(updatedAtUtc),
    'last_verified_at_utc': lastVerifiedAtUtc == null
        ? null
        : dateTimeToJson(lastVerifiedAtUtc!),
  };

  factory AiProviderConfig.fromJson(Map<String, Object?> json) {
    const model = 'AiProviderConfig';
    try {
      final modelsValue = json['available_models'];
      if (modelsValue is! List) {
        throw const DataFormatException(
          'AiProviderConfig.available_models must be a list.',
        );
      }
      final models = modelsValue
          .map((value) {
            if (value is! String) {
              throw const DataFormatException(
                'AiProviderConfig.available_models must contain strings.',
              );
            }
            return value;
          })
          .toList(growable: false);
      final verifiedModels = _readOptionalStringList(json, 'verified_models');
      final incompatibleModels = _readOptionalStringList(
        json,
        'incompatible_models',
      );
      return AiProviderConfig(
        id: readRequiredString(json, 'id', model),
        type: AiProviderTypeValues.parse(
          readRequiredString(json, 'type', model),
        ),
        displayName: readRequiredString(json, 'display_name', model),
        baseUrl: readRequiredString(json, 'base_url', model),
        apiKeyRef: readRequiredString(json, 'api_key_ref', model),
        selectedModel: readRequiredString(json, 'selected_model', model),
        enabled: _readBool(json, 'enabled', model),
        connectionStatus: AiProviderConnectionStatus.values.firstWhere(
          (item) =>
              item.name == readRequiredString(json, 'connection_status', model),
        ),
        availableModels: List.unmodifiable(models),
        verifiedModels: List.unmodifiable(verifiedModels),
        incompatibleModels: List.unmodifiable(incompatibleModels),
        createdAtUtc: readRequiredDateTime(json, 'created_at_utc', model),
        updatedAtUtc: readRequiredDateTime(json, 'updated_at_utc', model),
        lastVerifiedAtUtc: readOptionalDateTime(
          json,
          'last_verified_at_utc',
          model,
        ),
      );
    } on DataFormatException {
      rethrow;
    } catch (_) {
      throw const DataFormatException(
        'AiProviderConfig contains invalid data.',
      );
    }
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AiProviderConfig &&
            id == other.id &&
            type == other.type &&
            displayName == other.displayName &&
            baseUrl == other.baseUrl &&
            apiKeyRef == other.apiKeyRef &&
            selectedModel == other.selectedModel &&
            enabled == other.enabled &&
            connectionStatus == other.connectionStatus &&
            _listEquals(availableModels, other.availableModels) &&
            _listEquals(verifiedModels, other.verifiedModels) &&
            _listEquals(incompatibleModels, other.incompatibleModels) &&
            createdAtUtc == other.createdAtUtc &&
            updatedAtUtc == other.updatedAtUtc &&
            lastVerifiedAtUtc == other.lastVerifiedAtUtc;
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    displayName,
    baseUrl,
    apiKeyRef,
    selectedModel,
    enabled,
    connectionStatus,
    Object.hashAll(availableModels),
    Object.hashAll(verifiedModels),
    Object.hashAll(incompatibleModels),
    createdAtUtc,
    updatedAtUtc,
    lastVerifiedAtUtc,
  );
}

class AiProviderCatalog {
  const AiProviderCatalog._();

  static List<AiProviderConfig> builtIns(DateTime nowUtc) {
    final now = nowUtc.toUtc();
    return AiProviderType.values
        .where((type) => type.isBuiltIn)
        .map(
          (type) => AiProviderConfig(
            id: type.name,
            type: type,
            displayName: type.displayName,
            baseUrl: type.defaultBaseUrl,
            apiKeyRef: 'ai.api_key.${type.name}',
            selectedModel: '',
            enabled: true,
            connectionStatus: AiProviderConnectionStatus.untested,
            availableModels: const [],
            verifiedModels: const [],
            incompatibleModels: const [],
            createdAtUtc: now,
            updatedAtUtc: now,
          ),
        )
        .toList(growable: false);
  }
}

const _unset = Object();

bool _readBool(Map<String, Object?> json, String key, String model) {
  final value = json[key];
  if (value is! bool) {
    throw DataFormatException('$model.$key must be a bool.');
  }
  return value;
}

List<String> _readOptionalStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List || value.any((item) => item is! String)) {
    throw DataFormatException('AiProviderConfig.$key must contain strings.');
  }
  return value.cast<String>();
}

bool _listEquals(List<String> first, List<String> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}
