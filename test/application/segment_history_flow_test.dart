import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/segments/insert_segment.dart';
import 'package:ibukihome/application/segments/list_segment_revisions.dart';
import 'package:ibukihome/application/segments/reorder_segments.dart';
import 'package:ibukihome/application/segments/restore_segment.dart';
import 'package:ibukihome/application/segments/restore_segment_revision.dart';
import 'package:ibukihome/application/segments/save_segment.dart';
import 'package:ibukihome/application/segments/soft_delete_segment.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/data/memory/in_memory_segment_repository.dart';
import 'package:ibukihome/data/repositories/segment_repository.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/segments/segment.dart';
import 'package:ibukihome/domain/segments/segment_revision.dart';

void main() {
  group('segment insertion and ordering', () {
    test('inserts before an anchor', () async {
      final f = await _Fixture.create();
      await f.addSegments(3);

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
      final f = await _Fixture.create();
      await f.addSegments(3);

      final inserted = await f.insert(
        projectId: 'project-1',
        anchorSegmentId: 'segment-1',
        position: SegmentInsertPosition.after,
        content: 'inserted',
        id: 'inserted',
        nowUtc: _t(2),
      );

      expect(inserted.orderIndex, 2);
      expect(await f.activeIds(), [
        'segment-0',
        'segment-1',
        'inserted',
        'segment-2',
      ]);
    });

    test('insert keeps active order indexes continuous', () async {
      final f = await _Fixture.create();
      await f.addSegments(4);
      await f.insert(
        projectId: 'project-1',
        anchorSegmentId: 'segment-2',
        position: SegmentInsertPosition.before,
        content: '',
        id: 'inserted',
        nowUtc: _t(2),
      );

      expect(
        (await f.segments.listSegments('project-1')).map((e) => e.orderIndex),
        [0, 1, 2, 3, 4],
      );
    });

    test('insert rejects a missing anchor', () async {
      final f = await _Fixture.create();
      expect(
        f.insert(
          projectId: 'project-1',
          anchorSegmentId: 'missing',
          position: SegmentInsertPosition.before,
          content: '',
          id: 'inserted',
          nowUtc: _t(2),
        ),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('insert rejects a cross-project anchor', () async {
      final f = await _Fixture.create();
      await f.addProject('project-2');
      await f.addSegment('other', projectId: 'project-2', orderIndex: 0);

      expect(
        f.insert(
          projectId: 'project-1',
          anchorSegmentId: 'other',
          position: SegmentInsertPosition.before,
          content: '',
          id: 'inserted',
          nowUtc: _t(2),
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('insert rejects a deleted anchor', () async {
      final f = await _Fixture.create();
      await f.addSegment('anchor', orderIndex: 0);
      await f.softDelete(
        projectId: 'project-1',
        segmentId: 'anchor',
        deletedAt: _t(2),
      );

      expect(
        f.insert(
          projectId: 'project-1',
          anchorSegmentId: 'anchor',
          position: SegmentInsertPosition.after,
          content: '',
          id: 'inserted',
          nowUtc: _t(3),
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('insert rejects a deleted project', () async {
      final f = await _Fixture.create();
      await f.addSegment('anchor', orderIndex: 0);
      await f.projects.softDeleteProject('project-1', _t(2));

      expect(
        f.insert(
          projectId: 'project-1',
          anchorSegmentId: 'anchor',
          position: SegmentInsertPosition.after,
          content: '',
          id: 'inserted',
          nowUtc: _t(3),
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('insert allows empty content', () async {
      final f = await _Fixture.create();
      await f.addSegment('anchor', orderIndex: 0);
      final result = await f.insert(
        projectId: 'project-1',
        anchorSegmentId: 'anchor',
        position: SegmentInsertPosition.after,
        content: '',
        id: 'inserted',
        nowUtc: _t(2),
      );
      expect(result.content, isEmpty);
    });

    test('insert starts with revision one and UTC timestamps', () async {
      final f = await _Fixture.create();
      await f.addSegment('anchor', orderIndex: 0);
      final result = await f.insert(
        projectId: 'project-1',
        anchorSegmentId: 'anchor',
        position: SegmentInsertPosition.after,
        content: 'text',
        id: 'inserted',
        nowUtc: DateTime.parse('2026-01-02T08:00:00+08:00'),
      );
      expect(result.revision, 1);
      expect(result.createdAt, DateTime.utc(2026, 1, 2));
      expect(result.updatedAt, DateTime.utc(2026, 1, 2));
      expect(result.deletedAt, isNull);
    });

    test(
      'insert rejects a duplicate segment id without shifting order',
      () async {
        final f = await _Fixture.create();
        await f.addSegments(2);
        expect(
          f.insert(
            projectId: 'project-1',
            anchorSegmentId: 'segment-0',
            position: SegmentInsertPosition.after,
            content: '',
            id: 'segment-1',
            nowUtc: _t(2),
          ),
          throwsA(isA<DuplicateEntityException>()),
        );
        expect(await f.activeIds(), ['segment-0', 'segment-1']);
      },
    );

    test('reorders middle segments upward', () async {
      final f = await _Fixture.create();
      await f.addSegments(3);
      await f.reorder(
        projectId: 'project-1',
        orderedIds: ['segment-1', 'segment-0', 'segment-2'],
        updatedAt: _t(2),
      );
      expect(await f.activeIds(), ['segment-1', 'segment-0', 'segment-2']);
    });

    test('reorders middle segments downward', () async {
      final f = await _Fixture.create();
      await f.addSegments(3);
      await f.reorder(
        projectId: 'project-1',
        orderedIds: ['segment-0', 'segment-2', 'segment-1'],
        updatedAt: _t(2),
      );
      expect(await f.activeIds(), ['segment-0', 'segment-2', 'segment-1']);
    });

    test('unchanged reorder does not add revisions', () async {
      final f = await _Fixture.create();
      await f.addSegments(2);
      await f.reorder(
        projectId: 'project-1',
        orderedIds: ['segment-0', 'segment-1'],
        updatedAt: _t(2),
      );
      expect((await f.segments.getSegment('segment-0')).revision, 1);
      expect((await f.segments.getSegment('segment-1')).revision, 1);
    });

    test(
      'changed reorder increments affected revisions without history',
      () async {
        final f = await _Fixture.create();
        await f.addSegments(2);
        await f.reorder(
          projectId: 'project-1',
          orderedIds: ['segment-1', 'segment-0'],
          updatedAt: _t(2),
        );
        expect((await f.segments.getSegment('segment-0')).revision, 2);
        expect((await f.segments.getSegment('segment-1')).revision, 2);
        expect(await f.segments.listRevisions('segment-0'), isEmpty);
      },
    );

    test('changed reorder preserves createdAt and updates updatedAt', () async {
      final f = await _Fixture.create();
      await f.addSegments(2);
      await f.reorder(
        projectId: 'project-1',
        orderedIds: ['segment-1', 'segment-0'],
        updatedAt: _t(3),
      );
      final moved = await f.segments.getSegment('segment-1');
      expect(moved.createdAt, _t(1));
      expect(moved.updatedAt, _t(3));
    });

    test('reorder rejects missing ids', () async {
      final f = await _Fixture.create();
      await f.addSegments(2);
      expect(
        f.reorder(
          projectId: 'project-1',
          orderedIds: ['segment-0'],
          updatedAt: _t(2),
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('reorder rejects duplicate ids', () async {
      final f = await _Fixture.create();
      await f.addSegments(2);
      expect(
        f.reorder(
          projectId: 'project-1',
          orderedIds: ['segment-0', 'segment-0'],
          updatedAt: _t(2),
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('reorder rejects cross-project ids', () async {
      final f = await _Fixture.create();
      await f.addSegment('segment-0', orderIndex: 0);
      await f.addProject('project-2');
      await f.addSegment('other', projectId: 'project-2', orderIndex: 0);
      expect(
        f.reorder(
          projectId: 'project-1',
          orderedIds: ['other'],
          updatedAt: _t(2),
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('deleted segments are excluded from reorder input', () async {
      final f = await _Fixture.create();
      await f.addSegments(2);
      await f.softDelete(
        projectId: 'project-1',
        segmentId: 'segment-1',
        deletedAt: _t(2),
      );
      await f.reorder(
        projectId: 'project-1',
        orderedIds: ['segment-0'],
        updatedAt: _t(3),
      );
      expect(await f.activeIds(), ['segment-0']);
    });
  });

  group('segment soft delete and restore', () {
    test('soft delete hides a segment and increments revision', () async {
      final f = await _Fixture.create();
      await f.addSegment('segment-0', orderIndex: 0);
      final deleted = await f.softDelete(
        projectId: 'project-1',
        segmentId: 'segment-0',
        deletedAt: _t(2),
      );
      expect(deleted.deletedAt, _t(2));
      expect(deleted.revision, 2);
      expect(await f.segments.listSegments('project-1'), isEmpty);
    });

    test('includeDeleted reads a soft-deleted segment', () async {
      final f = await _Fixture.create();
      await f.addSegment('segment-0', orderIndex: 0);
      await f.softDelete(
        projectId: 'project-1',
        segmentId: 'segment-0',
        deletedAt: _t(2),
      );
      expect(
        await f.segments.listSegments('project-1', includeDeleted: true),
        hasLength(1),
      );
    });

    test('repeated soft delete is a no-op', () async {
      final f = await _Fixture.create();
      await f.addSegment('segment-0', orderIndex: 0);
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
      expect(second, first);
    });

    test('delete normalizes active order indexes', () async {
      final f = await _Fixture.create();
      await f.addSegments(4);
      await f.softDelete(
        projectId: 'project-1',
        segmentId: 'segment-1',
        deletedAt: _t(2),
      );
      expect(
        (await f.segments.listSegments('project-1')).map((e) => e.orderIndex),
        [0, 1, 2],
      );
    });

    test('delete keeps historical revisions', () async {
      final f = await _Fixture.create();
      final original = await f.addSegment('segment-0', orderIndex: 0);
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
      expect(await f.segments.listRevisions('segment-0'), hasLength(1));
    });

    test('delete rejects a cross-project segment', () async {
      final f = await _Fixture.create();
      await f.addProject('project-2');
      await f.addSegment('other', projectId: 'project-2', orderIndex: 0);
      expect(
        f.softDelete(
          projectId: 'project-1',
          segmentId: 'other',
          deletedAt: _t(2),
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('restore returns a segment to its former position', () async {
      final f = await _Fixture.create();
      await f.addSegments(3);
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

    test('restore clamps an out-of-range former position', () async {
      final f = await _Fixture.create();
      await f.addSegment('active', orderIndex: 0);
      final deleted = Segment(
        metadata: _metadata('deleted', deletedAt: _t(2)),
        projectId: 'project-1',
        orderIndex: 99,
        content: 'deleted',
      );
      await f.segments.upsertSegment(deleted);
      final restored = await f.restore(
        projectId: 'project-1',
        segmentId: 'deleted',
        restoredAt: _t(3),
      );
      expect(restored.orderIndex, 1);
      expect(await f.activeIds(), ['active', 'deleted']);
    });

    test('repeated restore is a no-op', () async {
      final f = await _Fixture.create();
      await f.addSegment('segment-0', orderIndex: 0);
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
      expect(second, first);
    });

    test('restore leaves active order indexes continuous', () async {
      final f = await _Fixture.create();
      await f.addSegments(4);
      await f.softDelete(
        projectId: 'project-1',
        segmentId: 'segment-2',
        deletedAt: _t(2),
      );
      await f.restore(
        projectId: 'project-1',
        segmentId: 'segment-2',
        restoredAt: _t(3),
      );
      expect(
        (await f.segments.listSegments('project-1')).map((e) => e.orderIndex),
        [0, 1, 2, 3],
      );
    });

    test('restore preserves identity, content and createdAt', () async {
      final f = await _Fixture.create();
      final original = await f.addSegment(
        'segment-0',
        orderIndex: 0,
        content: 'text',
      );
      await f.softDelete(
        projectId: 'project-1',
        segmentId: original.id,
        deletedAt: _t(2),
      );
      final restored = await f.restore(
        projectId: 'project-1',
        segmentId: original.id,
        restoredAt: _t(3),
      );
      expect(restored.id, original.id);
      expect(restored.content, original.content);
      expect(restored.createdAt, original.createdAt);
    });
  });

  group('segment revision listing and restoration', () {
    test('lists history newest revision first', () async {
      final f = await _Fixture.create();
      final original = await f.addSegment(
        'segment-0',
        orderIndex: 0,
        content: 'v1',
      );
      final second = await f.save(
        currentSegment: original,
        newContent: 'v2',
        now: _t(2),
        revisionId: 'revision-1',
      );
      await f.save(
        currentSegment: second,
        newContent: 'v3',
        now: _t(3),
        revisionId: 'revision-2',
      );
      final history = await f.listHistory(
        projectId: 'project-1',
        segmentId: original.id,
      );
      expect(history.map((item) => item.revisionNumber), [2, 1]);
    });

    test('history listing rejects a forged project id', () async {
      final f = await _Fixture.create();
      await f.addSegment('segment-0', orderIndex: 0);
      expect(
        f.listHistory(projectId: 'project-2', segmentId: 'segment-0'),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('restores historical content', () async {
      final f = await _revisionFixture();
      final result = await f.restoreRevision(
        projectId: 'project-1',
        segmentId: 'segment-0',
        segmentRevisionId: 'revision-1',
        newRevisionId: 'rollback-1',
        nowUtc: _t(3),
      );
      expect(result.content, 'v1');
    });

    test('stores current content before restoring history', () async {
      final f = await _revisionFixture();
      await f.restoreRevision(
        projectId: 'project-1',
        segmentId: 'segment-0',
        segmentRevisionId: 'revision-1',
        newRevisionId: 'rollback-1',
        nowUtc: _t(3),
      );
      final rollback = await f.segments.getRevision('rollback-1');
      expect(rollback.content, 'v2');
      expect(rollback.mode, 'mobile_restore');
    });

    test('history restore increments current revision', () async {
      final f = await _revisionFixture();
      final result = await f.restoreRevision(
        projectId: 'project-1',
        segmentId: 'segment-0',
        segmentRevisionId: 'revision-1',
        newRevisionId: 'rollback-1',
        nowUtc: _t(3),
      );
      expect(result.revision, 3);
    });

    test('history restore preserves createdAt and orderIndex', () async {
      final f = await _revisionFixture();
      final before = await f.segments.getSegment('segment-0');
      final result = await f.restoreRevision(
        projectId: 'project-1',
        segmentId: 'segment-0',
        segmentRevisionId: 'revision-1',
        newRevisionId: 'rollback-1',
        nowUtc: _t(3),
      );
      expect(result.createdAt, before.createdAt);
      expect(result.orderIndex, before.orderIndex);
    });

    test('history restore does not modify its target revision', () async {
      final f = await _revisionFixture();
      final target = await f.segments.getRevision('revision-1');
      await f.restoreRevision(
        projectId: 'project-1',
        segmentId: 'segment-0',
        segmentRevisionId: target.id,
        newRevisionId: 'rollback-1',
        nowUtc: _t(3),
      );
      expect(await f.segments.getRevision(target.id), target);
    });

    test('restoring identical content is a no-op', () async {
      final f = await _revisionFixture();
      final current = await f.segments.getSegment('segment-0');
      await f.segments.appendRevision(
        _revision('same', current, content: current.content),
      );
      final result = await f.restoreRevision(
        projectId: 'project-1',
        segmentId: current.id,
        segmentRevisionId: 'same',
        newRevisionId: 'unused',
        nowUtc: _t(3),
      );
      expect(result, current);
      expect(f.segments.getRevision('unused'), throwsA(anything));
    });

    test('revision id conflict rolls back historical restore', () async {
      final f = await _revisionFixture();
      final before = await f.segments.getSegment('segment-0');
      expect(
        f.restoreRevision(
          projectId: 'project-1',
          segmentId: 'segment-0',
          segmentRevisionId: 'revision-1',
          newRevisionId: 'revision-1',
          nowUtc: _t(3),
        ),
        throwsA(isA<DuplicateEntityException>()),
      );
      expect(await f.segments.getSegment('segment-0'), before);
      expect(await f.segments.listRevisions('segment-0'), hasLength(1));
    });

    test('restored content can be restored back again', () async {
      final f = await _revisionFixture();
      await f.restoreRevision(
        projectId: 'project-1',
        segmentId: 'segment-0',
        segmentRevisionId: 'revision-1',
        newRevisionId: 'rollback-1',
        nowUtc: _t(3),
      );
      final restoredBack = await f.restoreRevision(
        projectId: 'project-1',
        segmentId: 'segment-0',
        segmentRevisionId: 'rollback-1',
        newRevisionId: 'rollback-2',
        nowUtc: _t(4),
      );
      expect(restoredBack.content, 'v2');
      expect(await f.segments.listRevisions('segment-0'), hasLength(3));
    });

    test('rejects a revision from another segment', () async {
      final f = await _revisionFixture();
      final other = await f.addSegment('other', orderIndex: 1);
      await f.segments.appendRevision(_revision('other-revision', other));
      expect(
        f.restoreRevision(
          projectId: 'project-1',
          segmentId: 'segment-0',
          segmentRevisionId: 'other-revision',
          newRevisionId: 'rollback',
          nowUtc: _t(3),
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('rejects a revision from another project', () async {
      final f = await _revisionFixture();
      await f.addProject('project-2');
      final other = await f.addSegment(
        'other',
        projectId: 'project-2',
        orderIndex: 0,
      );
      await f.segments.appendRevision(_revision('other-revision', other));
      expect(
        f.restoreRevision(
          projectId: 'project-1',
          segmentId: 'segment-0',
          segmentRevisionId: 'other-revision',
          newRevisionId: 'rollback',
          nowUtc: _t(3),
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('rejects restoration for a deleted segment', () async {
      final f = await _revisionFixture();
      await f.softDelete(
        projectId: 'project-1',
        segmentId: 'segment-0',
        deletedAt: _t(3),
      );
      expect(
        f.restoreRevision(
          projectId: 'project-1',
          segmentId: 'segment-0',
          segmentRevisionId: 'revision-1',
          newRevisionId: 'rollback',
          nowUtc: _t(4),
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('rejects a missing history record', () async {
      final f = await _revisionFixture();
      expect(
        f.restoreRevision(
          projectId: 'project-1',
          segmentId: 'segment-0',
          segmentRevisionId: 'missing',
          newRevisionId: 'rollback',
          nowUtc: _t(3),
        ),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });
}

class _Fixture {
  _Fixture._(this.store)
    : projects = InMemoryProjectRepository(store),
      segments = InMemorySegmentRepository(store),
      insert = InsertSegment(
        InMemoryProjectRepository(store),
        InMemorySegmentRepository(store),
      ),
      reorder = ReorderSegments(
        InMemoryProjectRepository(store),
        InMemorySegmentRepository(store),
      ),
      softDelete = SoftDeleteSegment(
        InMemoryProjectRepository(store),
        InMemorySegmentRepository(store),
      ),
      restore = RestoreSegment(
        InMemoryProjectRepository(store),
        InMemorySegmentRepository(store),
      ),
      listHistory = ListSegmentRevisions(InMemorySegmentRepository(store)),
      restoreRevision = RestoreSegmentRevision(
        InMemoryProjectRepository(store),
        InMemorySegmentRepository(store),
      ),
      save = SaveSegment(InMemorySegmentRepository(store));

  final InMemoryIbukiStore store;
  final InMemoryProjectRepository projects;
  final InMemorySegmentRepository segments;
  final InsertSegment insert;
  final ReorderSegments reorder;
  final SoftDeleteSegment softDelete;
  final RestoreSegment restore;
  final ListSegmentRevisions listHistory;
  final RestoreSegmentRevision restoreRevision;
  final SaveSegment save;

  static Future<_Fixture> create() async {
    final fixture = _Fixture._(InMemoryIbukiStore());
    await fixture.addProject('project-1');
    return fixture;
  }

  Future<void> addProject(String id) {
    return projects.upsertProject(
      Project(metadata: _metadata(id), title: id, description: ''),
    );
  }

  Future<Segment> addSegment(
    String id, {
    String projectId = 'project-1',
    required int orderIndex,
    String? content,
  }) async {
    final item = Segment(
      metadata: _metadata(id),
      projectId: projectId,
      orderIndex: orderIndex,
      content: content ?? id,
    );
    await segments.upsertSegment(item);
    return item;
  }

  Future<void> addSegments(int count) async {
    for (var index = 0; index < count; index += 1) {
      await addSegment('segment-$index', orderIndex: index);
    }
  }

  Future<List<String>> activeIds() async {
    return (await segments.listSegments('project-1')).map((e) => e.id).toList();
  }
}

Future<_Fixture> _revisionFixture() async {
  final f = await _Fixture.create();
  final first = await f.addSegment('segment-0', orderIndex: 0, content: 'v1');
  await f.save(
    currentSegment: first,
    newContent: 'v2',
    now: _t(2),
    revisionId: 'revision-1',
  );
  return f;
}

SegmentRevision _revision(String id, Segment segment, {String? content}) {
  return SegmentRevision(
    metadata: _metadata(id),
    projectId: segment.projectId,
    segmentId: segment.id,
    revisionNumber: segment.revision,
    content: content ?? segment.content,
    note: '',
    userInstruction: '',
    mode: 'test',
  );
}

EntityMetadata _metadata(String id, {DateTime? deletedAt}) {
  return EntityMetadata(
    id: id,
    createdAt: _t(1),
    updatedAt: deletedAt ?? _t(1),
    revision: deletedAt == null ? 1 : 2,
    deletedAt: deletedAt,
  );
}

DateTime _t(int day) => DateTime.utc(2026, 1, day);
