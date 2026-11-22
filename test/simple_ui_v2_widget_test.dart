import 'package:ibukihome/app/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/application/projects/current_project_controller.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/chat/chat_message.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';

void main() {
  testWidgets('bottom navigation contains novel chat settings', (tester) async {
    await _pump(tester);
    for (final key in [
      const Key('bottom-nav-novel'),
      const Key('bottom-nav-chat'),
      const Key('bottom-nav-settings'),
    ]) {
      expect(find.byKey(key), findsOneWidget);
    }
  });

  testWidgets('message list is flat instead of a card dashboard', (
    tester,
  ) async {
    await _pump(tester, seedSession: true);
    _go(tester, AppRoutes.chat);
    await tester.pumpAndSettle();

    final list = find.byKey(const Key('chat-message-list'));
    expect(list, findsOneWidget);
    expect(
      find.descendant(of: list, matching: find.byType(Card)),
      findsNothing,
    );
  });

  testWidgets('contacts contain active ChatPersonas only', (tester) async {
    final container = await _pump(tester, seedSession: true);
    await container
        .read(chatPersonaRepositoryProvider)
        .softDeletePersona('character-2', _t1);
    container.read(dataChangeTickProvider.notifier).bump();
    _go(tester, AppRoutes.chat);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-add-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-menu-session')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('contact-character-1')), findsOneWidget);
    expect(find.byKey(const Key('contact-character-2')), findsNothing);
  });

  testWidgets('contact search filters real persona content', (tester) async {
    await _pump(tester, seedSession: true);
    _go(tester, AppRoutes.chat);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-add-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-menu-session')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('contact-search-field')),
      'quiet',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('contact-character-1')), findsOneWidget);
    expect(find.byKey(const Key('contact-character-2')), findsNothing);
  });

  testWidgets('contact profile shows ChatPersona content', (tester) async {
    await _pump(tester);
    _go(tester, AppRoutes.chatContact('character-1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Quiet but observant'), findsOneWidget);
    expect(find.byKey(const Key('message-character-button')), findsOneWidget);
  });

  testWidgets('contact message action creates a persona-bound session', (
    tester,
  ) async {
    final container = await _pump(tester);
    _go(tester, AppRoutes.chatContact('character-1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('message-character-button')));
    await tester.pumpAndSettle();

    final sessions = await container
        .read(chatRepositoryProvider)
        .listSessions(personaId: 'character-1');
    expect(sessions, hasLength(1));
    expect(find.byKey(const Key('chat-session-page')), findsOneWidget);
  });

  testWidgets('contact message action reuses the newest existing session', (
    tester,
  ) async {
    final container = await _pump(tester, seedSession: true);
    _go(tester, AppRoutes.chatContact('character-1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('message-character-button')));
    await tester.pumpAndSettle();

    expect(
      await container
          .read(chatRepositoryProvider)
          .listSessions(personaId: 'character-1'),
      hasLength(1),
    );
    expect(find.text('Ibuki'), findsWidgets);
  });

  testWidgets(
    'multiple sessions for one character remain independently visible',
    (tester) async {
      final container = await _pump(tester, seedSession: true);
      await container
          .read(chatRepositoryProvider)
          .upsertSession(
            _session('session-older', updatedAt: _t0, title: 'Old Ibuki'),
          );
      container.read(dataChangeTickProvider.notifier).bump();
      _go(tester, AppRoutes.chat);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('conversation-session-1')), findsOneWidget);
      expect(
        find.byKey(const Key('conversation-session-older')),
        findsOneWidget,
      );
    },
  );

  testWidgets('assistant message is aligned left with a character avatar', (
    tester,
  ) async {
    await _pump(tester, seedSession: true, seedRoles: true);
    _go(tester, AppRoutes.chatSession('session-1'));
    await tester.pumpAndSettle();

    final row = tester.widget<Row>(
      find.byKey(const Key('chat-message-assistant-message')),
    );
    expect(row.mainAxisAlignment, MainAxisAlignment.start);
    expect(
      find.descendant(
        of: find.byKey(const Key('chat-message-assistant-message')),
        matching: find.byType(CircleAvatar),
      ),
      findsOneWidget,
    );
  });

  testWidgets('user message is aligned right', (tester) async {
    await _pump(tester, seedSession: true, seedRoles: true);
    _go(tester, AppRoutes.chatSession('session-1'));
    await tester.pumpAndSettle();

    final row = tester.widget<Row>(
      find.byKey(const Key('chat-message-user-message')),
    );
    expect(row.mainAxisAlignment, MainAxisAlignment.end);
  });

  testWidgets('system message is centered and visually separate', (
    tester,
  ) async {
    await _pump(tester, seedSession: true, seedRoles: true);
    _go(tester, AppRoutes.chatSession('session-1'));
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(
      find.byKey(const Key('system-message-system-message')),
    );
    expect(text.textAlign, TextAlign.center);
  });

  testWidgets('assistant bubble renders complete 10000 character content', (
    tester,
  ) async {
    final container = await _pump(tester, seedSession: true);
    final content = List.generate(10000, (index) => '字').join();
    await container
        .read(chatRepositoryProvider)
        .appendMessage(
          _message(
            'assistant-long-message',
            role: ChatMessageRole.assistant,
            content: content,
            createdAt: _t1.add(const Duration(minutes: 1)),
          ),
        );
    container.read(dataChangeTickProvider.notifier).bump();
    _go(tester, AppRoutes.chatSession('session-1'));
    await tester.pumpAndSettle();

    final bubble = find.byKey(const Key('chat-message-assistant-long-message'));
    expect(bubble, findsOneWidget);
    final text = tester.widget<Text>(
      find.descendant(of: bubble, matching: find.text(content)),
    );
    expect(text.data, content);
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistant STOP message keeps manual continue menu', (
    tester,
  ) async {
    await _pump(tester, seedSession: true, seedRoles: true);
    _go(tester, AppRoutes.chatSession('session-1'));
    await tester.pumpAndSettle();

    await tester.longPress(
      find.byKey(const Key('message-bubble-actions-assistant-message')),
    );
    await tester.pumpAndSettle();
    expect(find.text('继续生成'), findsOneWidget);
    expect(find.text('重新生成'), findsOneWidget);
  });

  testWidgets('single chat hides bottom navigation and decorative mascot', (
    tester,
  ) async {
    await _pump(tester, seedSession: true);
    _go(tester, AppRoutes.chatSession('session-1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('primary-bottom-navigation')), findsNothing);
    expect(find.byKey(const Key('mascot-slot')), findsNothing);
  });

  testWidgets('simple chat fits a 360 by 800 viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester, seedSession: true);
    _go(tester, AppRoutes.chat);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('assistant bubbles have no permanent menu and use long press', (
    tester,
  ) async {
    await _pump(tester, seedSession: true, seedRoles: true);
    _go(tester, AppRoutes.chatSession('session-1'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('assistant-message-menu-assistant-message')),
      findsNothing,
    );
    expect(find.text('已完成'), findsNothing);
    expect(find.text('STOP'), findsNothing);

    await tester.longPress(
      find.byKey(const Key('message-bubble-actions-assistant-message')),
    );
    await tester.pumpAndSettle();

    expect(find.text('复制'), findsOneWidget);
    expect(find.text('继续生成'), findsOneWidget);
    expect(find.text('重新生成'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool seedSession = false,
  bool seedRoles = false,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await _seed(container, seedSession: seedSession, seedRoles: seedRoles);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const IbukiHomeApp(),
    ),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go(AppRoutes.novelEditor('project-1'));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _seed(
  ProviderContainer container, {
  required bool seedSession,
  required bool seedRoles,
}) async {
  await container
      .read(projectRepositoryProvider)
      .upsertProject(
        Project(
          metadata: _metadata('project-1'),
          title: 'Story',
          description: '',
        ),
      );
  await container
      .read(characterRepositoryProvider)
      .upsertCharacter(
        CharacterCard(
          metadata: _metadata('character-1'),
          projectId: 'project-1',
          name: 'Ibuki',
          content: 'Quiet but observant',
          sortOrder: 0,
        ),
      );
  for (final persona in [
    ChatPersona(
      metadata: _metadata('character-1'),
      name: 'Ibuki',
      descriptionMode: ChatPersonaDescriptionMode.simple,
      shortDescription: 'Quiet but observant',
      speakingStyle: 'Natural and concise',
    ),
    ChatPersona(
      metadata: _metadata('character-2'),
      name: 'Bell',
      descriptionMode: ChatPersonaDescriptionMode.simple,
      shortDescription: 'Energetic shopkeeper',
      speakingStyle: 'Cheerful',
    ),
  ]) {
    await container.read(chatPersonaRepositoryProvider).upsertPersona(persona);
  }
  await container
      .read(characterRepositoryProvider)
      .upsertCharacter(
        CharacterCard(
          metadata: _metadata('character-2'),
          projectId: 'project-1',
          name: 'Bell',
          content: 'Energetic shopkeeper',
          sortOrder: 1,
        ),
      );
  if (seedSession) {
    await container
        .read(chatRepositoryProvider)
        .upsertSession(_session('session-1'));
    await container
        .read(chatRepositoryProvider)
        .appendMessage(
          _message(
            'user-message',
            role: ChatMessageRole.user,
            content: 'Hello',
            createdAt: _t1,
          ),
        );
  }
  if (seedRoles) {
    await container
        .read(chatRepositoryProvider)
        .appendMessage(
          _message(
            'assistant-message',
            role: ChatMessageRole.assistant,
            content: 'Welcome back',
            createdAt: _t1.add(const Duration(minutes: 1)),
            finishReason: AiFinishReason.stop,
          ),
        );
    await container
        .read(chatRepositoryProvider)
        .appendMessage(
          _message(
            'system-message',
            role: ChatMessageRole.system,
            content: 'Local conversation',
            createdAt: _t1.add(const Duration(minutes: 2)),
          ),
        );
  }
  container
      .read(currentProjectControllerProvider.notifier)
      .selectProject('project-1');
  container.read(dataChangeTickProvider.notifier).bump();
}

ChatSession _session(String id, {String title = 'Ibuki', DateTime? updatedAt}) {
  return ChatSession(
    metadata: _metadata(id, updatedAt: updatedAt),
    projectId: null,
    personaId: 'character-1',
    characterId: null,
    title: title,
  );
}

ChatMessage _message(
  String id, {
  required ChatMessageRole role,
  required String content,
  required DateTime createdAt,
  AiFinishReason? finishReason,
}) {
  return ChatMessage(
    metadata: EntityMetadata(
      id: id,
      createdAt: createdAt,
      updatedAt: createdAt,
      revision: 1,
    ),
    sessionId: 'session-1',
    projectId: null,
    role: role,
    content: content,
    finishReason: finishReason,
  );
}

EntityMetadata _metadata(String id, {DateTime? updatedAt}) {
  return EntityMetadata(
    id: id,
    createdAt: _t0,
    updatedAt: updatedAt ?? _t0,
    revision: 1,
  );
}

void _go(WidgetTester tester, String location) {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
}

final _t0 = DateTime.utc(2026, 8, 10, 8);
final _t1 = DateTime.utc(2026, 8, 10, 9);
