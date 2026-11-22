import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ibukihome/data/sqlite/sqlite_novel_output_limits_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_backup_snapshot_store.dart';
import 'package:ibukihome/domain/projects/novel_output_limits.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';
import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);
  Future<SqliteFixture> fixture() async {
    final f = await SqliteFixture.create();
    for (final id in ['a', 'b']) {
      await f.projects.upsertProject(
        Project(
          metadata: metadata(id),
          title: id,
          description: 'old content',
          systemPrompt: 'old prompt',
        ),
      );
    }
    return f;
  }

  test(
    'v18 migration preserves old stories and defaults, limits survive reopening independently',
    () async {
      final f = await fixture();
      final original = await f.projects.getProject('a');
      final db = await f.database.database;
      await db.execute('DROP TABLE novel_output_settings');
      await db.setVersion(18);
      await f.database.close();
      final reopened = await reopenFixture(f);
      final repo = SQLiteNovelOutputLimitsRepository(reopened.database);
      expect(await (await reopened.database.database).getVersion(), 21);
      expect(await reopened.projects.getProject('a'), original);
      expect((await repo.get('a')).isDefault, isTrue);
      await repo.save(
        const NovelOutputLimits(projectId: 'a', minimum: 100, maximum: 300),
        expectedRevision: 0,
        now: DateTime.utc(2026),
      );
      expect((await repo.get('b')).isDefault, isTrue);
      await reopened.database.close();
      final again = await reopenFixture(reopened);
      final saved = await SQLiteNovelOutputLimitsRepository(
        again.database,
      ).get('a');
      expect(saved.minimum, 100);
      expect(saved.maximum, 300);
      expect(saved.revision, 1);
    },
  );
  test(
    'invalid values and stale edits cannot overwrite settings, default clears both sides',
    () async {
      final f = await fixture();
      final repo = SQLiteNovelOutputLimitsRepository(f.database);
      final now = DateTime.utc(2026);
      final first = await repo.save(
        const NovelOutputLimits(projectId: 'a', maximum: 500),
        expectedRevision: 0,
        now: now,
      );
      await expectLater(
        repo.save(
          const NovelOutputLimits(projectId: 'a', minimum: 600, maximum: 500),
          expectedRevision: 1,
          now: now,
        ),
        throwsException,
      );
      await expectLater(
        repo.save(
          const NovelOutputLimits(projectId: 'a', minimum: 0),
          expectedRevision: 1,
          now: now,
        ),
        throwsException,
      );
      await expectLater(
        repo.save(
          const NovelOutputLimits(projectId: 'a', maximum: 200),
          expectedRevision: 0,
          now: now,
        ),
        throwsException,
      );
      expect((await repo.get('a')).maximum, 500);
      final cleared = await repo.save(
        const NovelOutputLimits(projectId: 'a'),
        expectedRevision: first.revision,
        now: now,
      );
      expect(cleared.isDefault, isTrue);
      expect(
        await (await f.database.database).query('novel_output_settings'),
        isEmpty,
      );
      await f.projects.softDeleteProject('a', now);
      await expectLater(
        repo.save(
          const NovelOutputLimits(projectId: 'a', maximum: 10),
          expectedRevision: 0,
          now: now,
        ),
        throwsException,
      );
    },
  );
  test(
    'logical backup merge remaps output limits to the copied story',
    () async {
      final f = await fixture();
      final repo = SQLiteNovelOutputLimitsRepository(f.database);
      await repo.save(
        const NovelOutputLimits(projectId: 'a', minimum: 80, maximum: 120),
        expectedRevision: 0,
        now: DateTime.utc(2026),
      );
      final store = SQLiteBackupSnapshotStore(f.database);
      final snapshot = await store.buildSnapshot();
      expect(snapshot.collections['novelOutputSettings'], hasLength(1));
      await store.restore(
        snapshot,
        mode: BackupRestoreMode.merge,
        restoredAssets: {},
      );
      final copy = (await f.projects.listProjects())
          .where((p) => p.id != 'a' && p.title == 'a')
          .single;
      expect((await repo.get(copy.id)).minimum, 80);
      expect((await repo.get('a')).maximum, 120);
      expect((await repo.get('b')).isDefault, isTrue);
      expect(
        await (await f.database.database).rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
    },
  );
  test('word targets retain defaults and model limits outrank the minimum', () {
    const empty = NovelOutputLimits(projectId: 'a');
    expect(empty.promptSuffix, '');
    expect(empty.label, '默认');
    const minimum = NovelOutputLimits(projectId: 'a', minimum: 1000000);
    expect(minimum.label, '至少 1000000 字');
    expect(minimum.promptSuffix, contains('实际允许的输出上限始终优先'));
    const maximum = NovelOutputLimits(projectId: 'b', maximum: 200);
    expect(maximum.label, '最多 200 字');
  });
}
