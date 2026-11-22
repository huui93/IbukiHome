import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/application/projects/current_project_controller.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/world/world_card.dart';

void main() {
  testWidgets(
    'project overview shows manuscript, character and world entries',
    (tester) async {
      await _pumpApp(tester, seedProject: true);
      _go(tester, AppRoutes.project('project-1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('project-overview-open-segments')), findsOne);
      expect(
        find.byKey(const Key('project-overview-open-characters')),
        findsOne,
      );
      expect(find.byKey(const Key('project-overview-open-world')), findsOne);
    },
  );

  testWidgets('project overview counts only active cards', (tester) async {
    final container = await _pumpApp(tester, seedProject: true);
    await _seedCards(container, deleted: true);
    _go(tester, AppRoutes.project('project-1'));
    await tester.pumpAndSettle();
    expect(find.text('1 个角色'), findsOne);
    expect(find.text('1 张世界观卡'), findsOne);
  });

  testWidgets('character management without project opens projects', (
    tester,
  ) async {
    await _pumpApp(tester);
    _go(tester, AppRoutes.projects);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('projects-page')), findsOne);
  });

  testWidgets('retired world entry redirects to the retained Tavern lobby', (
    tester,
  ) async {
    await _pumpApp(tester);
    _go(tester, AppRoutes.world);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tavern-new-story')), findsOne);
  });

  testWidgets('character route uses current local project data', (
    tester,
  ) async {
    final container = await _pumpApp(tester, seedProject: true);
    container
        .read(currentProjectControllerProvider.notifier)
        .selectProject('project-1');
    _go(tester, AppRoutes.projectCharacters('project-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('character-list-page')), findsOne);
  });

  testWidgets('world card route uses current local project', (tester) async {
    final container = await _pumpApp(tester, seedProject: true);
    container
        .read(currentProjectControllerProvider.notifier)
        .selectProject('project-1');
    _go(tester, AppRoutes.projectWorld('project-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('world-card-list-page')), findsOne);
  });

  testWidgets('character list shows Chinese empty state', (tester) async {
    await _pumpApp(tester, seedProject: true);
    _go(tester, AppRoutes.projectCharacters('project-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('empty-characters-state')), findsOne);
    expect(find.text('这个项目还没有角色。'), findsOne);
  });

  testWidgets('new character page opens', (tester) async {
    await _pumpApp(tester, seedProject: true);
    _go(tester, AppRoutes.projectCharacters('project-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-character-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-character-page')), findsOne);
  });

  testWidgets(
    'new original character can be saved without a type-selection step',
    (tester) async {
      await _openNewCharacter(tester);
      await tester.tap(find.byKey(const Key('save-character-button')));
      await tester.pump();
      expect(find.text('创建空内容角色？'), findsOne);
      expect(find.text('请先选择同人角色或原创角色'), findsNothing);
    },
  );

  testWidgets('creating character opens detail and updates list', (
    tester,
  ) async {
    await _openNewCharacter(tester);
    await tester.tap(find.text('原创角色'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('character-name-field')), '伊吹');
    await tester.scrollUntilVisible(
      find.byKey(const Key('character-content-field')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('character-content-field')),
      '温柔又坚定。',
    );
    await tester.tap(find.byKey(const Key('save-character-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('character-detail-page')), findsOne);
    expect(find.text('伊吹'), findsOne);
    _go(tester, AppRoutes.projectCharacters('project-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('character-tile-character-1')), findsOne);
  });

  testWidgets('character detail opens editor', (tester) async {
    await _pumpApp(tester, seedProject: true, seedCards: true);
    _go(tester, AppRoutes.character('project-1', 'character-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-character-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-character-page')), findsOne);
  });

  testWidgets('unchanged character save does not increase revision', (
    tester,
  ) async {
    final container = await _pumpApp(
      tester,
      seedProject: true,
      seedCards: true,
    );
    _go(tester, AppRoutes.editCharacter('project-1', 'character-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-character-button')));
    await tester.pump();
    expect(
      (await container
              .read(characterRepositoryProvider)
              .getCharacter('character-1'))
          .revision,
      1,
    );
  });

  testWidgets('character delete confirmation moves card to deleted list', (
    tester,
  ) async {
    await _pumpApp(tester, seedProject: true, seedCards: true);
    _go(tester, AppRoutes.character('project-1', 'character-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-character-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delete-character-dialog')), findsOne);
    await tester.tap(find.byKey(const Key('confirm-delete-character-button')));
    await tester.pumpAndSettle();
    _go(tester, AppRoutes.deletedCharacters('project-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deleted-character-character-1')), findsOne);
  });

  testWidgets('deleted character can be restored', (tester) async {
    final container = await _pumpApp(
      tester,
      seedProject: true,
      seedCards: true,
    );
    await container
        .read(characterRepositoryProvider)
        .softDeleteCharacter('character-1', DateTime.utc(2026, 7, 30, 9));
    container.read(dataChangeTickProvider.notifier).bump();
    _go(tester, AppRoutes.deletedCharacters('project-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restore-character-character-1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('deleted-character-character-1')),
      findsNothing,
    );
    expect(
      await container
          .read(characterRepositoryProvider)
          .listCharacters('project-1'),
      hasLength(1),
    );
  });

  testWidgets('character down button changes order', (tester) async {
    final container = await _pumpApp(tester, seedProject: true);
    await _seedTwoCharacters(container);
    _go(tester, AppRoutes.projectCharacters('project-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('move-character-down-character-1')));
    await tester.pumpAndSettle();
    expect(
      (await container
              .read(characterRepositoryProvider)
              .listCharacters('project-1'))
          .map((item) => item.id),
      ['character-2', 'character-1'],
    );
  });

  testWidgets('forged project id cannot open another project character', (
    tester,
  ) async {
    await _pumpApp(tester, seedProject: true, seedCards: true);
    _go(tester, AppRoutes.character('wrong-project', 'character-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project-flow-error-view')), findsOne);
  });

  testWidgets('unsaved character edit intercepts Android back', (tester) async {
    await _pumpApp(tester, seedProject: true, seedCards: true);
    _go(tester, AppRoutes.character('project-1', 'character-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-character-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('character-content-field')),
      '尚未保存',
    );
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discard-character-changes-dialog')), findsOne);
  });

  testWidgets('world list shows Chinese empty state', (tester) async {
    await _pumpApp(tester, seedProject: true);
    _go(tester, AppRoutes.projectWorld('project-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('empty-world-cards-state')), findsOne);
    expect(find.text('这个项目还没有世界观卡。'), findsOne);
  });

  testWidgets('new world card page opens', (tester) async {
    await _pumpApp(tester, seedProject: true);
    _go(tester, AppRoutes.projectWorld('project-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-world-card-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-world-card-page')), findsOne);
  });

  testWidgets('empty world title cannot create', (tester) async {
    await _openNewWorldCard(tester);
    await tester.tap(find.byKey(const Key('save-world-card-button')));
    await tester.pump();
    expect(find.text('世界观标题不能为空'), findsOne);
  });

  testWidgets('creating world card opens detail and updates list', (
    tester,
  ) async {
    await _openNewWorldCard(tester);
    await tester.enterText(
      find.byKey(const Key('world-card-title-field')),
      '城市',
    );
    await tester.enterText(
      find.byKey(const Key('world-card-content-field')),
      '一座临海城市。',
    );
    await tester.tap(find.byKey(const Key('save-world-card-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('world-card-detail-page')), findsOne);
    _go(tester, AppRoutes.projectWorld('project-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('world-card-tile-world_card-1')), findsOne);
  });

  testWidgets('world detail opens editor and saves changes', (tester) async {
    final container = await _pumpApp(
      tester,
      seedProject: true,
      seedCards: true,
    );
    _go(tester, AppRoutes.worldCard('project-1', 'world-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-world-card-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('world-card-content-field')),
      '更新后的城市规则。',
    );
    await tester.tap(find.byKey(const Key('save-world-card-button')));
    await tester.pump();
    expect(
      (await container.read(worldRepositoryProvider).getWorldCard('world-1'))
          .revision,
      2,
    );
  });

  testWidgets('world delete and restore round trip', (tester) async {
    final container = await _pumpApp(
      tester,
      seedProject: true,
      seedCards: true,
    );
    _go(tester, AppRoutes.worldCard('project-1', 'world-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-world-card-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-world-card-button')));
    await tester.pumpAndSettle();
    _go(tester, AppRoutes.deletedWorldCards('project-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restore-world-card-world-1')));
    await tester.pumpAndSettle();
    expect(
      await container.read(worldRepositoryProvider).listWorldCards('project-1'),
      hasLength(1),
    );
  });

  testWidgets('world down button changes order', (tester) async {
    final container = await _pumpApp(tester, seedProject: true);
    await _seedTwoWorldCards(container);
    _go(tester, AppRoutes.projectWorld('project-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('move-world-card-down-world-1')));
    await tester.pumpAndSettle();
    expect(
      (await container
              .read(worldRepositoryProvider)
              .listWorldCards('project-1'))
          .map((item) => item.id),
      ['world-2', 'world-1'],
    );
  });

  testWidgets('forged project id cannot open another project world card', (
    tester,
  ) async {
    await _pumpApp(tester, seedProject: true, seedCards: true);
    _go(tester, AppRoutes.worldCard('wrong-project', 'world-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project-flow-error-view')), findsOne);
  });

  testWidgets('unsaved world edit intercepts Android back', (tester) async {
    await _pumpApp(tester, seedProject: true, seedCards: true);
    _go(tester, AppRoutes.worldCard('project-1', 'world-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-world-card-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('world-card-content-field')),
      '尚未保存',
    );
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('discard-world-card-changes-dialog')),
      findsOne,
    );
  });

  testWidgets('character and world pages fit 360 by 800', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpApp(tester, seedProject: true, seedCards: true);
    _go(tester, AppRoutes.projectCharacters('project-1'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    _go(tester, AppRoutes.projectWorld('project-1'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('character and world pages build in dark theme', (tester) async {
    await _pumpApp(tester, seedProject: true, seedCards: true);
    _go(tester, AppRoutes.settings);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-theme-switch')),
      220,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('settings-page')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-theme-switch')));
    await tester.pumpAndSettle();
    expect(
      Theme.of(
        tester.element(find.byKey(const Key('settings-theme-switch'))),
      ).brightness,
      Brightness.dark,
    );
    _go(tester, AppRoutes.projectCharacters('project-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('character-list-page')), findsOne);
    _go(tester, AppRoutes.projectWorld('project-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('world-card-list-page')), findsOne);
    expect(tester.takeException(), isNull);
  });
}

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  bool seedProject = false,
  bool seedCards = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      entityIdGeneratorProvider.overrideWithValue(_DeterministicIds()),
      utcClockProvider.overrideWithValue(
        _FixedClock(DateTime.utc(2026, 7, 30, 8)),
      ),
    ],
  );
  addTearDown(container.dispose);
  if (seedProject) {
    await container
        .read(projectRepositoryProvider)
        .upsertProject(_project('project-1'));
  }
  if (seedCards) {
    await _seedCards(container);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const IbukiHomeApp(),
    ),
  );
  await tester.pumpAndSettle();
  _go(tester, AppRoutes.novel);
  await tester.pumpAndSettle();
  return container;
}

Future<void> _seedCards(
  ProviderContainer container, {
  bool deleted = false,
}) async {
  await container
      .read(characterRepositoryProvider)
      .upsertCharacter(_character('character-1', 0));
  await container
      .read(worldRepositoryProvider)
      .upsertWorldCard(_world('world-1', 0));
  if (deleted) {
    await container
        .read(characterRepositoryProvider)
        .upsertCharacter(
          _character(
            'character-deleted',
            1,
            deletedAt: DateTime.utc(2026, 7, 30, 9),
          ),
        );
    await container
        .read(worldRepositoryProvider)
        .upsertWorldCard(
          _world('world-deleted', 1, deletedAt: DateTime.utc(2026, 7, 30, 9)),
        );
  }
  container.read(dataChangeTickProvider.notifier).bump();
}

Future<void> _seedTwoCharacters(ProviderContainer container) async {
  await container
      .read(characterRepositoryProvider)
      .upsertCharacter(_character('character-1', 0));
  await container
      .read(characterRepositoryProvider)
      .upsertCharacter(_character('character-2', 1));
  container.read(dataChangeTickProvider.notifier).bump();
}

Future<void> _seedTwoWorldCards(ProviderContainer container) async {
  await container
      .read(worldRepositoryProvider)
      .upsertWorldCard(_world('world-1', 0));
  await container
      .read(worldRepositoryProvider)
      .upsertWorldCard(_world('world-2', 1));
  container.read(dataChangeTickProvider.notifier).bump();
}

Future<void> _openNewCharacter(WidgetTester tester) async {
  await _pumpApp(tester, seedProject: true);
  _go(tester, AppRoutes.newCharacter('project-1'));
  await tester.pumpAndSettle();
}

Future<void> _openNewWorldCard(WidgetTester tester) async {
  await _pumpApp(tester, seedProject: true);
  _go(tester, AppRoutes.newWorldCard('project-1'));
  await tester.pumpAndSettle();
}

void _go(WidgetTester tester, String location) {
  final context = tester.element(find.byType(Scaffold).first);
  GoRouter.of(context).go(location);
}

Project _project(String id) {
  final now = DateTime.utc(2026, 7, 30, 8);
  return Project(
    metadata: EntityMetadata(
      id: id,
      createdAt: now,
      updatedAt: now,
      revision: 1,
    ),
    title: '角色世界观测试',
    description: '',
  );
}

CharacterCard _character(String id, int order, {DateTime? deletedAt}) {
  final now = DateTime.utc(2026, 7, 30, 8);
  return CharacterCard(
    metadata: EntityMetadata(
      id: id,
      createdAt: now,
      updatedAt: now,
      revision: deletedAt == null ? 1 : 2,
      deletedAt: deletedAt,
    ),
    projectId: 'project-1',
    name: id,
    content: '角色内容',
    sortOrder: order,
  );
}

WorldCard _world(String id, int order, {DateTime? deletedAt}) {
  final now = DateTime.utc(2026, 7, 30, 8);
  return WorldCard(
    metadata: EntityMetadata(
      id: id,
      createdAt: now,
      updatedAt: now,
      revision: deletedAt == null ? 1 : 2,
      deletedAt: deletedAt,
    ),
    projectId: 'project-1',
    title: id,
    content: '世界观内容',
    sortOrder: order,
  );
}

class _DeterministicIds extends EntityIdGenerator {
  final Map<String, int> _counts = {};

  @override
  String nextId(String prefix) {
    final count = (_counts[prefix] ?? 0) + 1;
    _counts[prefix] = count;
    return '$prefix-$count';
  }
}

class _FixedClock extends UtcClock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}
