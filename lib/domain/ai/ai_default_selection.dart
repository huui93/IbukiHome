import '../../core/errors/data_exceptions.dart';
import '../common/entity_metadata.dart';

class AiDefaultSelection {
  const AiDefaultSelection({
    required this.providerId,
    required this.modelId,
    required this.updatedAtUtc,
  });

  final String providerId;
  final String modelId;
  final DateTime updatedAtUtc;

  Map<String, Object?> toJson() => {
    'provider_id': providerId,
    'model_id': modelId,
    'updated_at_utc': dateTimeToJson(updatedAtUtc),
  };

  factory AiDefaultSelection.fromJson(Map<String, Object?> json) {
    try {
      return AiDefaultSelection(
        providerId: readRequiredString(
          json,
          'provider_id',
          'AiDefaultSelection',
        ),
        modelId: readRequiredString(json, 'model_id', 'AiDefaultSelection'),
        updatedAtUtc: readRequiredDateTime(
          json,
          'updated_at_utc',
          'AiDefaultSelection',
        ),
      );
    } on DataFormatException {
      rethrow;
    } catch (_) {
      throw const DataFormatException(
        'AiDefaultSelection contains invalid data.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiDefaultSelection &&
          providerId == other.providerId &&
          modelId == other.modelId &&
          updatedAtUtc == other.updatedAtUtc;

  @override
  int get hashCode => Object.hash(providerId, modelId, updatedAtUtc);
}
