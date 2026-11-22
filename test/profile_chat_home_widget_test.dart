import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_router.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/application/ai/ai_settings_controller.dart';
import 'package:ibukihome/application/profile/local_user_profile.dart';
import 'package:ibukihome/application/profile/profile_avatar_picker.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/application/security/secure_value_store.dart';
import 'package:ibukihome/data/memory/in_memory_secure_value_store.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';

void main() {
  testWidgets('home has personal identity and a single conversation list', (
    tester,
  ) async {
    final c = await pump(tester);
    expect(find.byKey(const Key('chat-self-name')), findsOneWidget);
    expect(find.text('我'), findsOneWidget);
    expect(find.byKey(const Key('chat-home-tabs')), findsNothing);
    expect(find.text('联系人'), findsNothing);
    expect(find.byKey(const Key('chat-add-menu')), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('聊天')),
      findsNothing,
    );
    c.read(appRouterProvider).go(AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const Key('settings-personal-profile')), findsOneWidget);
    c.read(appRouterProvider).go(AppRoutes.novel);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('novel-tab-bookshelf')), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('小说')),
      findsNothing,
    );
  });

  testWidgets('plus dims the whole page and offers exactly three actions', (
    tester,
  ) async {
    await pump(tester);
    await menu(tester);
    for (final text in ['添加人格', '添加会话', '修改人格']) {
      expect(find.text(text), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const Key('chat-creation-menu')),
        matching: find.byType(ListTile),
      ),
      findsNWidgets(3),
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is ModalBarrier && w.color == Colors.black54 && w.dismissible,
      ),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(24, 360));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-creation-menu')), findsNothing);
    expect(find.byKey(const Key('chat-home-page')), findsOneWidget);
  });

  testWidgets('add persona opens the real persona editor', (tester) async {
    await pump(tester);
    await menu(tester);
    await tester.tap(find.byKey(const Key('chat-menu-persona')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-persona-editor')), findsOneWidget);
  });

  testWidgets('add session always creates a separate persona-bound session', (
    tester,
  ) async {
    final c = await pump(tester, seed: true);
    await menu(tester);
    await tester.tap(find.byKey(const Key('chat-menu-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact-p')));
    await tester.pumpAndSettle();
    final sessions = await c
        .read(chatRepositoryProvider)
        .listSessions(personaId: 'p');
    expect(sessions, hasLength(2));
    expect(sessions.map((s) => s.id).toSet(), hasLength(2));
    expect(find.byKey(const Key('chat-session-page')), findsOneWidget);
    expect(find.text('old-message-body'), findsNothing);
  });

  testWidgets('edit persona selects and loads the existing persona', (
    tester,
  ) async {
    await pump(tester, seed: true);
    await menu(tester);
    await tester.tap(find.byKey(const Key('chat-menu-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact-p')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-persona-editor')), findsOneWidget);
    final name = tester.widget<TextField>(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '名字',
      ),
    );
    expect(name.controller!.text, 'Mira');
  });

  testWidgets(
    'name and preset avatar update the header and survive reopening',
    (tester) async {
      final store = InMemorySecureValueStore();
      var c = await pump(tester, store: store);
      await tester.tap(find.byKey(const Key('bottom-nav-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-personal-profile')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('personal-name-field')),
        '试用者',
      );
      await tester.tap(find.byKey(const Key('personal-avatar-pink')));
      await tester.ensureVisible(
        find.byKey(const Key('save-personal-profile')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-personal-profile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('personal-profile-page')), findsNothing);
      c.read(appRouterProvider).go(AppRoutes.chat);
      await tester.pumpAndSettle();
      expect(find.text('试用者'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c = await pump(tester, store: store);
      expect(find.text('试用者'), findsOneWidget);
      expect(c.read(localUserProfileProvider).value!.avatar, 'pink');
    },
  );

  testWidgets('invalid name and write failure retain the profile draft', (
    tester,
  ) async {
    await pump(tester, store: FailingStore());
    await tester.tap(find.byKey(const Key('chat-self-profile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('personal-name-field')), '   ');
    await tester.tap(find.byKey(const Key('save-personal-profile')));
    await tester.pumpAndSettle();
    expect(find.text('名字不能为空'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('personal-name-field')),
      '保留草稿',
    );
    await tester.tap(find.byKey(const Key('save-personal-profile')));
    await tester.pumpAndSettle();
    expect(find.text('保存失败，修改内容仍在，请重试。'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('personal-name-field')))
          .controller!
          .text,
      '保留草稿',
    );
  });

  testWidgets('unsaved personal changes ask before leaving', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('chat-self-profile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('personal-name-field')), '未保存');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('personal-profile-page')), findsOneWidget);
  });

  testWidgets('local avatar selection is normalized, saved and reloaded', (
    tester,
  ) async {
    final data = await rootBundle.load('assets/images/navigation/nav_chat.png');
    final photo = await tester.runAsync(
      () => normalizeProfileAvatar(data.buffer.asUint8List()),
    );
    expect(photo, isNotNull);
    expect(photo!.length, lessThan(256 * 1024));
    final store = InMemorySecureValueStore();
    await pump(tester, store: store, picker: FixedPicker(photo));
    await tester.tap(find.byKey(const Key('chat-self-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-personal-avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-personal-profile')));
    await tester.pumpAndSettle();
    final profile = LocalUserProfile.decode(
      await store.read(LocalUserProfileController.storageKey),
    );
    expect(profile.photo, orderedEquals(photo));
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling photo selection preserves the current avatar', (
    tester,
  ) async {
    final c = await pump(tester, picker: FixedPicker(null));
    await tester.tap(find.byKey(const Key('chat-self-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-personal-avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-personal-profile')));
    await tester.pumpAndSettle();
    expect(c.read(localUserProfileProvider).value!.photo, isNull);
  });

  testWidgets('header and menu fit a narrow viewport with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = InMemorySecureValueStore();
    await store.write(
      LocalUserProfileController.storageKey,
      const LocalUserProfile(name: '这是一个用于验证顶部超长名字省略显示的本人名字').encode(),
    );
    await pump(tester, store: store);
    await menu(tester);
    expect(tester.takeException(), isNull);
  });
}

Future<ProviderContainer> pump(
  WidgetTester tester, {
  SecureValueStore? store,
  ProfileAvatarPicker? picker,
  bool seed = false,
}) async {
  final c = ProviderContainer(
    overrides: [
      aiSecureValueStoreProvider.overrideWithValue(
        store ?? InMemorySecureValueStore(),
      ),
      if (picker != null) profileAvatarPickerProvider.overrideWithValue(picker),
    ],
  );
  addTearDown(c.dispose);
  if (seed) {
    await c
        .read(chatPersonaRepositoryProvider)
        .upsertPersona(
          ChatPersona(
            metadata: meta('p'),
            name: 'Mira',
            descriptionMode: ChatPersonaDescriptionMode.simple,
            shortDescription: 'Quiet',
            speakingStyle: 'Natural',
          ),
        );
    await c
        .read(chatRepositoryProvider)
        .upsertSession(
          ChatSession(
            metadata: meta('existing'),
            projectId: null,
            personaId: 'p',
            title: 'Existing',
          ),
        );
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(container: c, child: const IbukiHomeApp()),
  );
  await tester.pumpAndSettle();
  return c;
}

EntityMetadata meta(String id) => EntityMetadata(
  id: id,
  createdAt: DateTime.utc(2026, 11, 21),
  updatedAt: DateTime.utc(2026, 11, 21),
  revision: 1,
);
Future<void> menu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('chat-add-menu')));
  await tester.pumpAndSettle();
}

class FixedPicker implements ProfileAvatarPicker {
  FixedPicker(this.photo);
  final Uint8List? photo;
  @override
  Future<Uint8List?> pick() async => photo;
}

class FailingStore extends InMemorySecureValueStore {
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('test storage failure');
}
