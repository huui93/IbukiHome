import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/app/startup_error_app.dart';
import 'package:ibukihome/app/theme/theme_controller.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_character_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_chat_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_project_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_segment_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_world_repository.dart';

import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  group('SQLite provider integration', () {
    test('default repository provider remains in-memory for tests', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(projectRepositoryProvider),
        isA<InMemoryProjectRepository>(),
      );
    });

    test('production-style overrides use SQLite repositories', () async {
      final fixture = await SqliteFixture.create();
      final container = _sqliteContainer(fixture);
      addTearDown(container.dispose);

      expect(
        container.read(projectRepositoryProvider),
        isA<SQLiteProjectRepository>(),
      );
    });

    test('SQLite repositories share one database instance', () async {
      final fixture = await SqliteFixture.create();
      final container = _sqliteContainer(fixture);
      addTearDown(container.dispose);

      final projectRepo =
          container.read(projectRepositoryProvider) as SQLiteProjectRepository;
      final segmentRepo =
          container.read(segmentRepositoryProvider) as SQLiteSegmentRepository;
      final characterRepo =
          container.read(characterRepositoryProvider)
              as SQLiteCharacterRepository;
      final worldRepo =
          container.read(worldRepositoryProvider) as SQLiteWorldRepository;
      final chatRepo =
          container.read(chatRepositoryProvider) as SQLiteChatRepository;

      expect(segmentRepo.ibukiDatabase, same(projectRepo.ibukiDatabase));
      expect(characterRepo.ibukiDatabase, same(projectRepo.ibukiDatabase));
      expect(worldRepo.ibukiDatabase, same(projectRepo.ibukiDatabase));
      expect(chatRepo.ibukiDatabase, same(projectRepo.ibukiDatabase));
    });

    test('repository providers write and read SQLite data', () async {
      final fixture = await SqliteFixture.create();
      final container = _sqliteContainer(fixture);
      addTearDown(container.dispose);

      await container
          .read(projectRepositoryProvider)
          .upsertProject(project('project-1'));

      expect(
        (await container.read(projectListProvider.future)).single.id,
        'project-1',
      );
    });

    test('provider refresh does not reopen SQLite database', () async {
      final fixture = await SqliteFixture.create();
      final container = _sqliteContainer(fixture);
      addTearDown(container.dispose);

      await container.read(projectListProvider.future);
      container.invalidate(projectListProvider);
      await container.read(projectListProvider.future);

      expect(fixture.database.openCount, 1);
    });

    test('route-style provider reads keep SQLite data', () async {
      final fixture = await SqliteFixture.create();
      final container = _sqliteContainer(fixture);
      addTearDown(container.dispose);
      await fixture.projects.upsertProject(project('project-1'));
      await fixture.segments.upsertSegment(
        segment('segment-1', 'project-1', 0),
      );

      await container.read(projectListProvider.future);
      await container.read(segmentListProvider('project-1').future);
      await container.read(projectListProvider.future);

      expect(
        (await container.read(
          segmentListProvider('project-1').future,
        )).single.id,
        'segment-1',
      );
    });

    test('data change ticks keep SQLite data', () async {
      final fixture = await SqliteFixture.create();
      final container = _sqliteContainer(fixture);
      addTearDown(container.dispose);
      await fixture.projects.upsertProject(project('project-1'));

      container.read(dataChangeTickProvider.notifier).bump();

      expect(
        (await container.read(projectListProvider.future)).single.id,
        'project-1',
      );
    });

    test('theme switching keeps SQLite data', () async {
      final fixture = await SqliteFixture.create();
      final container = _sqliteContainer(fixture);
      addTearDown(container.dispose);
      await fixture.projects.upsertProject(project('project-1'));

      container.read(themeModeControllerProvider.notifier).setDarkMode(true);

      expect(
        (await container.read(projectListProvider.future)).single.id,
        'project-1',
      );
      expect(fixture.database.openCount, 1);
    });

    testWidgets('database startup error page shows retry', (tester) async {
      var retried = false;

      await tester.pumpWidget(
        StartupErrorApp(
          onRetry: () {
            retried = true;
          },
        ),
      );

      expect(find.text('数据库暂时无法打开'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pump();

      expect(retried, isTrue);
    });
  });
}

ProviderContainer _sqliteContainer(SqliteFixture fixture) {
  return ProviderContainer(
    overrides: [
      projectRepositoryProvider.overrideWithValue(
        SQLiteProjectRepository(fixture.database),
      ),
      segmentRepositoryProvider.overrideWithValue(
        SQLiteSegmentRepository(fixture.database),
      ),
      characterRepositoryProvider.overrideWithValue(
        SQLiteCharacterRepository(fixture.database),
      ),
      worldRepositoryProvider.overrideWithValue(
        SQLiteWorldRepository(fixture.database),
      ),
      chatRepositoryProvider.overrideWithValue(
        SQLiteChatRepository(fixture.database),
      ),
    ],
  );
}
