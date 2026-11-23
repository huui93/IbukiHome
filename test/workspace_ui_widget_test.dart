import 'package:ibukihome/app/routing/app_router.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/application/projects/current_project_controller.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/chat/chat_message.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/segments/segment.dart';
import 'package:ibukihome/domain/world/world_card.dart';

void main() {
  testWidgets('novel fixture opens the manuscript explicitly', (tester) async {
    await _pumpApp(tester);
    expect(find.byKey(const Key('novel-workspace-home')), findsOneWidget);
  });

  for (final label in ['小说', '聊天', '设置']) {
    testWidgets('primary navigation contains $label', (tester) async {
      await _pumpApp(tester);
      expect(find.text(label), findsWidgets);
    });
  }

  testWidgets('primary navigation has exactly three destinations', (
    tester,
  ) async {
    await _pumpApp(tester);
    for (final key in [
      const Key('bottom-nav-novel'),
      const Key('bottom-nav-chat'),
      const Key('bottom-nav-settings'),
    ]) {
      expect(find.byKey(key), findsOneWidget);
    }
  });

  testWidgets('primary navigation uses the three mascot image assets', (
    tester,
  ) async {
    await _pumpApp(tester);
    const expectedAssets = {
      '小说': 'assets/images/navigation/nav_novel.png',
      '聊天': 'assets/images/navigation/nav_chat.png',
      '设置': 'assets/images/navigation/nav_settings.png',
    };

    for (final entry in expectedAssets.entries) {
      final image = tester.widget<Image>(
        find.byKey(Key('bottom-nav-image-${entry.key}')),
      );
      expect((image.image as AssetImage).assetName, entry.value);
      expect(image.fit, BoxFit.contain);
      expect(image.color, isNull);
    }
  });

  testWidgets('navigation mascot assets have transparent canvas corners', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final asset in [
        'assets/images/navigation/nav_novel.png',
        'assets/images/navigation/nav_chat.png',
        'assets/images/navigation/nav_settings.png',
      ]) {
        final data = await rootBundle.load(asset);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        final frame = await codec.getNextFrame();
        final pixels = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(pixels, isNotNull, reason: asset);
        expect(
          pixels!.getUint8(3),
          0,
          reason: '$asset keeps an opaque backdrop',
        );
        frame.image.dispose();
        codec.dispose();
      }
    });
  });

  testWidgets('mascot selection animation keeps unselected items subdued', (
    tester,
  ) async {
    await _pumpApp(tester);

    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const Key('bottom-nav-image-opacity-小说')),
          )
          .opacity,
      1,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const Key('bottom-nav-image-opacity-聊天')),
          )
          .opacity,
      1,
    );

    await tester.tap(find.byKey(const Key('bottom-nav-settings')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<AnimatedScale>(
            find.byKey(const Key('bottom-nav-image-scale-小说')),
          )
          .scale,
      0.94,
    );
    expect(
      tester
          .widget<AnimatedScale>(
            find.byKey(const Key('bottom-nav-image-scale-设置')),
          )
          .scale,
      1.16,
    );
  });

  testWidgets('old total home is bypassed', (tester) async {
    await _pumpApp(tester);
    expect(find.byKey(const Key('app-home-page')), findsNothing);
  });

  testWidgets('novel root has no drawer', (tester) async {
    await _pumpApp(tester);
    expect(tester.widget<Scaffold>(find.byType(Scaffold).first).drawer, isNull);
  });

  testWidgets('chat root has no drawer', (tester) async {
    await _pumpApp(tester);
    _go(tester, AppRoutes.chat);
    await tester.pumpAndSettle();
    expect(tester.widget<Scaffold>(find.byType(Scaffold).first).drawer, isNull);
  });

  testWidgets('novel defaults to a quiet empty bookshelf', (tester) async {
    await _pumpApp(tester);
    expect(find.byKey(const Key('empty-novel-bookshelf')), findsOneWidget);
    expect(find.text('还没有创作的作品'), findsOneWidget);
    expect(find.byKey(const Key('novel-switch-project')), findsNothing);
    expect(find.byKey(const Key('novel-new-project')), findsNothing);
  });

  testWidgets('novel with project opens continuous manuscript', (tester) async {
    await _pumpApp(tester, seedData: true);
    expect(find.byKey(const Key('continuous-manuscript-list')), findsOneWidget);
    expect(find.text('第一段正文'), findsOneWidget);
  });

  testWidgets('novel exposes a lightweight work menu', (tester) async {
    await _pumpApp(tester, seedData: true);
    await tester.tap(find.byKey(const Key('novel-tab-settings')));
    await tester.pumpAndSettle();
    expect(find.text('切换作品'), findsOneWidget);
    expect(find.text('角色卡'), findsOneWidget);
    expect(find.text('世界观'), findsOneWidget);
  });

  testWidgets('novel composer exposes AI generation', (tester) async {
    await _pumpApp(tester, seedData: true);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('novel-generate-next')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('novel composer retains manual fallback', (tester) async {
    await _pumpApp(tester, seedData: true);
    expect(find.byKey(const Key('novel-extra-creation')), findsOneWidget);
    expect(find.byKey(const Key('new-segment-button')), findsNothing);
  });

  testWidgets('novel composer exposes character context', (tester) async {
    await _pumpApp(tester, seedData: true);
    await tester.tap(find.byKey(const Key('novel-character-context')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('novel-character-context-sheet')),
      findsOneWidget,
    );
    expect(find.text('人物甲'), findsOneWidget);
    expect(find.byKey(const Key('novel-quick-new-character')), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('novel-character-character-1')),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();
    final edit = find.byKey(const Key('edit-character-button'));
    final delete = find.byKey(const Key('delete-character-button'));
    final confirm = find.byKey(const Key('confirm-character-settings'));
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    expect(tester.getSize(confirm), tester.getSize(edit));
    expect(tester.getSize(confirm), tester.getSize(delete));
    expect(
      tester.getTopLeft(confirm).dy,
      greaterThan(tester.getTopLeft(edit).dy),
    );
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-character-context')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('novel-character-character-1')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('novel composer exposes world context', (tester) async {
    await _pumpApp(tester, seedData: true);
    await tester.tap(find.byKey(const Key('novel-world-context')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('novel-world-context-sheet')), findsOneWidget);
    expect(find.text('世界规则'), findsOneWidget);
    await tester.tap(find.byKey(const Key('novel-quick-new-world')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('world-card-title-field')),
      '新世界卡',
    );
    await tester.enterText(
      find.byKey(const Key('world-card-content-field')),
      '在环形城里。',
    );
    await tester.tap(find.byKey(const Key('save-world-card-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('continuous-manuscript-list')), findsOneWidget);
    await tester.tap(find.byKey(const Key('novel-world-context')));
    await tester.pumpAndSettle();
    final created = find.widgetWithText(CheckboxListTile, '新世界卡');
    expect(tester.widget<CheckboxListTile>(created).value, isTrue);
  });

  testWidgets('chat opens directly to messages', (tester) async {
    await _pumpApp(tester, seedData: true);
    await tester.tap(find.byKey(const Key('bottom-nav-chat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-message-list')), findsOneWidget);
    expect(find.text('本地消息'), findsOneWidget);
  });

  testWidgets('chat replaces tabs with the unified plus menu', (tester) async {
    await _pumpApp(tester);
    _go(tester, AppRoutes.chat);
    await tester.pumpAndSettle();
    expect(find.text('消息'), findsNothing);
    expect(find.text('联系人'), findsNothing);
  });

  testWidgets('contacts are backed by character cards', (tester) async {
    await _pumpApp(tester, seedData: true);
    _go(tester, AppRoutes.chat);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-add-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-menu-session')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contact-character-1')), findsOneWidget);
    expect(find.text('人物甲'), findsOneWidget);
  });

  testWidgets('contact opens a normal profile', (tester) async {
    await _pumpApp(tester, seedData: true);
    _go(tester, AppRoutes.chatContact('character-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('character-chat-profile')), findsOneWidget);
    expect(find.byKey(const Key('message-character-button')), findsOneWidget);
  });

  testWidgets('deep chat hides primary navigation', (tester) async {
    await _pumpApp(tester, seedData: true);
    _go(tester, AppRoutes.chatSession('session-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-session-page')), findsOneWidget);
    expect(find.byKey(const Key('primary-bottom-navigation')), findsNothing);
  });

  testWidgets('deep chat uses a compact AI provider entry', (tester) async {
    await _pumpApp(tester, seedData: true);
    _go(tester, AppRoutes.chatSession('session-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-ai-provider')), findsOneWidget);
    expect(find.text('尚未配置 AI'), findsOneWidget);
  });

  testWidgets('legacy routes still build', (tester) async {
    await _pumpApp(tester, seedData: true);
    _go(tester, AppRoutes.projects);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('projects-page')), findsOneWidget);
  });

  final deepRoutes = <String, Key>{
    AppRoutes.projectSegments('project-1'): const Key('segment-list-page'),
    AppRoutes.projectCharacters('project-1'): const Key('character-list-page'),
    AppRoutes.projectWorld('project-1'): const Key('world-card-list-page'),
    AppRoutes.settings: const Key('settings-page'),
    AppRoutes.remoteConnect: const Key('remote-connect-page'),
    AppRoutes.newChatSession: const Key('chat-persona-picker'),
    AppRoutes.deletedChatSessions: const Key('deleted-chat-sessions-page'),
  };
  for (final entry in deepRoutes.entries) {
    testWidgets('legacy deep route ${entry.key} remains available', (
      tester,
    ) async {
      await _pumpApp(tester, seedData: true);
      _go(tester, entry.key);
      await tester.pumpAndSettle();
      expect(find.byKey(entry.value), findsOneWidget);
    });
  }

  for (final route in [AppRoutes.novel, AppRoutes.chat, AppRoutes.world]) {
    testWidgets('$route has no workspace drawer', (tester) async {
      await _pumpApp(tester, seedData: true);
      _go(tester, route);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-drawer-button')), findsNothing);
      expect(find.byKey(const Key('app-drawer')), findsNothing);
    });
  }

  for (final size in [
    const Size(360, 800),
    const Size(393, 873),
    const Size(412, 915),
    const Size(480, 960),
  ]) {
    for (final route in [AppRoutes.novel, AppRoutes.chat]) {
      testWidgets('$route fits ${size.width} by ${size.height}', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _pumpApp(tester, seedData: true);
        _go(tester, route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final dark in [false, true]) {
    for (final route in [AppRoutes.novel, AppRoutes.chat, AppRoutes.world]) {
      testWidgets('$route builds in ${dark ? 'dark' : 'light'} mode', (
        tester,
      ) async {
        await _pumpApp(tester, seedData: true);
        if (dark) {
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
        }
        _go(tester, route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('tab switching keeps current project', (tester) async {
    final container = await _pumpApp(tester, seedData: true);
    await tester.tap(find.byKey(const Key('bottom-nav-chat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bottom-nav-novel')));
    await tester.pumpAndSettle();
    expect(container.read(currentProjectControllerProvider), 'project-1');
  });

  testWidgets('long project name does not overflow novel', (tester) async {
    await _pumpApp(tester, seedData: true, longNames: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text keeps primary navigation usable', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpApp(tester);
    expect(find.byKey(const Key('bottom-nav-chat')), findsOneWidget);
    expect(find.byKey(const Key('bottom-nav-world')), findsNothing);
  });
}

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  bool seedData = false,
  bool longNames = false,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  if (seedData) {
    await _seed(container, longNames: longNames);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const IbukiHomeApp(),
    ),
  );
  await tester.pumpAndSettle();
  container
      .read(appRouterProvider)
      .go(seedData ? AppRoutes.novelEditor('project-1') : AppRoutes.novel);
  await tester.pumpAndSettle();
  return container;
}

Future<void> _seed(
  ProviderContainer container, {
  required bool longNames,
}) async {
  final title = longNames ? '这是一个用于验证超长项目名称不会破坏底栏和正文布局的本地长篇小说项目' : '长篇测试项目';
  await container
      .read(projectRepositoryProvider)
      .upsertProject(
        Project(
          metadata: _metadata('project-1'),
          title: title,
          description: '项目说明',
        ),
      );
  await container
      .read(segmentRepositoryProvider)
      .upsertSegment(
        Segment(
          metadata: _metadata('segment-1'),
          projectId: 'project-1',
          orderIndex: 0,
          content: '第一段正文',
        ),
      );
  await container
      .read(characterRepositoryProvider)
      .upsertCharacter(
        CharacterCard(
          metadata: _metadata('character-1'),
          projectId: 'project-1',
          name: '人物甲',
          content: '人物设定',
          sortOrder: 0,
        ),
      );
  await container
      .read(chatPersonaRepositoryProvider)
      .upsertPersona(
        ChatPersona(
          metadata: _metadata('character-1'),
          name: '人物甲',
          descriptionMode: ChatPersonaDescriptionMode.simple,
          shortDescription: '人物设定',
          speakingStyle: '自然',
        ),
      );
  await container
      .read(worldRepositoryProvider)
      .upsertWorldCard(
        WorldCard(
          metadata: _metadata('world-1'),
          projectId: 'project-1',
          title: '世界规则',
          content: '世界观内容',
          sortOrder: 0,
        ),
      );
  await container
      .read(chatRepositoryProvider)
      .upsertSession(
        ChatSession(
          metadata: _metadata('session-1'),
          projectId: null,
          personaId: 'character-1',
          characterId: null,
          title: '人物甲',
        ),
      );
  await container
      .read(chatRepositoryProvider)
      .appendMessage(
        ChatMessage(
          metadata: _metadata('message-1'),
          sessionId: 'session-1',
          projectId: null,
          role: ChatMessageRole.user,
          content: '本地消息',
        ),
      );
  container
      .read(currentProjectControllerProvider.notifier)
      .selectProject('project-1');
  container.read(dataChangeTickProvider.notifier).bump();
}

EntityMetadata _metadata(String id) {
  final now = DateTime.utc(2026, 8, 2, 8);
  return EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);
}

void _go(WidgetTester tester, String location) {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
}
