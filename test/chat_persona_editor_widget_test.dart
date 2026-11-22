import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_router.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/application/chat/chat_avatar_store.dart';
import 'package:ibukihome/application/profile/profile_avatar_picker.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';

void main() {
  testWidgets('simple persona form saves optional avatar and paired examples', (
    tester,
  ) async {
    final bytes = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final image = await recorder.endRecording().toImage(8, 8);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      image.dispose();
      return bytes;
    }))!;
    final assets = InMemoryChatAvatarStore();
    final c = ProviderContainer(
      overrides: [
        profileAvatarPickerProvider.overrideWithValue(_Picker(bytes)),
        chatAvatarStoreProvider.overrideWithValue(assets),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const IbukiHomeApp()),
    );
    await tester.pumpAndSettle();
    c.read(appRouterProvider).go(AppRoutes.newChatPersona);
    await tester.pumpAndSettle();
    for (final label in ['角色描写', '说话方式', '简单描写', '详细描写', '自动长期记忆']) {
      expect(find.text(label), findsNothing);
    }
    await tester.tap(find.byKey(const Key('pick-persona-avatar')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('persona-name-field')), '云');
    await tester.enterText(
      find.byKey(const Key('persona-prompt-field')),
      '温柔、简短地回应。',
    );
    expect(find.byKey(const Key('add-persona-example')), findsNothing);
    await _show(tester, 'persona-examples-section');
    await tester.tap(find.text('语料库（选填）'));
    await tester.pumpAndSettle();
    await _show(tester, 'add-persona-example');
    await tester.tap(find.byKey(const Key('add-persona-example')));
    await tester.pumpAndSettle();
    await _show(tester, 'persona-example-user-0');
    await tester.enterText(
      find.byKey(const Key('persona-example-user-0')),
      '回来啦',
    );
    await tester.tap(find.byKey(const Key('save-chat-persona')));
    await tester.pumpAndSettle();
    expect(await c.read(chatPersonaRepositoryProvider).listPersonas(), isEmpty);
    await _show(tester, 'persona-example-ai-0');
    await tester.enterText(
      find.byKey(const Key('persona-example-ai-0')),
      '欢迎回来。',
    );
    await tester.tap(find.byKey(const Key('save-chat-persona')));
    await tester.pumpAndSettle();
    final saved =
        (await c.read(chatPersonaRepositoryProvider).listPersonas()).single;
    expect(saved.name, '云');
    expect(saved.personaPrompt, '温柔、简短地回应。');
    expect(saved.presetMessages.single.user, '回来啦');
    expect(saved.presetMessages.single.assistant, '欢迎回来。');
    expect(assets.assets[saved.avatarReference], bytes);
    expect(saved.avatarReference, startsWith('memory://chat-avatars/'));
    expect(await c.read(chatRepositoryProvider).listSessions(), isEmpty);

    c.read(appRouterProvider).go(AppRoutes.editChatPersona(saved.id));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('persona-example-user-0')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('persona-prompt-field')))
          .controller!
          .text,
      saved.personaPrompt,
    );
    final session = await c.read(createChatSessionProvider)(
      id: 'memory-session',
      title: '独立会话',
      personaId: saved.id,
      nowUtc: DateTime.now().toUtc(),
    );
    final other = await c.read(createChatSessionProvider)(
      id: 'other-session',
      title: '另一个会话',
      personaId: saved.id,
      nowUtc: DateTime.now().toUtc(),
    );
    c.invalidate(chatSessionListProvider);
    c.read(appRouterProvider).go(AppRoutes.chatMemorySettings);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('memory-settings-${session.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('session-auto-memory-${session.id}')));
    await tester.pumpAndSettle();
    final after = await c
        .read(chatPersonaRepositoryProvider)
        .getPersona(saved.id);
    expect(after.autoMemoryEnabled, isTrue);
    expect(
      (await c.read(chatMemoryServiceProvider).settings(session.id)).autoSave,
      isFalse,
    );
    expect(
      (await c.read(chatMemoryServiceProvider).settings(other.id)).autoSave,
      isTrue,
    );
    expect(after.personaPrompt, saved.personaPrompt);
    expect(after.presetMessages, saved.presetMessages);
    expect(after.avatarReference, saved.avatarReference);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _show(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

class _Picker implements ProfileAvatarPicker {
  _Picker(this.bytes);
  final Uint8List bytes;
  @override
  Future<Uint8List?> pick() async => bytes;
}
