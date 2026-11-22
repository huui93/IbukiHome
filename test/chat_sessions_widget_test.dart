import 'package:ibukihome/application/chat/chat_image_picker.dart';
import 'package:ibukihome/domain/chat/chat_image.dart';
import 'helpers/chat_image_fixture.dart';
import 'dart:collection';
import 'package:ibukihome/application/chat/chat_controls_providers.dart';
import 'package:ibukihome/domain/chat/chat_usage_record.dart';
import 'package:ibukihome/domain/ai/ai_token_usage.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/application/projects/current_project_controller.dart';
import 'package:ibukihome/application/plugins/plugin_providers.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/domain/chat/chat_message.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/plugins/ibuki_plugin_manifest.dart';
import 'package:ibukihome/domain/plugins/installed_plugin.dart';

void main() {
  testWidgets(
    'chat plus picks and removes a draft image without creating a message',
    (tester) async {
      final c = await _pumpChatApp(tester, imagePicker: _ImagePicker());
      await _seedLongSession(c, count: 0);
      _go(tester, AppRoutes.chatSession('session-long'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-tools-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-tool-image')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-image-draft')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('chat-send-button')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('chat-remove-image')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-image-draft')), findsNothing);
      expect(
        await c.read(chatRepositoryProvider).listMessages('session-long'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'image-only send persists binary locally and displays the pending image after reopening',
    (tester) async {
      final c = await _pumpChatApp(
        tester,
        imagePicker: _ImagePicker(),
        ids: ['image-message'],
      );
      await _seedLongSession(c, count: 0);
      _go(tester, AppRoutes.chatSession('session-long'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-tools-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-tool-image')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-send-button')));
      await tester.pumpAndSettle();
      final saved =
          (await c.read(chatRepositoryProvider).listMessages('session-long'))
              .single;
      expect(saved.image!.base64Data, imageFixtureBase64);
      expect(saved.image!.userText, '');
      expect(saved.content, '[图片]');
      expect(find.byKey(const Key('chat-image-draft')), findsNothing);
      _go(tester, AppRoutes.chat);
      await tester.pumpAndSettle();
      _go(tester, AppRoutes.chatSession('session-long'));
      await tester.pumpAndSettle();
      expect(find.text('图片待识别 · 可重试生成'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'settings exposes an independent vision selector following the current chat by default',
    (tester) async {
      await _pumpChatApp(tester);
      _go(tester, AppRoutes.settings);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settings-chat-vision')));
      await tester.tap(find.byKey(const Key('settings-chat-vision')));
      await tester.pumpAndSettle();
      expect(find.text('聊天识图模型'), findsOneWidget);
      expect(find.text('跟随当前聊天模型'), findsWidgets);
      await tester.tap(find.byKey(const Key('save-ai-binding')));
      await tester.pumpAndSettle();
      expect(find.text('聊天识图模型'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('/chat shows the session list', (tester) async {
    await _pumpChatApp(tester);

    expect(find.byKey(const Key('chat-home-page')), findsOneWidget);
    expect(find.byKey(const Key('empty-chat-sessions-state')), findsOneWidget);
  });

  testWidgets('empty session list shows the empty state', (tester) async {
    await _pumpChatApp(tester);

    expect(find.text('还没有消息'), findsOneWidget);
  });

  testWidgets('new chat page can be opened', (tester) async {
    await _pumpChatApp(tester);

    _go(tester, AppRoutes.newChatSession);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-persona-picker')), findsOneWidget);
  });

  testWidgets('new session requires choosing a chat persona', (tester) async {
    final container = await _pumpChatApp(tester);
    _go(tester, AppRoutes.newChatSession);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-persona-picker')), findsOneWidget);
    expect(
      await container.read(chatRepositoryProvider).listSessions(),
      isEmpty,
    );
    expect(find.byKey(const Key('chat-session-project-field')), findsNothing);
  });

  testWidgets('creating an unbound session opens the chat page', (
    tester,
  ) async {
    final container = await _pumpChatApp(tester, ids: ['session-1']);

    await _createSession(tester);

    final session = await container
        .read(chatRepositoryProvider)
        .getSession('session-1');
    expect(session.projectId, isNull);
    expect(find.byKey(const Key('chat-session-page')), findsOneWidget);
  });

  testWidgets('current novel project does not appear in chat creation', (
    tester,
  ) async {
    final container = await _pumpChatApp(
      tester,
      ids: ['session-1'],
      projects: [_project('project-1', title: '测试项目')],
      currentProjectId: 'project-1',
    );
    _go(tester, AppRoutes.newChatSession);
    await tester.pumpAndSettle();
    expect(find.text('测试项目'), findsNothing);
    expect(find.byKey(const Key('chat-session-project-field')), findsNothing);
    await _createSession(tester);
    final session = await container
        .read(chatRepositoryProvider)
        .getSession('session-1');
    expect(session.projectId, isNull);
    expect(session.characterId, isNull);
    expect(session.personaId, 'test-persona');
  });

  testWidgets('session appears in the list after returning', (tester) async {
    await _pumpChatApp(tester, ids: ['session-1']);
    await _createSession(tester, title: '列表会话');

    _go(tester, AppRoutes.chat);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('chat-session-tile-session-1')),
      findsOneWidget,
    );
    expect(find.text('列表会话'), findsOneWidget);
  });

  testWidgets('new session has an empty chat state', (tester) async {
    await _pumpChatApp(tester, ids: ['session-1']);
    await _createSession(tester);

    expect(find.byKey(const Key('empty-chat-messages-state')), findsOneWidget);
    expect(find.byKey(const Key('novel-auto-story-toggle')), findsNothing);
    expect(find.text('自动剧情'), findsNothing);
  });

  testWidgets('empty input cannot send', (tester) async {
    await _pumpChatApp(tester, ids: ['session-1']);
    await _createSession(tester);

    final button = tester.widget<IconButton>(
      find.byKey(const Key('chat-send-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('typing enables sending', (tester) async {
    await _pumpChatApp(tester, ids: ['session-1']);
    await _createSession(tester);

    await tester.enterText(find.byKey(const Key('chat-input-field')), '第一条');
    await tester.pump();

    final button = tester.widget<IconButton>(
      find.byKey(const Key('chat-send-button')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('sending adds a user message and clears input', (tester) async {
    await _pumpChatApp(tester, ids: ['session-1', 'message-1']);
    await _createSession(tester);

    await _sendMessage(tester, '第一条消息');

    expect(find.byKey(const Key('chat-message-message-1')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('chat-input-field')))
          .controller
          ?.text,
      isEmpty,
    );
  });

  testWidgets('saving failure keeps the draft text', (tester) async {
    await _pumpChatApp(tester, ids: ['session-1', 'message-1', 'message-1']);
    await _createSession(tester);
    await _sendMessage(tester, '第一条消息');

    await tester.enterText(find.byKey(const Key('chat-input-field')), '第二条消息');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat-send-button')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('chat-input-field')))
          .controller
          ?.text,
      '第二条消息',
    );
  });

  testWidgets('list shows message count and last summary', (tester) async {
    await _pumpChatApp(tester, ids: ['session-1', 'message-1']);
    await _createSession(tester);
    await _sendMessage(tester, '最后一条');

    _go(tester, AppRoutes.chat);
    await tester.pumpAndSettle();

    expect(find.text('测试会话'), findsOneWidget);
    expect(find.text('最后一条'), findsOneWidget);
  });

  testWidgets('assistant and system messages render when stored', (
    tester,
  ) async {
    final container = await _pumpChatApp(tester);
    await _seedSessionWithMessages(container);
    _go(tester, AppRoutes.chatSession('session-1'));
    await tester.pumpAndSettle();

    expect(find.text('助手消息'), findsOneWidget);
    expect(find.text('系统消息'), findsOneWidget);
  });

  testWidgets('UI does not create a fake assistant message', (tester) async {
    final container = await _pumpChatApp(
      tester,
      ids: ['session-1', 'message-1'],
    );
    await _createSession(tester);

    await _sendMessage(tester, '只保存用户消息');

    expect(
      await container.read(chatRepositoryProvider).listMessages('session-1'),
      hasLength(1),
    );
    expect(find.textContaining('正在想'), findsNothing);
  });

  testWidgets('generic enabled chat panel appears and disable removes it', (
    tester,
  ) async {
    final container = await _pumpChatApp(tester);
    await container
        .read(chatRepositoryProvider)
        .upsertSession(
          ChatSession(
            metadata: _metadata('plugin-session'),
            projectId: null,
            title: '插件会话',
          ),
        );
    final contributions = container.read(pluginContributionRegistryProvider);
    contributions.registerPlugin(_chatPanelPlugin());
    _go(tester, AppRoutes.chatSession('plugin-session'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat-session-detail-menu')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const Key('chat-plugin-entry-compat.sillytavern.ruby.poc-ruby-status'),
      ),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(10, 400));
    await tester.pumpAndSettle();

    contributions.unregisterPlugin('compat.sillytavern.ruby.poc');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-session-detail-menu')));
    await tester.pumpAndSettle();
    expect(find.text('RUBY'), findsNothing);
  });

  testWidgets('renaming refreshes the list and detail page', (tester) async {
    await _pumpChatApp(tester, ids: ['session-1']);
    await _createSession(tester, title: '旧标题');

    await tester.tap(find.byKey(const Key('chat-session-detail-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('rename-chat-session-field')),
      '新标题',
    );
    await tester.tap(
      find.byKey(const Key('confirm-rename-chat-session-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('新标题'), findsOneWidget);
  });

  testWidgets('unchanged rename does not increase revision', (tester) async {
    final container = await _pumpChatApp(tester, ids: ['session-1']);
    await _createSession(tester, title: '相同标题');
    final before = await container
        .read(chatRepositoryProvider)
        .getSession('session-1');

    await tester.tap(find.byKey(const Key('chat-session-detail-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirm-rename-chat-session-button')),
    );
    await tester.pumpAndSettle();

    final after = await container
        .read(chatRepositoryProvider)
        .getSession('session-1');
    expect(after.revision, before.revision);
  });

  testWidgets('deleting a session returns to the list', (tester) async {
    await _pumpChatApp(tester, ids: ['session-1']);
    await _createSession(tester);

    await _deleteVisibleSession(tester);

    expect(find.byKey(const Key('empty-chat-sessions-state')), findsOneWidget);
  });

  testWidgets('deleted session list shows deleted sessions', (tester) async {
    await _pumpChatApp(tester, ids: ['session-1']);
    await _createSession(tester);
    await _deleteVisibleSession(tester);

    _go(tester, AppRoutes.deletedChatSessions);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('deleted-chat-session-session-1')),
      findsOneWidget,
    );
  });

  testWidgets('restoring a deleted session keeps messages', (tester) async {
    final container = await _pumpChatApp(
      tester,
      ids: ['session-1', 'message-1'],
    );
    await _createSession(tester);
    await _sendMessage(tester, '恢复后还在');
    await _deleteVisibleSession(tester);
    _go(tester, AppRoutes.deletedChatSessions);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('restore-chat-session-session-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('chat-session-tile-session-1')),
      findsOneWidget,
    );
    expect(
      await container.read(chatRepositoryProvider).listMessages('session-1'),
      hasLength(1),
    );
  });

  testWidgets('unsent input asks for confirmation on toolbar back', (
    tester,
  ) async {
    await _pumpChatApp(tester, ids: ['session-1']);
    await _createSession(tester);

    await tester.enterText(find.byKey(const Key('chat-input-field')), '未发送');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('discard-chat-draft-dialog')), findsOneWidget);
  });

  testWidgets('Android back is intercepted for unsent input', (tester) async {
    await _pumpChatApp(tester, ids: ['session-1']);
    await _createSession(tester);

    await tester.enterText(find.byKey(const Key('chat-input-field')), '未发送');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('discard-chat-draft-dialog')), findsOneWidget);
  });

  testWidgets('deleted project is displayed as unavailable', (tester) async {
    final container = await _pumpChatApp(
      tester,
      ids: ['session-1'],
      projects: [_project('project-1', title: '测试项目')],
      currentProjectId: 'project-1',
    );
    await _createSession(tester);
    await container
        .read(projectRepositoryProvider)
        .softDeleteProject('project-1', DateTime.utc(2026, 8, 1, 10));
    container.read(dataChangeTickProvider.notifier).bump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-session-page')), findsOneWidget);
  });

  testWidgets('chat picker offers no novel or remote project associations', (
    tester,
  ) async {
    await _pumpChatApp(
      tester,
      projects: [_project('project-1', title: '本地项目')],
    );
    _go(tester, AppRoutes.newChatSession);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-session-project-field')), findsNothing);
    expect(find.text('本地项目'), findsNothing);
    expect(find.textContaining('电脑项目'), findsNothing);
  });

  testWidgets('small chat page has no overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpChatApp(tester, ids: ['session-1', 'message-1']);
    await _createSession(tester);
    await _sendMessage(tester, List.filled(20, '长消息').join('，'));

    expect(tester.takeException(), isNull);
  });

  testWidgets('dark chat list and page can build', (tester) async {
    await _pumpChatApp(tester, ids: ['session-1']);
    await _createSession(tester);

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
    _go(tester, AppRoutes.chat);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-home-page')), findsOneWidget);
    _go(tester, AppRoutes.chatSession('session-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-session-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local routes remain available after chat flow', (tester) async {
    await _pumpChatApp(tester);

    _go(tester, AppRoutes.projects);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('projects-page')), findsOneWidget);
    _go(tester, AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-page')), findsOneWidget);
  });

  testWidgets(
    'chat append preserves older reading position and returns to bottom',
    (tester) async {
      final container = await _pumpChatApp(tester);
      await _seedLongSession(container, count: 60);
      _go(tester, AppRoutes.chatSession('session-long'));
      await tester.pumpAndSettle();
      final list = find.byKey(const Key('instant-message-list'));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);

      await tester.drag(list, const Offset(0, 850));
      await tester.pumpAndSettle();
      final readingOffset = scrollable.position.pixels;
      expect(readingOffset, greaterThan(0));
      expect(
        readingOffset,
        lessThan(scrollable.position.maxScrollExtent - 160),
      );

      await container
          .read(chatRepositoryProvider)
          .appendMessage(
            ChatMessage(
              metadata: _metadata(
                'message-appended',
                createdAt: DateTime.utc(2026, 8, 1, 9),
              ),
              sessionId: 'session-long',
              projectId: null,
              role: ChatMessageRole.assistant,
              content: '最新消息。${'继续聊天。' * 10}',
            ),
          );
      container.read(repositoryRevisionsProvider.notifier).bump(const {
        RepositoryDataArea.chatMessages,
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(scrollable.position.pixels, closeTo(readingOffset, 1));
      expect(find.byKey(const Key('chat-scroll-to-bottom')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-appended')), findsNothing);

      await tester.tap(find.byKey(const Key('chat-scroll-to-bottom')));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);
      expect(find.byKey(const Key('chat-scroll-to-bottom')), findsNothing);
      expect(find.byKey(const ValueKey('message-appended')), findsOneWidget);
    },
  );

  testWidgets('chat append follows bottom without a zero-offset rebuild', (
    tester,
  ) async {
    final container = await _pumpChatApp(tester);
    await _seedLongSession(container, count: 36);
    _go(tester, AppRoutes.chatSession('session-long'));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('instant-message-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    await container
        .read(chatRepositoryProvider)
        .appendMessage(
          ChatMessage(
            metadata: _metadata(
              'message-new-bottom',
              createdAt: DateTime.utc(2026, 8, 1, 9),
            ),
            sessionId: 'session-long',
            projectId: null,
            role: ChatMessageRole.assistant,
            content: '最新回复。${'继续。' * 12}',
          ),
        );
    container.read(repositoryRevisionsProvider.notifier).bump(const {
      RepositoryDataArea.chatMessages,
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
    expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);
    expect(find.byKey(const Key('chat-scroll-to-bottom')), findsNothing);
  });
  testWidgets(
    'composer tools delete one latest message at a time including user',
    (tester) async {
      final c = await _pumpChatApp(tester);
      await _seedLongSession(c, count: 2);
      final last =
          (await c.read(chatRepositoryProvider).listMessages('session-long'))
              .last;
      await c
          .read(chatRepositoryProvider)
          .mutateLatestMessage(
            expected: last,
            replacement: last.copyWith(
              content: List.generate(60, (i) => '$i').join('\n'),
            ),
            nowUtc: DateTime.utc(2026, 8, 2),
          );
      _go(tester, AppRoutes.chatSession('session-long'));
      await tester.pumpAndSettle();
      for (final remaining in [1, 0]) {
        await tester.tap(find.byKey(const Key('chat-tools-button')));
        await tester.pumpAndSettle();
        expect(find.text('管理聊天文件'), findsNothing);
        expect(find.byKey(const Key('chat-tool-summary')), findsOneWidget);
        await tester.tap(find.byKey(const Key('chat-tool-delete')));
        await tester.pumpAndSettle();
        expect(
          tester
              .getSize(
                find
                    .descendant(
                      of: find.byType(AlertDialog),
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .height,
          lessThan(420),
        );
        await tester.tap(find.byKey(const Key('confirm-delete-chat-message')));
        await tester.pumpAndSettle();
        expect(
          await c.read(chatRepositoryProvider).listMessages('session-long'),
          hasLength(remaining),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'summary tools open local overview, usage shows unknown history and reasoning adapts to no model',
    (tester) async {
      await _pumpChatApp(tester, ids: ['session-1', 'memory-state']);
      await _createSession(tester);
      await tester.tap(find.byKey(const Key('chat-tools-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-tool-summary')));
      await tester.pumpAndSettle();
      expect(find.text('会话摘要'), findsOneWidget);
      expect(find.byKey(const Key('search-session-memory')), findsOneWidget);
      expect(find.text('还没有长期记忆。'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-tools-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-tool-usage')));
      await tester.pumpAndSettle();
      expect(find.text('暂无完整的服务用量记录'), findsOneWidget);
      expect(find.byKey(const Key('chat-usage-page')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-tools-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-tool-reasoning')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-reasoning-automatic')), findsOneWidget);
      expect(find.byKey(const Key('chat-reasoning-high')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'chat plus opens a compact floating menu instead of a bottom sheet',
    (tester) async {
      final c = await _pumpChatApp(tester);
      await _seedLongSession(c, count: 2);
      _go(tester, AppRoutes.chatSession('session-long'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-tools-button')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('chat-tools-menu'))).width,
        lessThanOrEqualTo(260),
      );
      expect(
        tester.getBottomLeft(find.byKey(const Key('chat-tools-menu'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('chat-tools-button'))).dy,
        ),
      );
      await tester.tapAt(const Offset(600, 40));
      await tester.pumpAndSettle();
      expect(
        await c.read(chatRepositoryProvider).listMessages('session-long'),
        hasLength(2),
      );
    },
  );
  testWidgets(
    'usage is a full page with separate actual and estimated counts at 320 width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = await _pumpChatApp(tester);
      await _seedSessionWithMessages(c);
      final repo = c.read(chatControlsRepositoryProvider);
      for (final actual in [true, false]) {
        await repo.recordUsage(
          ChatUsageRecord(
            id: actual ? 'actual' : 'estimate',
            sessionId: 'session-1',
            operation: 'chat-reply',
            providerId: 'provider',
            model: 'long-model-name-for-layout',
            status: 'stop',
            startedAt: DateTime.utc(2026),
            endedAt: DateTime.utc(2026),
            estimatedInputTokens: 900,
            estimatedOutputTokens: 400,
            usage: actual
                ? const AiTokenUsage(
                    inputTokens: 1000,
                    outputTokens: 500,
                    totalTokens: 1500,
                    cachedInputTokens: 200,
                    isFinal: true,
                  )
                : null,
          ),
        );
      }
      _go(tester, AppRoutes.chatSessionUsage('session-1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-usage-page')), findsOneWidget);
      expect(find.text('1,500'), findsOneWidget);
      expect(find.text('1,000'), findsOneWidget);
      expect(find.byKey(const Key('chat-usage-estimates')), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<ProviderContainer> _pumpChatApp(
  WidgetTester tester, {
  List<String> ids = const ['session-1', 'message-1', 'message-2'],
  List<Project> projects = const [],
  String? currentProjectId,
  ChatImagePicker? imagePicker,
}) async {
  final container = ProviderContainer(
    overrides: [
      if (imagePicker != null)
        chatImagePickerProvider.overrideWithValue(imagePicker),
      entityIdGeneratorProvider.overrideWithValue(_QueueIdGenerator(ids)),
      utcClockProvider.overrideWithValue(
        _FixedClock(DateTime.utc(2026, 8, 1, 8)),
      ),
    ],
  );
  addTearDown(container.dispose);
  for (final project in projects) {
    await container.read(projectRepositoryProvider).upsertProject(project);
  }
  if (currentProjectId != null) {
    container
        .read(currentProjectControllerProvider.notifier)
        .selectProject(currentProjectId);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const IbukiHomeApp(),
    ),
  );
  await tester.pumpAndSettle();
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(AppRoutes.chat);
  await tester.pumpAndSettle();
  return container;
}

Future<void> _createSession(
  WidgetTester tester, {
  String title = '测试会话',
}) async {
  final context = tester.element(find.byType(Scaffold).first);
  final container = ProviderScope.containerOf(context, listen: false);
  await container.read(createChatPersonaProvider)(
    id: 'test-persona',
    name: title,
    personaPrompt: '友善的聊天伙伴',
    nowUtc: DateTime.utc(2026, 8, 1),
  );
  container.read(dataChangeTickProvider.notifier).bump();
  _go(tester, AppRoutes.newChatSession);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('persona-test-persona')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('chat-session-page')), findsOneWidget);
}

Future<void> _sendMessage(WidgetTester tester, String content) async {
  await tester.enterText(find.byKey(const Key('chat-input-field')), content);
  await tester.pump();
  await tester.tap(find.byKey(const Key('chat-send-button')));
  await tester.pumpAndSettle();
}

Future<void> _deleteVisibleSession(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('chat-session-detail-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('删除'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('confirm-delete-chat-session-button')));
  await tester.pumpAndSettle();
}

Future<void> _seedSessionWithMessages(ProviderContainer container) async {
  final session = ChatSession(
    metadata: _metadata('session-1'),
    projectId: null,
    title: '带消息会话',
  );
  await container.read(chatRepositoryProvider).upsertSession(session);
  await container
      .read(chatRepositoryProvider)
      .appendMessage(
        ChatMessage(
          metadata: _metadata('message-assistant'),
          sessionId: 'session-1',
          projectId: null,
          role: ChatMessageRole.assistant,
          content: '助手消息',
        ),
      );
  await container
      .read(chatRepositoryProvider)
      .appendMessage(
        ChatMessage(
          metadata: _metadata(
            'message-system',
            createdAt: DateTime.utc(2026, 8, 1, 8, 1),
          ),
          sessionId: 'session-1',
          projectId: null,
          role: ChatMessageRole.system,
          content: '系统消息',
        ),
      );
  container.read(dataChangeTickProvider.notifier).bump();
}

InstalledPlugin _chatPanelPlugin() => InstalledPlugin(
  manifest: IbukiPluginManifest.fromJson({
    'manifestVersion': 1,
    'extensionApiVersion': 1,
    'id': 'compat.sillytavern.ruby.poc',
    'name': 'RUBY Compatibility PoC',
    'version': '0.1.0',
    'permissions': ['ui.extend'],
    'capabilities': ['chat-panel'],
    'contributions': {
      'chatPanels': [
        {'id': 'ruby-status', 'label': 'RUBY', 'entry': 'web/index.html'},
      ],
    },
  }),
  installedPath: '/private/plugins/compat.sillytavern.ruby.poc',
  dataPath: '/private/plugin_data/compat.sillytavern.ruby.poc',
  enabled: true,
  installedAt: DateTime.utc(2026, 8, 26),
  updatedAt: DateTime.utc(2026, 8, 26),
);

Future<void> _seedLongSession(
  ProviderContainer container, {
  required int count,
}) async {
  await container
      .read(chatRepositoryProvider)
      .upsertSession(
        ChatSession(
          metadata: _metadata('session-long'),
          projectId: null,
          title: '长聊天',
        ),
      );
  for (var index = 0; index < count; index += 1) {
    await container
        .read(chatRepositoryProvider)
        .appendMessage(
          ChatMessage(
            metadata: _metadata(
              'message-$index',
              createdAt: DateTime.utc(2026, 8, 1, 8, index),
            ),
            sessionId: 'session-long',
            projectId: null,
            role: index.isEven
                ? ChatMessageRole.user
                : ChatMessageRole.assistant,
            content: '第 $index 条消息。${'这是滚动稳定测试。' * 4}',
          ),
        );
  }
  container.read(dataChangeTickProvider.notifier).bump();
}

Project _project(String id, {String? title}) {
  return Project(metadata: _metadata(id), title: title ?? id, description: '');
}

EntityMetadata _metadata(String id, {DateTime? createdAt}) {
  final created = createdAt ?? DateTime.utc(2026, 8, 1, 8);
  return EntityMetadata(
    id: id,
    createdAt: created,
    updatedAt: created,
    revision: 1,
  );
}

void _go(WidgetTester tester, String location) {
  final candidateKeys = [
    const Key('chat-home-page'),
    const Key('chat-session-page'),
    const Key('new-chat-session-page'),
    const Key('deleted-chat-sessions-page'),
    const Key('projects-page'),
    const Key('settings-page'),
  ];
  for (final key in candidateKeys) {
    final finder = find.byKey(key);
    if (finder.evaluate().isNotEmpty) {
      GoRouter.of(tester.element(finder)).go(location);
      return;
    }
  }
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
}

class _QueueIdGenerator extends EntityIdGenerator {
  _QueueIdGenerator(Iterable<String> ids) : _ids = Queue.of(ids);

  final Queue<String> _ids;

  @override
  String nextId(String prefix) => _ids.removeFirst();
}

class _FixedClock extends UtcClock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

class _ImagePicker extends ChatImagePicker {
  @override
  Future<ChatImage?> pick() async => imageFixture();
}
