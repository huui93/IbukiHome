import '../../domain/ai/ai_default_selection.dart';
import '../../domain/ai/ai_provider_config.dart';

abstract class AiProviderConfigRepository {
  Future<List<AiProviderConfig>> listConfigs();

  Future<AiProviderConfig?> getConfig(String id);

  Future<void> saveConfig(AiProviderConfig config);

  Future<void> deleteConfig(String id);

  Future<AiDefaultSelection?> loadDefault();

  Future<void> saveDefault(AiDefaultSelection selection);

  Future<void> clearDefault();
}
