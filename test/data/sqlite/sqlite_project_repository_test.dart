import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';

import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  group('SQLiteProjectRepository', () {
    test('creates and reads a project', () async {
      final fixture = await SqliteFixture.create();

      await fixture.projects.upsertProject(project('project-1'));

      expect(
        await fixture.projects.getProject('project-1'),
        project('project-1'),
      );
    });

    test('updates a project', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-1'));

      await fixture.projects.upsertProject(
        project('project-1').copyWith(title: 'Updated'),
      );

      expect((await fixture.projects.getProject('project-1')).title, 'Updated');
    });

    test('hides soft-deleted projects by default', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-1'));

      await fixture.projects.softDeleteProject(
        'project-1',
        DateTime.utc(2026, 1, 2),
      );

      expect(await fixture.projects.listProjects(), isEmpty);
    });

    test('includeDeleted can read soft-deleted projects', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-1'));
      await fixture.projects.softDeleteProject(
        'project-1',
        DateTime.utc(2026, 1, 2),
      );

      expect(
        await fixture.projects.listProjects(includeDeleted: true),
        hasLength(1),
      );
    });

    test('restores a soft-deleted project', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-1'));
      await fixture.projects.softDeleteProject(
        'project-1',
        DateTime.utc(2026, 1, 2),
      );

      await fixture.projects.restoreProject(
        'project-1',
        DateTime.utc(2026, 1, 3),
      );

      final restored = await fixture.projects.getProject('project-1');
      expect(restored.deletedAt, isNull);
      expect(restored.revision, 3);
      expect(await fixture.projects.listProjects(), hasLength(1));
    });

    test('sorts like the in-memory implementation', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(
        project('project-b', title: 'B', updatedAt: DateTime.utc(2026, 1, 1)),
      );
      await fixture.projects.upsertProject(
        project('project-a', title: 'A', updatedAt: DateTime.utc(2026, 1, 2)),
      );
      await fixture.projects.upsertProject(
        project('project-c', title: 'C', updatedAt: DateTime.utc(2026, 1, 1)),
      );

      final projects = await fixture.projects.listProjects();

      expect(projects.map((item) => item.id), [
        'project-a',
        'project-b',
        'project-c',
      ]);
    });

    test('persists projects after closing and reopening', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-1'));
      await fixture.database.close();

      final reopened = await reopenFixture(fixture);

      expect((await reopened.projects.getProject('project-1')).id, 'project-1');
    });

    test('missing project throws an explicit exception', () async {
      final fixture = await SqliteFixture.create();

      expect(
        fixture.projects.getProject('missing'),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });
}
