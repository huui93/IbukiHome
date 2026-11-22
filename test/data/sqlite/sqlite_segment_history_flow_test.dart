import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/segments/insert_segment.dart';
import 'package:ibukihome/application/segments/reorder_segments.dart';
import 'package:ibukihome/application/segments/restore_segment.dart';
import 'package:ibukihome/application/segments/restore_segment_revision.dart';
import 'package:ibukihome/application/segments/save_segment.dart';
import 'package:ibukihome/application/segments/soft_delete_segment.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/data/repositories/segment_repository.dart';

import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  group('SQLite segment insertion and ordering transactions', () {
    test('inserts before an anchor and shifts later segments', () async {
      final f = await _Fixture.create(count: 3);
      final inserted = await f.insert(
        projectId: 'project-1',
        anchorSegmentId: 'segment-1',
        position: SegmentInsertPosition.before,
        content: 'inserted',
        id: 'inserted',
        nowUtc: _t(2),
      );
      expect(inserted.orderIndex, 1);
      expect(await f.activeIds(), [
        'segment-0',
        'inserted',
        'segment-1',
        'segment-2',
      ]);
    });

    test('inserts after an anchor', () async {
      final f = await _Fixture.create(count: 3);
      await f.insert(
        projectId: 'project-1',
        anchorSegmentId: 'segment-1',
        position: SegmentInsertPosition.after,
        content: 'inserted',
        id: 'inserted',
        nowUtc: _t(2),
      );
      expect(await f.activeIds(), [
        'segment-0',
        'segment-1',
        'inserted',
        'segment-2',
      ]);
    });

    test('insert keeps order indexes continuous', () async {
      final f = await _Fixture.create(count: 4);
      await f.insert(
        projectId: 'project-1',
        anchorSegmentId: 'segment-2',
        position: SegmentInsertPosition.before,
        content: '',
        id: 'inserted',
        nowUtc: _t(2),
      );
      expect(
        (await f.fixture.segments.listSegments(
          'project-1',
        )).map((e) => e.orderIndex),
        [0, 1, 2, 3, 4],
      );
    });

    test('insert failure rolls back shifted indexes', () async {
      final f = await _Fixture.create(count: 3);
      final db = await f.fixture.database.database;
      await db.execute('''
CREATE TRIGGER fail_inserted_segment
BEFORE INSERT ON segments
WHEN NEW.id = 'inserted'
BEGIN
  SELECT RAISE(ABORT, 'forced insert failure');
END
''');
      expect(
        f.insert(
          projectId: 'project-1',
          anchorSegmentId: 'segment-1',
          position: SegmentInsertPosition.before,
          content: '',
          id: 'inserted',
          nowUtc: _t(2),
        ),
        throwsA(isA<DataConflictException>()),
      );
      expect(await f.activeIds(), ['segment-0', 'segment-1', 'segment-2']);
      expect(
        (await f.fixture.segments.listSegments(
          'project-1',
        )).map((e) => e.orderIndex),
        [0, 1, 2],
      );
    });

    test('duplicate insert id does not shift indexes', () async {
      final f = await _Fixture.create(count: 3);
      expect(
        f.insert(
          projectId: 'project-1',
          anchorSegmentId: 'segment-1',
          position: SegmentInsertPosition.before,
          content: '',
          id: 'segment-2',
          nowUtc: _t(2),
        ),
        throwsA(isA<DuplicateEntityException>()),
      );
      expect(await f.activeIds(), ['segment-0', 'segment-1', 'segment-2']);
    });

    test('reorder persists exact order and continuous indexes', () async {
      final f = await _Fixture.create(count: 3);
      await f.reorder(
        projectId: 'project-1',
        orderedIds: ['segment-2', 'segment-0', 'segment-1'],
        updatedAt: _t(2),
      );
      expect(await f.activeIds(), ['segment-2', 'segment-0', 'segment-1']);
      expect(
        (await f.fixture.segments.listSegments(
          'project-1',
        )).map((e) => e.orderIndex),
        [0, 1, 2],
      );
    });

    test('reorder changes revisions but creates no content history', () async {
      final f = await _Fixture.create(count: 2);
      await f.reorder(
        projectId: 'project-1',
        orderedIds: ['segment-1', 'segment-0'],
        updatedAt: _t(2),
      );
      expect((await f.fixture.segments.getSegment('segment-1')).revision, 2);
      expect(await f.fixture.segments.listRevisions('segment-1'), isEmpty);
    });

    test('invalid reorder leaves all rows unchanged', () async {
      final f = await _Fixture.create(count: 2);
      expect(
        f.reorder(
          projectId: 'project-1',
          orderedIds: ['segment-0', 'segment-0'],
          updatedAt: _t(2),
        ),
        throwsA(isA<DataConflictException>()),
      );
      expect(await f.activeIds(), ['segment-0', 'segment-1']);
    });

    test('reorder update failure rolls back the whole transaction', () async {
      final f = await _Fixture.create(count: 3);
      final db = await f.fixture.database.database;
      await db.execute('''
CREATE TRIGGER fail_segment_reorder
BEFORE UPDATE ON segments
WHEN OLD.id = 'segment-0' AND NEW.order_index <> OLD.order_index
BEGIN
  SELECT RAISE(ABORT, 'forced reorder failure');
END
''');
      expect(
        f.reorder(
          projectId: 'project-1',
          orderedIds: ['segment-2', 'segment-1', 'segment-0'],
          updatedAt: _t(2),
        ),
        throwsA(isA<DataConflictException>()),
      );
      expect(await f.activeIds(), ['segment-0', 'segment-1', 'segment-2']);
    });
  });

  group('SQLite segment delete and restore transactions', () {
    test('soft delete normalizes remaining order', () async {
      final f = await _Fixture.create(count: 4);
      await f.softDelete(
        projectId: 'project-1',
        segmentId: 'segment-1',
        deletedAt: _t(2),
      );
      expect(await f.activeIds(), ['segment-0', 'segment-2', 'segment-3']);
      expect(
        (await f.fixture.segments.listSegments(
          'project-1',
        )).map((e) => e.orderIndex),
        [0, 1, 2],
      );
    });

    test('soft delete keeps segment history', () async {
      final f = await _Fixture.create(count: 1);
      final original = await f.fixture.segments.getSegment('segment-0');
      await f.save(
        currentSegment: original,
        newContent: 'new',
        now: _t(2),
        revisionId: 'revision-1',
      );
      await f.softDelete(
        projectId: 'project-1',
        segmentId: 'segment-0',
        deletedAt: _t(3),
      );
      expect(await f.fixture.segments.listRevisions('segment-0'), hasLength(1));
    });

    test('repeated soft delete does not add a revision', () async {
      final f = await _Fixture.create(count: 1);
      final first = await f.softDelete(
        projectId: 'project-1',
        segmentId: 'segment-0',
        deletedAt: _t(2),
      );
      final second = await f.softDelete(
        projectId: 'project-1',
        segmentId: 'segment-0',
        deletedAt: _t(3),
      );
      expect(second.revision, first.revision);
      expect(second.deletedAt, first.deletedAt);
    });

    test('delete update failure rolls back order normalization', () async {
      final f = await _Fixture.create(count: 3);
      final db = await f.fixture.database.database;
      await db.execute('''
CREATE TRIGGER fail_segment_delete
BEFORE UPDATE ON segments
WHEN OLD.id = 'segment-1' AND NEW.deleted_at IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'forced delete failure');
END
''');
      expect(
        f.softDelete(
          projectId: 'project-1',
          segmentId: 'segment-1',
          deletedAt: _t(2),
        ),
        throwsA(isA<DataConflictException>()),
      );
      expect(await f.activeIds(), ['segment-0', 'segment-1', 'segment-2']);
    });

    test('restore reinserts at the former position', () async {
      final f = await _Fixture.create(count: 3);
      await f.softDelete(
        projectId: 'project-1',
        segmentId: 'segment-1',
        deletedAt: _t(2),
      );
      await f.restore(
        projectId: 'project-1',
        segmentId: 'segment-1',
        restoredAt: _t(3),
      );
      expect(await f.activeIds(), ['segment-0', 'segment-1', 'segment-2']);
    });

    test('restore clamps a former position beyond the active end', () async {
      final f = await _Fixture.create(count: 1);
      await f.fixture.segments.upsertSegment(
        segment('deleted', 'project-1', 40).copyWith(
          metadata: metadata(
            'deleted',
            updatedAt: _t(2),
            revision: 2,
            deletedAt: _t(2),
          ),
        ),
      );
      final restored = await f.restore(
        projectId: 'project-1',
        segmentId: 'deleted',
        restoredAt: _t(3),
      );
      expect(restored.orderIndex, 1);
    });

    test('repeated restore does not add a revision', () async {
      final f = await _Fixture.create(count: 1);
      await f.softDelete(
        projectId: 'project-1',
        segmentId: 'segment-0',
        deletedAt: _t(2),
      );
      final first = await f.restore(
        projectId: 'project-1',
        segmentId: 'segment-0',
        restoredAt: _t(3),
      );
      final second = await f.restore(
        projectId: 'project-1',
        segmentId: 'segment-0',
        restoredAt: _t(4),
      );
      expect(second.revision, first.revision);
    });

    test('restore update failure rolls back shifted peers', () async {
      final f = await _Fixture.create(count: 3);
      await f.softDelete(
        projectId: 'project-1',
        segmentId: 'segment-1',
        deletedAt: _t(2),
      );
      final db = await f.fixture.database.database;
      await db.execute('''
CREATE TRIGGER fail_segment_restore
BEFORE UPDATE ON segments
WHEN OLD.id = 'segment-1' AND NEW.deleted_at IS NULL
BEGIN
  SELECT RAISE(ABORT, 'forced restore failure');
END
''');
      expect(
        f.restore(
          projectId: 'project-1',
          segmentId: 'segment-1',
          restoredAt: _t(3),
        ),
        throwsA(isA<DataConflictException>()),
      );
      expect(await f.activeIds(), ['segment-0', 'segment-2']);
      expect(
        (await f.fixture.segments.getSegment('segment-1')).deletedAt,
        isNotNull,
      );
    });

    test('delete state and order persist after database reopen', () async {
      final f = await _Fixture.create(count: 3);
      await f.softDelete(
        projectId: 'project-1',
        segmentId: 'segment-1',
        deletedAt: _t(2),
      );
      await f.fixture.database.close();
      final reopened = await reopenFixture(f.fixture);
      expect(
        (await reopened.segments.listSegments('project-1')).map((e) => e.id),
        ['segment-0', 'segment-2'],
      );
      expect(
        (await reopened.segments.getSegment('segment-1')).deletedAt,
        isNotNull,
      );
    });
  });

  group('SQLite historical restoration transaction', () {
    test('restores content and stores the previous current version', () async {
      final f = await _Fixture.create(count: 1);
      final second = await f.save(
        currentSegment: await f.fixture.segments.getSegment('segment-0'),
        newContent: 'v2',
        now: _t(2),
        revisionId: 'revision-1',
      );
      final restored = await f.restoreRevision(
        projectId: 'project-1',
        segmentId: second.id,
        segmentRevisionId: 'revision-1',
        newRevisionId: 'rollback-1',
        nowUtc: _t(3),
      );
      expect(restored.content, 'segment-0');
      expect(
        (await f.fixture.segments.getRevision('rollback-1')).content,
        'v2',
      );
    });

    test('revision id conflict rolls back current content', () async {
      final f = await _Fixture.create(count: 1);
      final second = await f.save(
        currentSegment: await f.fixture.segments.getSegment('segment-0'),
        newContent: 'v2',
        now: _t(2),
        revisionId: 'revision-1',
      );
      expect(
        f.restoreRevision(
          projectId: 'project-1',
          segmentId: second.id,
          segmentRevisionId: 'revision-1',
          newRevisionId: 'revision-1',
          nowUtc: _t(3),
        ),
        throwsA(isA<DuplicateEntityException>()),
      );
      expect((await f.fixture.segments.getSegment(second.id)).content, 'v2');
    });

    test('segment update failure removes the new rollback revision', () async {
      final f = await _Fixture.create(count: 1);
      final second = await f.save(
        currentSegment: await f.fixture.segments.getSegment('segment-0'),
        newContent: 'v2',
        now: _t(2),
        revisionId: 'revision-1',
      );
      final db = await f.fixture.database.database;
      await db.execute('''
CREATE TRIGGER fail_history_restore_update
BEFORE UPDATE ON segments
BEGIN
  SELECT RAISE(ABORT, 'forced history restore update failure');
END
''');
      expect(
        f.restoreRevision(
          projectId: 'project-1',
          segmentId: second.id,
          segmentRevisionId: 'revision-1',
          newRevisionId: 'rollback-1',
          nowUtc: _t(3),
        ),
        throwsA(isA<DataConflictException>()),
      );
      expect((await f.fixture.segments.getSegment(second.id)).content, 'v2');
      expect(
        f.fixture.segments.getRevision('rollback-1'),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('revision insert failure leaves current content unchanged', () async {
      final f = await _Fixture.create(count: 1);
      final second = await f.save(
        currentSegment: await f.fixture.segments.getSegment('segment-0'),
        newContent: 'v2',
        now: _t(2),
        revisionId: 'revision-1',
      );
      final db = await f.fixture.database.database;
      await db.execute('''
CREATE TRIGGER fail_history_restore_insert
BEFORE INSERT ON segment_revisions
WHEN NEW.id = 'rollback-1'
BEGIN
  SELECT RAISE(ABORT, 'forced history restore insert failure');
END
''');
      expect(
        f.restoreRevision(
          projectId: 'project-1',
          segmentId: second.id,
          segmentRevisionId: 'revision-1',
          newRevisionId: 'rollback-1',
          nowUtc: _t(3),
        ),
        throwsA(isA<DataConflictException>()),
      );
      expect((await f.fixture.segments.getSegment(second.id)).content, 'v2');
      expect(await f.fixture.segments.listRevisions(second.id), hasLength(1));
    });

    test('restored content and history persist after reopen', () async {
      final f = await _Fixture.create(count: 1);
      final second = await f.save(
        currentSegment: await f.fixture.segments.getSegment('segment-0'),
        newContent: 'v2',
        now: _t(2),
        revisionId: 'revision-1',
      );
      await f.restoreRevision(
        projectId: 'project-1',
        segmentId: second.id,
        segmentRevisionId: 'revision-1',
        newRevisionId: 'rollback-1',
        nowUtc: _t(3),
      );
      await f.fixture.database.close();
      final reopened = await reopenFixture(f.fixture);
      expect(
        (await reopened.segments.getSegment(second.id)).content,
        'segment-0',
      );
      expect(await reopened.segments.listRevisions(second.id), hasLength(2));
    });
  });
}

class _Fixture {
  _Fixture._(this.fixture)
    : insert = InsertSegment(fixture.projects, fixture.segments),
      reorder = ReorderSegments(fixture.projects, fixture.segments),
      softDelete = SoftDeleteSegment(fixture.projects, fixture.segments),
      restore = RestoreSegment(fixture.projects, fixture.segments),
      restoreRevision = RestoreSegmentRevision(
        fixture.projects,
        fixture.segments,
      ),
      save = SaveSegment(fixture.segments);

  final SqliteFixture fixture;
  final InsertSegment insert;
  final ReorderSegments reorder;
  final SoftDeleteSegment softDelete;
  final RestoreSegment restore;
  final RestoreSegmentRevision restoreRevision;
  final SaveSegment save;

  static Future<_Fixture> create({required int count}) async {
    final fixture = await SqliteFixture.create();
    await fixture.projects.upsertProject(project('project-1'));
    for (var index = 0; index < count; index += 1) {
      await fixture.segments.upsertSegment(
        segment('segment-$index', 'project-1', index),
      );
    }
    return _Fixture._(fixture);
  }

  Future<List<String>> activeIds() async {
    return (await fixture.segments.listSegments(
      'project-1',
    )).map((item) => item.id).toList();
  }
}

DateTime _t(int day) => DateTime.utc(2026, 1, day);
