import 'package:sqflite/sqflite.dart';
import '../../core/errors/data_exceptions.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/projects/novel_prompt_preset.dart';
import '../repositories/novel_prompt_preset_repository.dart';
import 'ibuki_database.dart';
import 'sqlite_repository_helpers.dart';

class SQLiteNovelPromptPresetRepository implements NovelPromptPresetRepository {
  const SQLiteNovelPromptPresetRepository(this.database);
  final IbukiDatabase database;
  @override
  Future<List<NovelPromptPreset>> list() async {
    final db = await database.database;
    final rows = await db.query(
      'novel_prompt_presets',
      where: 'deleted_at IS NULL',
      orderBy: 'updated_at DESC, id ASC',
    );
    return List.unmodifiable(
      rows.map(
        (row) => NovelPromptPreset(
          metadata: EntityMetadata.fromJson(
            row,
            modelName: 'NovelPromptPreset',
          ),
          name: row['name']! as String,
          content: row['content']! as String,
        ),
      ),
    );
  }

  @override
  Future<void> save(NovelPromptPreset preset) async {
    final db = await database.database;
    final values = {
      ...preset.metadata.toJson(),
      'name': preset.name,
      'content': preset.content,
    };
    await handleSqliteWrite(
      () async {
        if (preset.metadata.revision == 1) {
          await db.insert(
            'novel_prompt_presets',
            values,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        } else {
          final updated = await db.update(
            'novel_prompt_presets',
            values,
            where: 'id = ? AND revision = ? AND deleted_at IS NULL',
            whereArgs: [preset.id, preset.metadata.revision - 1],
          );
          if (updated != 1) {
            throw const DataConflictException('方案已改变，请重新打开后编辑。');
          }
        }
      },
      entityName: 'NovelPromptPreset',
      entityId: preset.id,
    );
  }
}
