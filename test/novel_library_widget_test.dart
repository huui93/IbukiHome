import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_router.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/application/ai/ai_settings_controller.dart';
import 'package:ibukihome/application/projects/txt_novel_source.dart';
import 'package:ibukihome/application/projects/txt_novel_providers.dart';
import 'package:ibukihome/application/projects/novel_prompt_presets.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/data/memory/in_memory_secure_value_store.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/memory/story_memory_digest.dart';
import 'package:ibukihome/domain/memory/memory_generation_status.dart';

void main() {
  for (final page in ['outline', 'memory']) {
    testWidgets('deleted novels cannot edit their $page settings', (
      tester,
    ) async {
      final c = await pumpLibrary(tester);
      await c.read(projectRepositoryProvider).softDeleteProject('p1', now);
      await go(
        tester,
        c,
        page == 'outline'
            ? AppRoutes.projectOutline('p1')
            : AppRoutes.projectLongMemory('p1'),
      );
      expect(find.text('作品已删除。'), findsOneWidget);
      expect(find.byKey(const Key('add-outline-node-button')), findsNothing);
      expect(find.byKey(const Key('edit-story-memory')), findsNothing);
    });
  }
  testWidgets(
    'fanfic form validates its source and saves the original character name',
    (tester) async {
      final c = await pumpLibrary(tester);
      await go(tester, c, AppRoutes.newCharacter('p1'));
      await tester.tap(find.text('同人角色'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-character-button')));
      await tester.pumpAndSettle();
      expect(find.text('请填写作品名称'), findsOneWidget);
      expect(find.text('请填写原作角色名称'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('character-source-work-field')),
        '来源作品',
      );
      await tester.enterText(
        find.byKey(const Key('character-source-name-field')),
        '原作主角',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('character-content-field')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('character-content-field')),
        '这部小说中的角色内容',
      );
      await tester.tap(find.byKey(const Key('save-character-button')));
      await tester.pumpAndSettle();
      final card =
          (await c.read(characterRepositoryProvider).listCharacters('p1'))
              .single;
      expect(card.mode, CharacterCardMode.fanfic);
      expect(card.name, '原作主角');
      expect(card.sourceWorkTitle, '来源作品');
      expect(card.content, '这部小说中的角色内容');
      expect(
        await c.read(characterRepositoryProvider).listCharacters('p2'),
        isEmpty,
      );
    },
  );
  testWidgets(
    'TXT import previews a full file and creates a readable independent novel',
    (tester) async {
      final c = await pumpLibrary(
        tester,
        picker: FakeTxtPicker('导入小说.txt', '第一章\n来自 TXT 的完整正文。'),
      );
      await tester.tap(find.byKey(const Key('novel-import-txt')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-txt-novel')));
      await waitFor(tester, const Key('txt-novel-title'));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('txt-novel-title')))
            .controller!
            .text,
        '导入小说',
      );
      expect(find.textContaining('来自 TXT 的完整正文。'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-txt-import')));
      await tester.pumpAndSettle();
      final books = await c.read(projectRepositoryProvider).listProjects();
      final imported = books.singleWhere((p) => p.title == '导入小说');
      expect(books, hasLength(3));
      expect(imported.systemPrompt, isEmpty);
      await tester.tap(find.byKey(Key('project-tile-${imported.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('novel-reader-page')), findsOneWidget);
      expect(find.textContaining('来自 TXT 的完整正文。'), findsOneWidget);
      expect(
        (await c.read(projectRepositoryProvider).getProject('p1')).systemPrompt,
        '一号提示词',
      );
    },
  );
  testWidgets('canceling the file picker does not create a project', (
    tester,
  ) async {
    final c = await pumpLibrary(tester, picker: FakeTxtPicker(null, null));
    await go(tester, c, AppRoutes.importTxtNovel);
    await tester.tap(find.byKey(const Key('pick-txt-novel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('txt-novel-title')), findsNothing);
    expect(
      await c.read(projectRepositoryProvider).listProjects(),
      hasLength(2),
    );
  });
  testWidgets('invalid TXT shows an error without writing any story', (
    tester,
  ) async {
    final c = await pumpLibrary(tester, picker: FakeTxtPicker('空白.txt', ' \n'));
    await go(tester, c, AppRoutes.importTxtNovel);
    await tester.tap(find.byKey(const Key('pick-txt-novel')));
    await waitFor(tester, const Key('txt-import-error'));
    expect(find.text('这个 TXT 没有小说正文。'), findsOneWidget);
    expect(
      await c.read(projectRepositoryProvider).listProjects(),
      hasLength(2),
    );
  });
  testWidgets('prompt presets apply only after saving the chosen novel', (
    tester,
  ) async {
    final c = await pumpLibrary(tester);
    final preset = await c
        .read(novelPromptPresetServiceProvider)
        .save(name: '简洁风格', content: '克制、自然地叙述。');
    await go(tester, c, AppRoutes.projectCreationSettings('p1'));
    expect(find.byKey(const Key('outline-tab')), findsNothing);
    expect(find.byKey(const Key('long-memory-tab')), findsNothing);
    await tester.tap(find.byKey(const Key('choose-novel-preset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('novel-preset-${preset.id}')));
    await tester.pumpAndSettle();
    expect(
      (await c.read(projectRepositoryProvider).getProject('p1')).systemPrompt,
      '一号提示词',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('project-system-prompt-field')),
          )
          .controller!
          .text,
      preset.content,
    );
    await tester.tap(find.byKey(const Key('save-system-prompt-button')));
    await tester.pumpAndSettle();
    expect(
      (await c.read(projectRepositoryProvider).getProject('p1')).systemPrompt,
      preset.content,
    );
    expect(
      (await c.read(projectRepositoryProvider).getProject('p2')).systemPrompt,
      '二号提示词',
    );
    await c
        .read(novelPromptPresetServiceProvider)
        .save(name: '改过的方案', content: '新内容', previous: preset);
    expect(
      (await c.read(projectRepositoryProvider).getProject('p1')).systemPrompt,
      preset.content,
    );
  });
  testWidgets(
    'current prompt can be saved as a reusable preset and chosen by another novel',
    (tester) async {
      final c = await pumpLibrary(tester);
      await go(tester, c, AppRoutes.projectCreationSettings('p1'));
      await tester.enterText(
        find.byKey(const Key('project-system-prompt-field')),
        '细腻的对白',
      );
      await tester.tap(find.byKey(const Key('save-as-novel-preset')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('novel-preset-name')),
        '对白方案',
      );
      await tester.tap(find.byKey(const Key('save-novel-preset')));
      await tester.pumpAndSettle();
      final presets = await c.read(novelPromptPresetRepositoryProvider).list();
      expect(presets.single.name, '对白方案');
      expect(presets.single.content, '细腻的对白');
      await go(tester, c, AppRoutes.projectCreationSettings('p2'));
      await tester.tap(find.byKey(const Key('choose-novel-preset')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('novel-preset-${presets.single.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-system-prompt-button')));
      await tester.pumpAndSettle();
      expect(
        (await c.read(projectRepositoryProvider).getProject('p2')).systemPrompt,
        '细腻的对白',
      );
      expect(
        (await c.read(projectRepositoryProvider).getProject('p1')).systemPrompt,
        '一号提示词',
      );
    },
  );
  testWidgets('library supports editing and deleting a preset', (tester) async {
    final c = await pumpLibrary(tester);
    final preset = await c
        .read(novelPromptPresetServiceProvider)
        .save(name: '旧方案', content: '旧内容');
    await go(tester, c, AppRoutes.projectCreationSettings('p1'));
    await tester.tap(find.byKey(const Key('choose-novel-preset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('edit-novel-preset-${preset.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('novel-preset-name')), '新方案');
    await tester.enterText(
      find.byKey(const Key('novel-preset-content')),
      '新内容',
    );
    await tester.tap(find.byKey(const Key('save-novel-preset')));
    await tester.pumpAndSettle();
    expect(find.text('新方案'), findsOneWidget);
    await tester.tap(find.byKey(Key('delete-novel-preset-${preset.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('还没有提示词方案'), findsOneWidget);
    expect(
      (await c.read(projectRepositoryProvider).getProject('p1')).systemPrompt,
      '一号提示词',
    );
  });
  testWidgets(
    'outline and memory are separate routes and scoped to their own story',
    (tester) async {
      final c = await pumpLibrary(tester);
      for (final id in ['p1', 'p2']) {
        await c.read(createOutlineNodeProvider)(
          projectId: id,
          title: '$id 大纲',
          summary: '阶段',
          id: '$id-outline',
          nowUtc: now,
        );
        await c
            .read(novelMemoryRepositoryProvider)
            .upsertDigest(
              StoryMemoryDigest(
                metadata: meta('$id-memory'),
                projectId: id,
                content: '$id 独立记忆',
                sourceThroughOrder: 0,
                sourceFingerprint: id,
                status: MemoryGenerationStatus.valid,
              ),
            );
      }
      await go(tester, c, AppRoutes.projectOutline('p1'));
      expect(find.text('p1 大纲'), findsOneWidget);
      expect(find.text('p2 大纲'), findsNothing);
      await go(tester, c, AppRoutes.projectOutline('p2'));
      expect(find.text('p2 大纲'), findsOneWidget);
      expect(find.text('p1 大纲'), findsNothing);
      await go(tester, c, AppRoutes.projectLongMemory('p1'));
      expect(find.text('p1 独立记忆'), findsOneWidget);
      expect(find.text('p2 独立记忆'), findsNothing);
      await go(tester, c, AppRoutes.projectLongMemory('p2'));
      expect(find.text('p2 独立记忆'), findsOneWidget);
      expect(find.text('p1 独立记忆'), findsNothing);
    },
  );
  testWidgets(
    'original editing keeps legacy data without exposing AI or extra fields',
    (tester) async {
      final c = await pumpLibrary(tester);
      await c
          .read(characterRepositoryProvider)
          .upsertCharacter(
            CharacterCard(
              metadata: meta('oc'),
              projectId: 'p1',
              name: '人物',
              content: '既有内容',
              mode: CharacterCardMode.original,
              originalIdea: '旧构想',
              sortOrder: 0,
            ),
          );
      await go(tester, c, AppRoutes.editCharacter('p1', 'oc'));
      expect(find.byKey(const Key('character-ai-completion')), findsNothing);
      expect(
        find.byKey(const Key('character-original-idea-field')),
        findsNothing,
      );
      expect(find.byType(TextField), findsNWidgets(2));
      await tester.enterText(
        find.byKey(const Key('character-content-field')),
        '新内容',
      );
      await tester.tap(find.byKey(const Key('save-character-button')));
      await tester.pumpAndSettle();
      final saved = await c
          .read(characterRepositoryProvider)
          .getCharacter('oc');
      expect(saved.content, '新内容');
      expect(saved.originalIdea, '旧构想');
    },
  );
  testWidgets(
    'switching character modes retains input and works with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = await pumpLibrary(tester);
      await go(tester, c, AppRoutes.newCharacter('p1'));
      await tester.enterText(
        find.byKey(const Key('character-name-field')),
        '保留的名字',
      );
      await tester.tap(find.text('同人角色'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('character-source-work-field')),
        '来源作品',
      );
      await tester.tap(find.text('原创角色'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('character-name-field')))
            .controller!
            .text,
        '保留的名字',
      );
      expect(find.byKey(const Key('character-ai-completion')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

final now = DateTime.utc(2026, 11, 21);
EntityMetadata meta(String id) =>
    EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);

class FakeTxtPicker implements TxtNovelPicker {
  FakeTxtPicker(this.name, this.text);
  final String? name;
  final String? text;
  @override
  Future<TxtNovelFile?> pick() async => name == null
      ? null
      : TxtNovelFile(name!, Uint8List.fromList(utf8.encode(text!)));
}

Future<ProviderContainer> pumpLibrary(
  WidgetTester tester, {
  TxtNovelPicker? picker,
}) async {
  final c = ProviderContainer(
    overrides: [
      aiSecureValueStoreProvider.overrideWithValue(InMemorySecureValueStore()),
      if (picker != null) txtNovelPickerProvider.overrideWithValue(picker),
    ],
  );
  addTearDown(c.dispose);
  for (final id in ['p1', 'p2']) {
    await c
        .read(projectRepositoryProvider)
        .upsertProject(
          Project(
            metadata: meta(id),
            title: '$id 小说',
            description: '',
            systemPrompt: id == 'p1' ? '一号提示词' : '二号提示词',
          ),
        );
  }
  c.read(appRouterProvider).go(AppRoutes.novel);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: c, child: const IbukiHomeApp()),
  );
  await tester.pumpAndSettle();
  return c;
}

Future<void> go(WidgetTester tester, ProviderContainer c, String route) async {
  c.read(appRouterProvider).go(route);
  await tester.pumpAndSettle();
}

Future<void> waitFor(WidgetTester tester, Key key) async {
  for (var i = 0; i < 100 && find.byKey(key).evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
  expect(find.byKey(key), findsOneWidget);
}
