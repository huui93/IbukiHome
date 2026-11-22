enum CharacterReferenceSourceType { webEvidence, modelKnowledge }

class CharacterReferenceEvidence {
  const CharacterReferenceEvidence({
    required this.title,
    required this.sourceType,
    required this.summary,
    required this.confidence,
    this.sourceUrl,
  });

  final String title;
  final CharacterReferenceSourceType sourceType;
  final String? sourceUrl;
  final String summary;
  final double confidence;
}

abstract class CharacterReferenceLookupService {
  Future<List<CharacterReferenceEvidence>> lookup({
    required String workTitle,
    required String characterName,
    required String versionHint,
  });
}

/// The mobile app does not currently ship a web-reference transport.
/// Keeping this boundary explicit prevents model knowledge being presented as
/// verified web evidence and allows a real source to be plugged in later.
class NoopCharacterReferenceLookupService
    implements CharacterReferenceLookupService {
  const NoopCharacterReferenceLookupService();

  @override
  Future<List<CharacterReferenceEvidence>> lookup({
    required String workTitle,
    required String characterName,
    required String versionHint,
  }) async => const [];
}
