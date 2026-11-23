import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ibukihome/application/projects/txt_novel_providers.dart';
import 'package:ibukihome/application/projects/txt_novel_source.dart';
import 'package:ibukihome/application/projects/novel_prompt_presets.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/data/cache/cached_repositories.dart';
import 'package:ibukihome/data/sqlite/sqlite_novel_import_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_novel_prompt_preset_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_backup_snapshot_store.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/projects/novel_prompt_preset.dart';
import 'package:ibukihome/domain/segments/segment.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';
import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);
  test(
    'TXT import commits text and synchronizes a primed project cache',
    () async {
      final f = await SqliteFixture.create();
      final projects = CachedProjectRepository(f.projects);
      final segments = CachedSegmentRepository(f.segments);
      expect(await projects.listProjects(), isEmpty);
      final c = ProviderContainer(
        overrides: [
          projectRepositoryProvider.overrideWithValue(projects),
          segmentRepositoryProvider.overrideWithValue(segments),
          novelImportRepositoryProvider.overrideWithValue(
            SQLiteNovelImportRepository(f.database),
          ),
        ],
      );
      addTearDown(c.dispose);
      final parsed = prepareTxtNovel((
        fileName: '导入.txt',
        text: '正文\n' * 5000,
        encoding: 'UTF-8',
      ));
      final project = await c.read(importTxtNovelProvider)(
        parsed,
        parsed.title,
      );
      expect((await projects.listProjects()).single.id, project.id);
      expect(
        (await segments.listSegments(project.id)).map((s) => s.content).join(),
        parsed.parts.join(),
      );
      await f.database.close();
      final reopened = await reopenFixture(f);
      expect(
        (await reopened.segments.listSegments(
          project.id,
        )).map((s) => s.content).join(),
        parsed.parts.join(),
      );
    },
  );
  test('a text insert failure rolls back the entire new project', () async {
    final f = await SqliteFixture.create();
    await f.projects.upsertProject(
      Project(
        metadata: metadata('old'),
        title: '旧作品',
        description: '',
        systemPrompt: '旧提示词',
      ),
    );
    await f.segments.upsertSegment(
      Segment(
        metadata: metadata('occupied'),
        projectId: 'old',
        orderIndex: 0,
        content: '旧正文',
      ),
    );
    final repo = SQLiteNovelImportRepository(f.database);
    await expectLater(
      repo.insertNovel(
        Project(metadata: metadata('new'), title: '新小说', description: ''),
        [
          Segment(
            metadata: metadata('first'),
            projectId: 'new',
            orderIndex: 0,
            content: '第一段',
          ),
          Segment(
            metadata: metadata('occupied'),
            projectId: 'new',
            orderIndex: 1,
            content: '第二段',
          ),
        ],
      ),
      throwsA(isA<Exception>()),
    );
    expect((await f.projects.listProjects()).map((p) => p.id), ['old']);
    expect(await f.segments.listSegments('new'), isEmpty);
    expect((await f.segments.getSegment('occupied')).content, '旧正文');
  });
  test(
    'v16 upgrade adds the preset library and keeps every old story setting',
    () async {
      final f = await SqliteFixture.create();
      await f.projects.upsertProject(
        Project(
          metadata: metadata('old'),
          title: '旧小说',
          description: '',
          systemPrompt: '既有提示词',
        ),
      );
      final db = await f.database.database;
      await db.execute('DROP TABLE novel_prompt_presets');
      await db.setVersion(16);
      await f.database.close();
      final reopened = await reopenFixture(f);
      expect(await (await reopened.database.database).getVersion(), 22);
      expect((await reopened.projects.getProject('old')).systemPrompt, '既有提示词');
      expect(
        await SQLiteNovelPromptPresetRepository(reopened.database).list(),
        isEmpty,
      );
    },
  );
  test(
    'preset edits use revision checks and never change novels already using a copy',
    () async {
      final f = await SqliteFixture.create();
      final c = ProviderContainer(
        overrides: [
          projectRepositoryProvider.overrideWithValue(f.projects),
          novelPromptPresetRepositoryProvider.overrideWithValue(
            SQLiteNovelPromptPresetRepository(f.database),
          ),
        ],
      );
      addTearDown(c.dispose);
      final service = c.read(novelPromptPresetServiceProvider);
      final preset = await service.save(name: '叙事方案', content: '第一版');
      for (final id in ['one', 'two']) {
        await f.projects.upsertProject(
          Project(
            metadata: metadata(id),
            title: id,
            description: '',
            systemPrompt: preset.content,
          ),
        );
      }
      final updated = await service.save(
        name: '新方案',
        content: '第二版',
        previous: preset,
      );
      await expectLater(
        service.save(name: '冲突', content: '覆盖', previous: preset),
        throwsA(isA<Exception>()),
      );
      expect((await f.projects.getProject('one')).systemPrompt, '第一版');
      expect((await f.projects.getProject('two')).systemPrompt, '第一版');
      await service.delete(updated);
      expect(await c.read(novelPromptPresetRepositoryProvider).list(), isEmpty);
      expect((await f.projects.getProject('one')).systemPrompt, '第一版');
    },
  );
  test(
    'prompt library and imported novels survive backup merge including ID collisions',
    () async {
      final source = await SqliteFixture.create();
      final target = await SqliteFixture.create();
      final preset = NovelPromptPreset(
        metadata: metadata('preset'),
        name: '简洁叙事',
        content: '短句',
      );
      await SQLiteNovelPromptPresetRepository(source.database).save(preset);
      await SQLiteNovelImportRepository(source.database).insertNovel(
        Project(
          metadata: metadata('book'),
          title: '导入作品',
          description: '',
          systemPrompt: '本作要求',
        ),
        [
          Segment(
            metadata: metadata('text'),
            projectId: 'book',
            orderIndex: 0,
            content: '完整正文',
          ),
        ],
      );
      final snapshot = await SQLiteBackupSnapshotStore(
        source.database,
      ).buildSnapshot();
      final store = SQLiteBackupSnapshotStore(target.database);
      await store.restore(
        snapshot,
        mode: BackupRestoreMode.fresh,
        restoredAssets: {},
      );
      await store.restore(
        snapshot,
        mode: BackupRestoreMode.merge,
        restoredAssets: {},
      );
      expect(
        await SQLiteNovelPromptPresetRepository(target.database).list(),
        hasLength(2),
      );
      expect(await target.projects.listProjects(), hasLength(2));
      for (final project in await target.projects.listProjects()) {
        expect(project.systemPrompt, '本作要求');
        expect(
          (await target.segments.listSegments(project.id)).single.content,
          '完整正文',
        );
      }
    },
  );
}
