import '../../data/repositories/compatibility_import_repository.dart';

class SillyTavernCharacterContext {
  const SillyTavernCharacterContext({
    this.systemPrompt = '',
    this.postHistoryInstructions = '',
    this.exampleMessages = '',
    this.firstMessage = '',
  });

  final String systemPrompt;
  final String postHistoryInstructions;
  final String exampleMessages;
  final String firstMessage;

  bool get isEmpty =>
      systemPrompt.isEmpty &&
      postHistoryInstructions.isEmpty &&
      exampleMessages.isEmpty &&
      firstMessage.isEmpty;
}

class SillyTavernCharacterContextResolver {
  const SillyTavernCharacterContextResolver(this.repository);

  final CompatibilityImportRepository repository;

  Future<SillyTavernCharacterContext> resolve(String characterCardId) async {
    final payloads = await repository.listForEntity(
      'characterCard',
      characterCardId,
    );
    if (payloads.isEmpty) return const SillyTavernCharacterContext();
    final payload = payloads.first.normalizedPayload;
    return SillyTavernCharacterContext(
      systemPrompt: _string(payload['systemPrompt']),
      postHistoryInstructions: _string(payload['postHistoryInstructions']),
      exampleMessages: _string(payload['exampleMessages']),
      firstMessage: _string(payload['firstMessage']),
    );
  }

  String _string(Object? value) => value is String ? value.trim() : '';
}
