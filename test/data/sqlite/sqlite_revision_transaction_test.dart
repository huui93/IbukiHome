import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/segments/save_segment.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';

import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  group('SQLite segment revisions and transactions', () {
    test('editing content creates a historical revision', () async {
      final fixture = await _Fixture.create();

      await fixture.save(
        currentSegment: fixture.initial,
        newContent: 'new content',
        now: DateTime.utc(2026, 1, 2),
        revisionId: 'revision-1',
      );

      final revisions = await fixture.segments.listRevisions('segment-1');
      expect(revisions, hasLength(1));
      expect(revisions.single.content, 'old content');
      expect(revisions.single.revisionNumber, 1);
    });

    test('editing content increments segment revision', () async {
      final fixture = await _Fixture.create();

      final updated = await fixture.save(
        currentSegment: fixture.initial,
        newContent: 'new content',
        now: DateTime.utc(2026, 1, 2),
        revisionId: 'revision-1',
      );

      expect(updated.revision, 2);
      expect((await fixture.segments.getSegment('segment-1')).revision, 2);
    });

    test('unchanged content does not create a revision', () async {
      final fixture = await _Fixture.create();

      await fixture.save(
        currentSegment: fixture.initial,
        newContent: 'old content',
        now: DateTime.utc(2026, 1, 2),
        revisionId: 'revision-1',
      );

      expect(await fixture.segments.listRevisions('segment-1'), isEmpty);
    });

    test('revision ID conflict rolls back the segment update', () async {
      final fixture = await _Fixture.create();
      final secondVersion = await fixture.save(
        currentSegment: fixture.initial,
        newContent: 'new content',
        now: DateTime.utc(2026, 1, 2),
        revisionId: 'revision-1',
      );

      expect(
        fixture.save(
          currentSegment: secondVersion,
          newContent: 'third content',
          now: DateTime.utc(2026, 1, 3),
          revisionId: 'revision-1',
        ),
        throwsA(isA<DuplicateEntityException>()),
      );

      final stored = await fixture.segments.getSegment('segment-1');
      final revisions = await fixture.segments.listRevisions('segment-1');
      expect(stored.content, 'new content');
      expect(stored.revision, 2);
      expect(revisions, hasLength(1));
    });

    test('segment update failure leaves no historical residue', () async {
      final fixture = await _Fixture.create();
      final db = await fixture.database.database;
      await db.execute('''
CREATE TRIGGER fail_segment_update
BEFORE UPDATE ON segments
BEGIN
  SELECT RAISE(ABORT, 'forced segment update failure');
END
''');

      expect(
        fixture.save(
          currentSegment: fixture.initial,
          newContent: 'new content',
          now: DateTime.utc(2026, 1, 2),
          revisionId: 'revision-1',
        ),
        throwsA(isA<DataConflictException>()),
      );

      expect(
        (await fixture.segments.getSegment('segment-1')).content,
        'old content',
      );
      expect(await fixture.segments.listRevisions('segment-1'), isEmpty);
    });

    test('unique segment revision number constraint is enforced', () async {
      final fixture = await _Fixture.create();
      await fixture.segments.appendRevision(
        segmentRevision('revision-1', 'project-1', 'segment-1', 1),
      );

      expect(
        fixture.segments.appendRevision(
          segmentRevision('revision-2', 'project-1', 'segment-1', 1),
        ),
        throwsA(isA<DuplicateEntityException>()),
      );
    });

    test('revisions persist after closing and reopening', () async {
      final fixture = await _Fixture.create();
      await fixture.save(
        currentSegment: fixture.initial,
        newContent: 'new content',
        now: DateTime.utc(2026, 1, 2),
        revisionId: 'revision-1',
      );
      await fixture.database.close();

      final reopened = await reopenFixture(fixture.sqliteFixture);

      expect(await reopened.segments.listRevisions('segment-1'), hasLength(1));
    });
  });
}

class _Fixture {
  const _Fixture({
    required this.sqliteFixture,
    required this.segments,
    required this.save,
    required this.initial,
  });

  final SqliteFixture sqliteFixture;
  final dynamic segments;
  final SaveSegment save;
  final dynamic initial;

  dynamic get database => sqliteFixture.database;

  static Future<_Fixture> create() async {
    final fixture = await SqliteFixture.create();
    await fixture.projects.upsertProject(project('project-1'));
    final initial = segment(
      'segment-1',
      'project-1',
      0,
      content: 'old content',
    );
    await fixture.segments.upsertSegment(initial);
    return _Fixture(
      sqliteFixture: fixture,
      segments: fixture.segments,
      save: SaveSegment(fixture.segments),
      initial: initial,
    );
  }
}
