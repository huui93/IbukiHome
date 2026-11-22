import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';

import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  group('SQLiteSegmentRepository', () {
    test('creates and reads a segment', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-1'));

      await fixture.segments.upsertSegment(
        segment('segment-1', 'project-1', 0),
      );

      expect(
        await fixture.segments.getSegment('segment-1'),
        segment('segment-1', 'project-1', 0),
      );
    });

    test('isolates segments by projectId', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-a'));
      await fixture.projects.upsertProject(project('project-b'));
      await fixture.segments.upsertSegment(
        segment('segment-a', 'project-a', 0),
      );
      await fixture.segments.upsertSegment(
        segment('segment-b', 'project-b', 0),
      );

      final segments = await fixture.segments.listSegments('project-a');

      expect(segments.map((item) => item.id), ['segment-a']);
    });

    test('sorts by orderIndex', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-1'));
      await fixture.segments.upsertSegment(
        segment('segment-2', 'project-1', 2),
      );
      await fixture.segments.upsertSegment(
        segment('segment-1', 'project-1', 1),
      );

      final segments = await fixture.segments.listSegments('project-1');

      expect(segments.map((item) => item.id), ['segment-1', 'segment-2']);
    });

    test('foreign key rejects a segment for a missing project', () async {
      final fixture = await SqliteFixture.create();

      expect(
        fixture.segments.upsertSegment(segment('segment-1', 'missing', 0)),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('soft-deletes and restores segments', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-1'));
      await fixture.segments.upsertSegment(
        segment('segment-1', 'project-1', 0),
      );

      await fixture.segments.softDeleteSegment(
        'segment-1',
        DateTime.utc(2026, 1, 2),
      );

      expect(await fixture.segments.listSegments('project-1'), isEmpty);
      expect(
        await fixture.segments.listSegments('project-1', includeDeleted: true),
        hasLength(1),
      );

      await fixture.segments.restoreSegment(
        'segment-1',
        DateTime.utc(2026, 1, 3),
      );

      expect(await fixture.segments.listSegments('project-1'), hasLength(1));
    });

    test('persists segments after closing and reopening', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-1'));
      await fixture.segments.upsertSegment(
        segment('segment-1', 'project-1', 0),
      );
      await fixture.database.close();

      final reopened = await reopenFixture(fixture);

      expect(
        (await reopened.segments.listSegments('project-1')).single.id,
        'segment-1',
      );
    });

    test('rejects moving a segment between projects', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-a'));
      await fixture.projects.upsertProject(project('project-b'));
      await fixture.segments.upsertSegment(
        segment('segment-1', 'project-a', 0),
      );

      expect(
        fixture.segments.upsertSegment(segment('segment-1', 'project-b', 0)),
        throwsA(isA<DataConflictException>()),
      );
    });
  });
}
