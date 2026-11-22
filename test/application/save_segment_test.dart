import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/segments/save_segment.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/data/memory/in_memory_segment_repository.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/segments/segment.dart';

void main() {
  group('SaveSegment', () {
    test('does not create a revision when content is unchanged', () async {
      final fixture = await _Fixture.create();

      final result = await fixture.save(
        currentSegment: fixture.segment,
        newContent: fixture.segment.content,
        now: DateTime.utc(2026, 1, 3),
        revisionId: 'revision-1',
      );

      expect(result, fixture.segment);
      expect(await fixture.segments.listRevisions(fixture.segment.id), isEmpty);
    });

    test(
      'creates a revision containing the old content when content changes',
      () async {
        final fixture = await _Fixture.create();

        await fixture.save(
          currentSegment: fixture.segment,
          newContent: '新正文',
          now: DateTime.utc(2026, 1, 3),
          revisionId: 'revision-1',
          note: '手动修改',
          userInstruction: '更轻一点',
          mode: 'local_edit',
        );

        final revisions = await fixture.segments.listRevisions(
          fixture.segment.id,
        );
        expect(revisions, hasLength(1));
        expect(revisions.single.content, '旧正文');
        expect(revisions.single.note, '手动修改');
        expect(revisions.single.userInstruction, '更轻一点');
        expect(revisions.single.mode, 'local_edit');
      },
    );

    test('increments segment revision', () async {
      final fixture = await _Fixture.create();

      final result = await fixture.save(
        currentSegment: fixture.segment,
        newContent: '新正文',
        now: DateTime.utc(2026, 1, 3),
        revisionId: 'revision-1',
      );

      expect(result.revision, 2);
    });

    test('keeps createdAt unchanged', () async {
      final fixture = await _Fixture.create();

      final result = await fixture.save(
        currentSegment: fixture.segment,
        newContent: '新正文',
        now: DateTime.utc(2026, 1, 3),
        revisionId: 'revision-1',
      );

      expect(result.createdAt, fixture.segment.createdAt);
    });

    test('updates updatedAt with the provided time', () async {
      final fixture = await _Fixture.create();
      final now = DateTime.parse('2026-01-03T08:00:00+08:00');

      final result = await fixture.save(
        currentSegment: fixture.segment,
        newContent: '新正文',
        now: now,
        revisionId: 'revision-1',
      );

      expect(result.updatedAt, DateTime.utc(2026, 1, 3));
    });

    test('keeps id, projectId and orderIndex unchanged', () async {
      final fixture = await _Fixture.create();

      final result = await fixture.save(
        currentSegment: fixture.segment,
        newContent: '新正文',
        now: DateTime.utc(2026, 1, 3),
        revisionId: 'revision-1',
      );

      expect(result.id, fixture.segment.id);
      expect(result.projectId, fixture.segment.projectId);
      expect(result.orderIndex, fixture.segment.orderIndex);
    });

    test('revision history sorts by revisionNumber', () async {
      final fixture = await _Fixture.create();
      final first = await fixture.save(
        currentSegment: fixture.segment,
        newContent: '第二版',
        now: DateTime.utc(2026, 1, 3),
        revisionId: 'revision-1',
      );
      await fixture.save(
        currentSegment: first,
        newContent: '第三版',
        now: DateTime.utc(2026, 1, 4),
        revisionId: 'revision-2',
      );

      final revisions = await fixture.segments.listRevisions(
        fixture.segment.id,
      );

      expect(revisions.map((revision) => revision.revisionNumber), [1, 2]);
    });

    test('fails when revision ID conflicts', () async {
      final fixture = await _Fixture.create();
      final first = await fixture.save(
        currentSegment: fixture.segment,
        newContent: '第二版',
        now: DateTime.utc(2026, 1, 3),
        revisionId: 'revision-1',
      );

      expect(
        fixture.save(
          currentSegment: first,
          newContent: '第三版',
          now: DateTime.utc(2026, 1, 4),
          revisionId: 'revision-1',
        ),
        throwsA(isA<DuplicateEntityException>()),
      );
      expect(
        (await fixture.segments.getSegment(fixture.segment.id)).content,
        '第二版',
      );
    });

    test('fails when the segment no longer exists', () async {
      final store = InMemoryIbukiStore();
      final segments = InMemorySegmentRepository(store);
      final save = SaveSegment(segments);
      final missing = _segment();

      expect(
        save(
          currentSegment: missing,
          newContent: '新正文',
          now: DateTime.utc(2026, 1, 3),
          revisionId: 'revision-1',
        ),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });
}

class _Fixture {
  _Fixture({required this.segments, required this.save, required this.segment});

  final InMemorySegmentRepository segments;
  final SaveSegment save;
  final Segment segment;

  static Future<_Fixture> create() async {
    final store = InMemoryIbukiStore();
    final projects = InMemoryProjectRepository(store);
    final segments = InMemorySegmentRepository(store);
    final save = SaveSegment(segments);
    final segment = _segment();

    await projects.upsertProject(
      Project(metadata: _metadata('project-1'), title: '项目', description: ''),
    );
    await segments.upsertSegment(segment);

    return _Fixture(segments: segments, save: save, segment: segment);
  }
}

Segment _segment() {
  return Segment(
    metadata: _metadata('segment-1'),
    projectId: 'project-1',
    orderIndex: 4,
    content: '旧正文',
  );
}

EntityMetadata _metadata(String id) {
  return EntityMetadata(
    id: id,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 2),
    revision: 1,
  );
}
