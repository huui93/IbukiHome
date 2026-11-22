import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/application/import/sillytavern_asset_store.dart';
import 'package:ibukihome/application/import/sillytavern_file_picker.dart';
import 'package:ibukihome/application/import/sillytavern_import_plan.dart';
import 'package:ibukihome/application/import/sillytavern_import_service.dart';
import 'package:ibukihome/data/cache/cached_repositories.dart';
import 'package:ibukihome/data/sqlite/sqlite_compatibility_import_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_world_roleplay_repository.dart';

import 'sqlite_test_helpers.dart';

void main() {
  test(
    'transaction imports update warm project and character caches',
    () async {
      final fixture = await SqliteFixture.create();
      final projects = CachedProjectRepository(fixture.projects);
      final characters = CachedCharacterRepository(fixture.characters);
      final service = SillyTavernImportService(
        repository: SQLiteCompatibilityImportRepository(fixture.database),
        projects: projects,
        characters: characters,
        worlds: SQLiteWorldRoleplayRepository(fixture.database),
        assets: InMemorySillyTavernImportAssetStore(),
        ids: EntityIdGenerator(),
        clock: const UtcClock(),
      );
      expect(await projects.listProjects(), isEmpty);
      final first = await service.inspect(const _CardSource('Mira'));
      final firstResult = await service.execute(
        await service.buildPlan(
          inspection: first,
          destination: const SillyTavernImportDestination(
            newProjectTitle: 'Imported cast',
          ),
        ),
      );
      final project = (await projects.listProjects()).single;
      expect(project.id, firstResult.character!.projectId);
      expect(await characters.listCharacters(project.id), hasLength(1));
      expect(
        await characters.listCharacters(project.id, includeDeleted: true),
        hasLength(1),
      );
      final second = await service.inspect(const _CardSource('Morgan'));
      final secondResult = await service.execute(
        await service.buildPlan(
          inspection: second,
          destination: SillyTavernImportDestination(projectId: project.id),
        ),
      );
      expect(
        (await characters.listCharacters(project.id)).map((c) => c.name),
        containsAll(['Mira', 'Morgan']),
      );
      expect(
        await characters.listCharacters(project.id, includeDeleted: true),
        hasLength(2),
      );
      expect(
        (await characters.getCharacter(secondResult.character!.id)).name,
        'Morgan',
      );
      expect(projects.metrics.writes, 0);
      expect(characters.metrics.writes, 0);
      expect(await fixture.characters.listCharacters(project.id), hasLength(2));

      final failed = await service.buildPlan(
        inspection: await service.inspect(const _CardSource('Uncommitted')),
        destination: SillyTavernImportDestination(projectId: project.id),
      );
      await SQLiteCompatibilityImportRepository(
        fixture.database,
      ).commitImport(SillyTavernImportWrite(payload: failed.payload));
      await expectLater(service.execute(failed), throwsA(anything));
      expect(await characters.listCharacters(project.id), hasLength(2));
      expect(await fixture.characters.listCharacters(project.id), hasLength(2));
    },
  );
}

class _CardSource implements SillyTavernImportSource {
  const _CardSource(this.name);
  final String name;
  List<int> get bytes => utf8.encode(
    jsonEncode({
      'spec': 'chara_card_v3',
      'spec_version': '3.0',
      'data': {'name': name, 'description': 'Synthetic cache regression'},
    }),
  );
  @override
  String get fileName => '$name.json';
  @override
  Future<int> length() async => bytes.length;
  @override
  Stream<List<int>> openRead() => Stream.value(bytes);
}
