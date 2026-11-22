import '../../application/import/sillytavern_import_plan.dart';
import '../../domain/import/external_compatibility_payload.dart';

abstract class CompatibilityImportRepository {
  Future<List<ExternalCompatibilityPayload>> listPayloads();

  Future<ExternalCompatibilityPayload> getPayload(String id);

  Future<List<ExternalCompatibilityPayload>> findBySourceSha256(String sha256);

  Future<List<ExternalCompatibilityPayload>> listForEntity(
    String linkedEntityType,
    String linkedEntityId,
  );

  Future<void> commitImport(SillyTavernImportWrite write);

  Future<void> deletePayload(String id);
}
