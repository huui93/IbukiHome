import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';

import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  test('character reorder is atomic and persists after reopen', () async {
    final fixture = await SqliteFixture.create();
    await fixture.projects.upsertProject(project('project-1'));
    await fixture.characters.upsertCharacter(
      characterCard('character-1', 'project-1', 0),
    );
    await fixture.characters.upsertCharacter(
      characterCard('character-2', 'project-1', 1),
    );

    await fixture.characters.reorderCharacters(
      projectId: 'project-1',
      orderedIds: const ['character-2', 'character-1'],
      updatedAt: DateTime.utc(2026, 7, 30, 10),
    );
    final reopened = await reopenFixture(fixture);

    expect(
      (await reopened.characters.listCharacters(
        'project-1',
      )).map((item) => item.id),
      ['character-2', 'character-1'],
    );
  });

  test('world reorder is atomic and persists after reopen', () async {
    final fixture = await SqliteFixture.create();
    await fixture.projects.upsertProject(project('project-1'));
    await fixture.world.upsertWorldCard(worldCard('world-1', 'project-1', 0));
    await fixture.world.upsertWorldCard(worldCard('world-2', 'project-1', 1));

    await fixture.world.reorderWorldCards(
      projectId: 'project-1',
      orderedIds: const ['world-2', 'world-1'],
      updatedAt: DateTime.utc(2026, 7, 30, 10),
    );
    final reopened = await reopenFixture(fixture);

    expect(
      (await reopened.world.listWorldCards('project-1')).map((item) => item.id),
      ['world-2', 'world-1'],
    );
  });

  test('character reorder failure rolls back every update', () async {
    final fixture = await SqliteFixture.create();
    await fixture.projects.upsertProject(project('project-1'));
    await fixture.characters.upsertCharacter(
      characterCard('character-1', 'project-1', 0),
    );
    await fixture.characters.upsertCharacter(
      characterCard('character-2', 'project-1', 1),
    );
    final database = await fixture.database.database;
    await database.execute('''
CREATE TRIGGER fail_character_reorder
BEFORE UPDATE OF sort_order ON character_cards
WHEN NEW.id = 'character-1'
BEGIN
  SELECT RAISE(ABORT, 'forced reorder failure');
END
''');

    expect(
      () => fixture.characters.reorderCharacters(
        projectId: 'project-1',
        orderedIds: const ['character-2', 'character-1'],
        updatedAt: DateTime.utc(2026, 7, 30, 10),
      ),
      throwsA(isA<DataConflictException>()),
    );
    expect(
      (await fixture.characters.listCharacters(
        'project-1',
      )).map((item) => '${item.id}:${item.sortOrder}'),
      ['character-1:0', 'character-2:1'],
    );
  });

  test('world reorder failure rolls back every update', () async {
    final fixture = await SqliteFixture.create();
    await fixture.projects.upsertProject(project('project-1'));
    await fixture.world.upsertWorldCard(worldCard('world-1', 'project-1', 0));
    await fixture.world.upsertWorldCard(worldCard('world-2', 'project-1', 1));
    final database = await fixture.database.database;
    await database.execute('''
CREATE TRIGGER fail_world_reorder
BEFORE UPDATE OF sort_order ON world_cards
WHEN NEW.id = 'world-1'
BEGIN
  SELECT RAISE(ABORT, 'forced reorder failure');
END
''');

    expect(
      () => fixture.world.reorderWorldCards(
        projectId: 'project-1',
        orderedIds: const ['world-2', 'world-1'],
        updatedAt: DateTime.utc(2026, 7, 30, 10),
      ),
      throwsA(isA<DataConflictException>()),
    );
    expect(
      (await fixture.world.listWorldCards(
        'project-1',
      )).map((item) => '${item.id}:${item.sortOrder}'),
      ['world-1:0', 'world-2:1'],
    );
  });

  test('character soft delete and restore survive database reopen', () async {
    final fixture = await SqliteFixture.create();
    await fixture.projects.upsertProject(project('project-1'));
    await fixture.characters.upsertCharacter(
      characterCard('character-1', 'project-1', 0),
    );
    await fixture.characters.softDeleteCharacter(
      'character-1',
      DateTime.utc(2026, 7, 30, 10),
    );
    var reopened = await reopenFixture(fixture);
    expect(await reopened.characters.listCharacters('project-1'), isEmpty);
    await reopened.characters.restoreCharacter(
      'character-1',
      DateTime.utc(2026, 7, 30, 11),
    );
    reopened = await reopenFixture(reopened);
    final restored = await reopened.characters.getCharacter('character-1');
    expect(restored.deletedAt, isNull);
    expect(restored.revision, 3);
  });

  test('world soft delete and restore survive database reopen', () async {
    final fixture = await SqliteFixture.create();
    await fixture.projects.upsertProject(project('project-1'));
    await fixture.world.upsertWorldCard(worldCard('world-1', 'project-1', 0));
    await fixture.world.softDeleteWorldCard(
      'world-1',
      DateTime.utc(2026, 7, 30, 10),
    );
    var reopened = await reopenFixture(fixture);
    expect(await reopened.world.listWorldCards('project-1'), isEmpty);
    await reopened.world.restoreWorldCard(
      'world-1',
      DateTime.utc(2026, 7, 30, 11),
    );
    reopened = await reopenFixture(reopened);
    final restored = await reopened.world.getWorldCard('world-1');
    expect(restored.deletedAt, isNull);
    expect(restored.revision, 3);
  });
}
