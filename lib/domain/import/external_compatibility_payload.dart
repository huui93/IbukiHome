enum ExternalCompatibilitySourceType { sillyTavern }

class ExternalCompatibilityPayload {
  const ExternalCompatibilityPayload({
    required this.id,
    required this.sourceType,
    required this.sourceFormat,
    required this.sourceVersion,
    required this.sourceSha256,
    required this.linkedEntityType,
    required this.linkedEntityId,
    required this.normalizedPayload,
    required this.unsupportedPayload,
    required this.securityFlags,
    required this.importWarnings,
    required this.createdAt,
    this.metadata = const {},
  });

  final String id;
  final ExternalCompatibilitySourceType sourceType;
  final String sourceFormat;
  final String sourceVersion;
  final String sourceSha256;
  final String linkedEntityType;
  final String linkedEntityId;
  final Map<String, Object?> normalizedPayload;
  final Map<String, Object?> unsupportedPayload;
  final List<String> securityFlags;
  final List<String> importWarnings;
  final DateTime createdAt;
  final Map<String, Object?> metadata;

  bool get hasSecurityWarnings => securityFlags.isNotEmpty;

  ExternalCompatibilityPayload copyWith({
    String? id,
    ExternalCompatibilitySourceType? sourceType,
    String? sourceFormat,
    String? sourceVersion,
    String? sourceSha256,
    String? linkedEntityType,
    String? linkedEntityId,
    Map<String, Object?>? normalizedPayload,
    Map<String, Object?>? unsupportedPayload,
    List<String>? securityFlags,
    List<String>? importWarnings,
    DateTime? createdAt,
    Map<String, Object?>? metadata,
  }) {
    return ExternalCompatibilityPayload(
      id: id ?? this.id,
      sourceType: sourceType ?? this.sourceType,
      sourceFormat: sourceFormat ?? this.sourceFormat,
      sourceVersion: sourceVersion ?? this.sourceVersion,
      sourceSha256: sourceSha256 ?? this.sourceSha256,
      linkedEntityType: linkedEntityType ?? this.linkedEntityType,
      linkedEntityId: linkedEntityId ?? this.linkedEntityId,
      normalizedPayload: normalizedPayload ?? this.normalizedPayload,
      unsupportedPayload: unsupportedPayload ?? this.unsupportedPayload,
      securityFlags: securityFlags ?? this.securityFlags,
      importWarnings: importWarnings ?? this.importWarnings,
      createdAt: createdAt ?? this.createdAt,
      metadata: metadata ?? this.metadata,
    );
  }
}
