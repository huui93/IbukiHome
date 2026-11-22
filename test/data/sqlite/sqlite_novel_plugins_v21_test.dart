import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ibukihome/application/segments/save_segment.dart';
import 'package:ibukihome/data/sqlite/sqlite_novel_plugin_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_backup_snapshot_store.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);
  final now = DateTime.utc(2026, 11, 22);
  Future<SqliteFixture> fixture() async {
    final f = await SqliteFixture.create();
    for (final id in ['story', 'other']) {
      await f.projects.upsertProject(
        Project(
          metadata: metadata(id),
          title: id,
          description: '场景',
          systemPrompt: '本作设定',
        ),
      );
    }
    await f.segments.upsertSegment(segment('s0', 'story', 0, content: '最初的开头'));
    await f.segments.upsertSegment(segment('s1', 'story', 1, content: '第二段'));
    await f.characters.upsertCharacter(characterCard('char', 'story', 0));
    await f.world.upsertWorldCard(worldCard('world', 'story', 0));
    return f;
  }

  test(
    'v20 migration preserves existing manuscript and lazily establishes a root story',
    () async {
      final f = await fixture();
      final db = await f.database.database;
      for (final table in [
        'novel_plugin_reply_views',
        'novel_plugin_selections',
        'novel_plugin_candidates',
        'novel_segment_origins',
        'novel_active_branches',
        'novel_story_branches',
      ]) {
        await db.execute('DROP TABLE $table');
      }
      await db.setVersion(20);
      await f.database.close();
      final reopened = await reopenFixture(f);
      expect(await (await reopened.database.database).getVersion(), 21);
      final repo = SQLiteNovelPluginRepository(reopened.database);
      final before = await reopened.segments.listSegments('story');
      final h = await repo.history('story');
      expect(h.map((m) => m.id), ['s0', 's1']);
      expect(h.first.candidates.length, 1);
      expect(await reopened.segments.listSegments('story'), before);
      expect((await repo.branch('story')).storyId, 'story');
    },
  );
  test(
    'fork freezes the selected candidate and retains stable inherited message/candidate IDs',
    () async {
      final f = await fixture();
      final repo = SQLiteNovelPluginRepository(f.database);
      final original = (await repo.history('story')).first;
      await SaveSegment(f.segments)(
        currentSegment: await f.segments.getSegment('s0'),
        newContent: '另一个开头',
        now: now,
        revisionId: 'revision',
        mode: 'ai_rewrite',
      );
      final changed = (await repo.history('story')).first;
      expect(changed.candidates.length, 2);
      await repo.selectCandidate(
        projectId: 'story',
        messageId: 's0',
        candidateId: original.candidateId,
        now: now,
      );
      final branch = await repo.fork(
        projectId: 'story',
        newProjectId: 'fork',
        label: '试写',
        atMessageId: 's0',
        now: now,
      );
      expect(branch.parentId, 'story');
      expect(branch.inheritSettings, isTrue);
      final inherited = (await repo.history('fork')).single;
      expect(inherited.id, original.id);
      expect(inherited.candidateId, original.candidateId);
      expect(inherited.segmentId, isNot('s0'));
      expect(inherited.candidates.length, 1);
      await repo.selectCandidate(
        projectId: 'story',
        messageId: 's0',
        candidateId: changed.candidateId,
        now: now,
      );
      expect((await repo.history('fork')).single.content, '最初的开头');
      expect((await repo.history('story')).first.content, '另一个开头');
      expect(await f.characters.listCharacters('fork'), hasLength(1));
      expect(await f.world.listWorldCards('fork'), hasLength(1));
      expect(await repo.activeProject('story'), 'fork');
      expect(await repo.childProjectIds(), {'fork'});
    },
  );
  test(
    'fork conflicts roll back all cloned records and settings use optimistic revisions',
    () async {
      final f = await fixture();
      final repo = SQLiteNovelPluginRepository(f.database);
      await repo.branch('story');
      await expectLater(
        repo.fork(
          projectId: 'story',
          newProjectId: 'other',
          label: '冲突',
          now: now,
        ),
        throwsException,
      );
      expect(await repo.branches('story'), hasLength(1));
      expect(await f.segments.listSegments('other'), isEmpty);
      final child = await repo.fork(
        projectId: 'story',
        newProjectId: 'fork',
        label: '分支',
        now: now,
      );
      await repo.setInheritance('fork', false, child.revision);
      await expectLater(
        repo.setInheritance('fork', true, child.revision),
        throwsException,
      );
      expect((await repo.branch('fork')).inheritSettings, isFalse);
      await expectLater(repo.selectBranch('other', 'fork'), throwsException);
      await expectLater(
        repo.selectCandidate(
          projectId: 'other',
          messageId: 's0',
          candidateId: (await repo.history('story')).first.candidateId,
          now: now,
        ),
        throwsException,
      );
    },
  );
  test(
    'only the current latest exact reply can close a branch, closure survives edits and reopening',
    () async {
      final f = await fixture();
      var repo = SQLiteNovelPluginRepository(f.database);
      final current = (await repo.history('story')).last;
      await expectLater(
        repo.endBranch(
          projectId: 'story',
          pluginId: 'nvwa',
          segmentId: 's0',
          revision: 1,
          contentHash: novelContentHash('最初的开头'),
          reason: '旧回复',
        ),
        throwsException,
      );
      await expectLater(
        repo.endBranch(
          projectId: 'story',
          pluginId: 'nvwa',
          segmentId: 's1',
          revision: 1,
          contentHash: novelContentHash('不匹配'),
          reason: '不匹配',
        ),
        throwsException,
      );
      await repo.endBranch(
        projectId: 'story',
        pluginId: 'nvwa',
        segmentId: current.segmentId,
        revision: current.revision,
        contentHash: novelContentHash(current.content),
        reason: '本故事线结束',
      );
      await f.segments.softDeleteSegment('s1', now);
      await f.database.close();
      final again = await reopenFixture(f);
      repo = SQLiteNovelPluginRepository(again.database);
      expect((await repo.branch('story')).ended, isTrue);
      await expectLater(
        repo.selectCandidate(
          projectId: 'story',
          messageId: 's0',
          candidateId: (await repo.history('story')).first.candidateId,
          now: now,
        ),
        throwsException,
      );
      expect(
        (await repo.fork(
          projectId: 'story',
          newProjectId: 'new-story-line',
          label: '另开故事线',
          now: now,
        )).ended,
        isFalse,
      );
    },
  );
  test(
    'fresh restore and conflict merge preserve branch ownership, selected answers and origins',
    () async {
      final f = await fixture();
      final repo = SQLiteNovelPluginRepository(f.database);
      await repo.fork(
        projectId: 'story',
        newProjectId: 'fork',
        label: '分叉',
        atMessageId: 's0',
        now: now,
      );
      final store = SQLiteBackupSnapshotStore(f.database);
      final snapshot = await store.buildSnapshot();
      final empty = await SqliteFixture.create();
      await SQLiteBackupSnapshotStore(
        empty.database,
      ).restore(snapshot, mode: BackupRestoreMode.fresh, restoredAssets: {});
      expect(
        (await SQLiteNovelPluginRepository(
          empty.database,
        ).history('fork')).single.content,
        '最初的开头',
      );
      await store.restore(
        snapshot,
        mode: BackupRestoreMode.merge,
        restoredAssets: {},
      );
      final db = await f.database.database;
      final root = (await db.query(
        'projects',
        where: "title='story' AND id NOT IN ('story','fork')",
      )).where((p) => (p['id'] as String).isNotEmpty).toList();
      final copiedRoots = <String>[];
      for (final p in root) {
        final b = await repo.branch(p['id'] as String);
        if (b.projectId == b.storyId) copiedRoots.add(b.storyId);
      }
      expect(copiedRoots, hasLength(1));
      final copiedBranch = (await repo.branches(
        copiedRoots.single,
      )).singleWhere((b) => b.parentId != null);
      final copiedMessage = (await repo.history(copiedBranch.projectId)).single;
      expect(copiedMessage.id, isNot('s0'));
      expect(copiedMessage.content, '最初的开头');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'render data is bound to canonical text and deleting a work removes its branches only',
    () async {
      final f = await fixture();
      final repo = SQLiteNovelPluginRepository(f.database);
      final hash = novelContentHash('最初的开头');
      await repo.saveReplyView('s0', hash, {'timeBar': '午后'});
      expect((await repo.replyView('s0', hash))!['timeBar'], '午后');
      expect(await repo.replyView('s0', 'changed'), isNull);
      await expectLater(
        repo.saveReplyView('s0', 'changed', {'timeBar': '旧状态'}),
        throwsException,
      );
      await repo.fork(
        projectId: 'story',
        newProjectId: 'fork',
        label: '分支',
        now: now,
      );
      await repo.deleteStory('fork', now);
      expect((await f.projects.getProject('story')).deletedAt, isNotNull);
      expect((await f.projects.getProject('fork')).deletedAt, isNotNull);
      expect((await f.projects.getProject('other')).deletedAt, isNull);
      final previous = await f.segments.getSegment('s0');
      await expectLater(
        f.segments.upsertSegment(
          segment('late-generation', 'story', 2, content: '迟到的生成'),
        ),
        throwsException,
      );
      await expectLater(
        SaveSegment(f.segments)(
          currentSegment: previous,
          newContent: '迟到的重写',
          now: now,
          revisionId: 'late-revision',
        ),
        throwsException,
      );
      expect((await f.segments.getSegment('s0')).content, previous.content);
      expect(await f.segments.listRevisions('s0'), isEmpty);
    },
  );
}
