import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/plugins/ibuki_chat_api.dart';
import 'package:ibukihome/application/plugins/ibuki_hook_bus.dart';
import 'package:ibukihome/application/plugins/ibuki_plugin_context.dart';
import 'package:ibukihome/application/plugins/ibuki_web_plugin_bridge.dart';
import 'package:ibukihome/application/plugins/plugin_contributions.dart';
import 'package:ibukihome/application/plugins/plugin_permissions.dart';
import 'package:ibukihome/application/plugins/plugin_runtime.dart';
import 'package:ibukihome/application/plugins/plugin_storage.dart';
import 'package:ibukihome/core/errors/plugin_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_chat_persona_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_plugin_storage_repository.dart';
import 'package:ibukihome/domain/chat/chat_message.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/plugins/ibuki_plugin_manifest.dart';
import 'package:ibukihome/domain/plugins/installed_plugin.dart';

void main() {
  group('Manifest forward compatibility', () {
    test('unknown top-level and nested future fields survive round trip', () {
      final source = <String, Object?>{
        ..._manifestJson(),
        'futureFeature': {
          'abc': 123,
          'nested': [true, 'kept'],
        },
        'contributions': {
          'futureSlot': {'mode': 'v2'},
        },
        'runtime': {
          'type': 'web',
          'futureRuntimeOption': {'isolation': 2},
        },
      };

      final first = IbukiPluginManifest.fromJson(
        source.cast<String, dynamic>(),
      );
      final second = IbukiPluginManifest.parse(first.encode());

      expect(second.toJson()['futureFeature'], source['futureFeature']);
      expect(second.contributions, source['contributions']);
      expect(second.runtime, source['runtime']);
      expect(second.capabilities, contains('future-capability'));
    });

    test('future extension API is rejected without crashing', () {
      final json = _manifestJson()..['extensionApiVersion'] = 3;
      expect(
        () => IbukiPluginManifest.fromJson(json.cast<String, dynamic>()),
        throwsA(
          isA<PluginException>().having(
            (error) => error.category,
            'category',
            PluginErrorCategory.incompatibleExtensionApi,
          ),
        ),
      );
    });
  });

  group('PluginStorage', () {
    test('supports every JSON-safe value category', () async {
      final storage = _storage('plugin.a');
      final values = <String, Object?>{
        'null': null,
        'bool': true,
        'number': 12.5,
        'string': 'RUBY',
        'list': [1, 'two', false],
        'map': {
          'nested': [1, 2],
        },
      };
      for (final entry in values.entries) {
        await storage.set(entry.key, entry.value);
        expect(await storage.get(entry.key), entry.value);
      }
    });

    test('namespaces the same key by bound plugin identity', () async {
      final repository = InMemoryPluginStorageRepository();
      final a = PluginStorage(pluginId: 'plugin.a', repository: repository);
      final b = PluginStorage(pluginId: 'plugin.b', repository: repository);
      await a.set('uiState', 'a');
      await b.set('uiState', 'b');
      expect(await a.get('uiState'), 'a');
      expect(await b.get('uiState'), 'b');
    });

    test('remove affects only one key', () async {
      final storage = _storage('plugin.a');
      await storage.set('one', 1);
      await storage.set('two', 2);
      await storage.remove('one');
      expect(await storage.get('one'), isNull);
      expect(await storage.get('two'), 2);
    });

    test('clear affects only the bound namespace', () async {
      final repository = InMemoryPluginStorageRepository();
      final a = PluginStorage(pluginId: 'plugin.a', repository: repository);
      final b = PluginStorage(pluginId: 'plugin.b', repository: repository);
      await a.set('state', 1);
      await b.set('state', 2);
      await a.clear();
      expect(await a.get('state'), isNull);
      expect(await b.get('state'), 2);
    });

    test('rejects non-JSON values', () async {
      final storage = _storage('plugin.a');
      await expectLater(
        storage.set('bad', DateTime.utc(2026)),
        throwsA(isA<PluginException>()),
      );
    });

    test('rejects oversized values', () async {
      final storage = PluginStorage(
        pluginId: 'plugin.a',
        repository: InMemoryPluginStorageRepository(),
        maxEncodedValueBytes: 10,
      );
      await expectLater(
        storage.set('large', '01234567890'),
        throwsA(isA<PluginException>()),
      );
    });

    test('rejects empty and control-character keys', () async {
      final storage = _storage('plugin.a');
      await expectLater(storage.set('', 1), throwsA(isA<PluginException>()));
      await expectLater(
        storage.set('bad\nkey', 1),
        throwsA(isA<PluginException>()),
      );
    });
  });

  group('Hook lifecycle', () {
    test('unsubscribe removes one owned listener', () async {
      final bus = IbukiHookBus();
      var calls = 0;
      final subscription = bus.subscribe(
        pluginId: 'plugin.a',
        hook: IbukiHook.afterAiResponse,
        handler: (_) => calls++,
      );
      await bus.publish(IbukiHook.afterAiResponse, const {});
      subscription.cancel();
      await bus.publish(IbukiHook.afterAiResponse, const {});
      expect(calls, 1);
    });

    test('removePlugin clears every listener owned by the plugin', () {
      final bus = IbukiHookBus();
      for (final hook in IbukiHook.values.take(3)) {
        bus.subscribe(pluginId: 'plugin.a', hook: hook, handler: (_) {});
      }
      expect(bus.subscriptionCount('plugin.a'), 3);
      bus.removePlugin('plugin.a');
      expect(bus.subscriptionCount('plugin.a'), 0);
    });

    test('enable-disable-enable does not accumulate listeners', () {
      final bus = IbukiHookBus();
      void enable() {
        bus.removePlugin('plugin.a');
        bus.subscribe(
          pluginId: 'plugin.a',
          hook: IbukiHook.afterChatMessageSaved,
          handler: (_) {},
        );
      }

      enable();
      expect(bus.subscriptionCount('plugin.a'), 1);
      bus.removePlugin('plugin.a');
      expect(bus.subscriptionCount('plugin.a'), 0);
      enable();
      expect(bus.subscriptionCount('plugin.a'), 1);
    });

    test('one throwing hook is isolated from other plugins', () async {
      final bus = IbukiHookBus();
      var secondCalled = false;
      bus.subscribe(
        pluginId: 'plugin.bad',
        hook: IbukiHook.afterChatMessageSaved,
        handler: (_) => throw StateError('safe test'),
      );
      bus.subscribe(
        pluginId: 'plugin.good',
        hook: IbukiHook.afterChatMessageSaved,
        handler: (_) => secondCalled = true,
      );
      final failures = await bus.publish(
        IbukiHook.afterChatMessageSaved,
        const {'messageId': 'safe-id'},
      );
      expect(secondCalled, true);
      expect(failures.single.pluginId, 'plugin.bad');
      expect(failures.single.hook, IbukiHook.afterChatMessageSaved);
    });
  });

  group('Read-only Chat API', () {
    test(
      'returns minimized DTOs for session, messages and character',
      () async {
        final fixture = await _chatFixture(
          permissions: const ['chat.read', 'character.read'],
        );
        final session = await fixture.api.getCurrentSession();
        final messages = await fixture.api.getMessages();
        final character = await fixture.api.getSafeCharacterContext();
        expect(session?.toJson().keys, {
          'id',
          'title',
          'projectId',
          'personaId',
        });
        expect(messages.single.toJson().keys, {
          'id',
          'role',
          'content',
          'createdAt',
        });
        expect(character?.toJson().keys, {'id', 'name', 'shortDescription'});
      },
    );

    test('chat read is denied without chat.read', () async {
      final fixture = await _chatFixture(permissions: const []);
      await expectLater(
        fixture.api.getMessages(),
        throwsA(
          isA<PluginException>().having(
            (error) => error.category,
            'category',
            PluginErrorCategory.permissionDenied,
          ),
        ),
      );
    });

    test('character read is denied without character.read', () async {
      final fixture = await _chatFixture(permissions: const ['chat.read']);
      await expectLater(
        fixture.api.getCurrentPersona(),
        throwsA(isA<PluginException>()),
      );
    });

    test('recent messages validates and bounds limit', () async {
      final fixture = await _chatFixture(permissions: const ['chat.read']);
      await expectLater(
        fixture.api.getRecentMessages(limit: 201),
        throwsArgumentError,
      );
      expect(await fixture.api.getRecentMessages(limit: 1), hasLength(1));
    });
  });

  group('Contribution lifecycle', () {
    test('enabled plugin registers generic chat panel', () {
      final registry = PluginContributionRegistry();
      addTearDown(registry.dispose);
      registry.registerPlugin(_installed());
      expect(registry.chatPanels.single.label, 'RUBY');
      expect(registry.chatPanels.single.entry, 'web/index.html');
    });

    test('disable unregisters generic chat panel', () {
      final registry = PluginContributionRegistry();
      addTearDown(registry.dispose);
      registry.registerPlugin(_installed());
      registry.unregisterPlugin('compat.sillytavern.ruby.poc');
      expect(registry.chatPanels, isEmpty);
    });

    test('registration requires ui.extend permission', () {
      final registry = PluginContributionRegistry();
      addTearDown(registry.dispose);
      expect(
        () => registry.registerPlugin(_installed(permissions: const [])),
        throwsA(isA<PluginException>()),
      );
    });

    test('declarative runtime unload clears contributions and hooks', () async {
      final registry = PluginContributionRegistry();
      addTearDown(registry.dispose);
      final hooks = IbukiHookBus();
      final runtime = DeclarativePluginRuntime(
        contributions: registry,
        hooks: hooks,
      );
      final plugin = _installed();
      await runtime.load(plugin);
      hooks.subscribe(
        pluginId: plugin.id,
        hook: IbukiHook.afterAiResponse,
        handler: (_) {},
      );
      await runtime.unload(plugin);
      expect(registry.chatPanels, isEmpty);
      expect(hooks.subscriptionCount(plugin.id), 0);
    });
  });

  group('Web bridge', () {
    test('allowlisted chat request returns structured result', () async {
      final harness = _bridgeHarness();
      final response = _decode(
        await harness.bridge.handle(_request('chat.getCurrentSession')),
      );
      expect(response['requestId'], 'request-1');
      expect((response['result'] as Map)['title'], 'RUBY test');
    });

    test(
      'context returns safe character only with character permission',
      () async {
        final response = _decode(
          await _bridgeHarness().bridge.handle(_request('context.get')),
        );
        expect((response['result'] as Map)['character'], isA<Map>());
      },
    );

    test('unknown method returns unknown_method', () async {
      final response = _decode(
        await _bridgeHarness().bridge.handle(_request('core.rawSql')),
      );
      expect((response['error'] as Map)['code'], 'unknown_method');
    });

    test('missing permission returns permission_denied', () async {
      final harness = _bridgeHarness(permissions: const ['ui.extend']);
      final response = _decode(
        await harness.bridge.handle(_request('chat.getMessages')),
      );
      expect((response['error'] as Map)['code'], 'permission_denied');
    });

    test('invalid recent limit returns invalid_arguments', () async {
      final response = _decode(
        await _bridgeHarness().bridge.handle(
          _request('chat.getRecentMessages', {'limit': 99999999}),
        ),
      );
      expect((response['error'] as Map)['code'], 'invalid_arguments');
    });

    test('plugin identity spoof is rejected', () async {
      final response = _decode(
        await _bridgeHarness().bridge.handle(
          _request('storage.get', {'key': 'uiState', 'pluginId': 'plugin.b'}),
        ),
      );
      expect((response['error'] as Map)['code'], 'identity_mismatch');
    });

    test('storage methods stay in bridge-bound namespace', () async {
      final repository = InMemoryPluginStorageRepository();
      final harness = _bridgeHarness(repository: repository);
      await harness.bridge.handle(
        _request('storage.set', {'key': 'ui.displayMode', 'value': 'compact'}),
      );
      expect(
        await PluginStorage(
          pluginId: 'compat.sillytavern.ruby.poc',
          repository: repository,
        ).get('ui.displayMode'),
        'compact',
      );
      expect(
        await PluginStorage(
          pluginId: 'another.plugin',
          repository: repository,
        ).get('ui.displayMode'),
        isNull,
      );
    });

    test('bridge diagnostics retain only safe statistical fields', () async {
      final logger = RollingPluginBridgeLogger(maxEntries: 2);
      final harness = _bridgeHarness(logger: logger);
      await harness.bridge.handle(_request('chat.getMessages'));
      final entry = logger.entries.single;
      expect(entry.pluginId, 'compat.sillytavern.ruby.poc');
      expect(entry.method, 'chat.getMessages');
      expect(entry.success, true);
      expect(entry.errorCode, isNull);
    });
  });
}

Map<String, Object?> _manifestJson() => {
  'manifestVersion': 1,
  'extensionApiVersion': 1,
  'id': 'compat.sillytavern.ruby.poc',
  'name': 'RUBY Compatibility PoC',
  'version': '0.1.0',
  'permissions': [
    'chat.read',
    'character.read',
    'storage.private',
    'ui.extend',
  ],
  'capabilities': ['chat-panel', 'future-capability'],
  'contributions': {
    'chatPanels': [
      {
        'id': 'ruby-status',
        'label': 'RUBY',
        'entry': 'web/index.html',
        'style': 'web/ruby_poc.css',
        'script': 'web/ruby_poc.js',
      },
    ],
  },
  'runtime': {'type': 'web'},
  'metadata': {'source': 'test'},
};

InstalledPlugin _installed({
  List<String> permissions = const [
    'chat.read',
    'character.read',
    'storage.private',
    'ui.extend',
  ],
}) {
  final manifest = _manifestJson()..['permissions'] = permissions;
  return InstalledPlugin(
    manifest: IbukiPluginManifest.fromJson(manifest.cast<String, dynamic>()),
    installedPath: '/private/plugins/compat.sillytavern.ruby.poc',
    dataPath: '/private/plugin_data/compat.sillytavern.ruby.poc',
    enabled: true,
    installedAt: DateTime.utc(2026, 8, 26),
    updatedAt: DateTime.utc(2026, 8, 26),
  );
}

PluginStorage _storage(String pluginId) => PluginStorage(
  pluginId: pluginId,
  repository: InMemoryPluginStorageRepository(),
);

Future<_ChatFixture> _chatFixture({required List<String> permissions}) async {
  final store = InMemoryIbukiStore();
  final chats = InMemoryChatRepository(store);
  final personas = InMemoryChatPersonaRepository(store);
  final persona = ChatPersona(
    metadata: _metadata('persona-1'),
    name: '林筱墨',
    descriptionMode: ChatPersonaDescriptionMode.simple,
    shortDescription: '安全摘要',
    speakingStyle: '',
  );
  final session = ChatSession(
    metadata: _metadata('session-1'),
    projectId: null,
    personaId: persona.id,
    title: 'RUBY test',
  );
  await personas.upsertPersona(persona);
  await chats.upsertSession(session);
  await chats.appendMessage(
    ChatMessage(
      metadata: _metadata('message-1'),
      sessionId: session.id,
      projectId: null,
      role: ChatMessageRole.user,
      content: '测试消息',
    ),
  );
  final manifest = IbukiPluginManifest.fromJson(
    (_manifestJson()..['permissions'] = permissions).cast<String, dynamic>(),
  );
  return _ChatFixture(
    CoreIbukiChatApi(
      sessionId: session.id,
      permissions: PluginPermissionGuard(manifest),
      chats: chats,
      personas: personas,
    ),
  );
}

class _ChatFixture {
  const _ChatFixture(this.api);

  final CoreIbukiChatApi api;
}

class _BridgeHarness {
  const _BridgeHarness(this.bridge);

  final IbukiWebPluginBridge bridge;
}

_BridgeHarness _bridgeHarness({
  List<String> permissions = const [
    'chat.read',
    'character.read',
    'storage.private',
    'ui.extend',
  ],
  InMemoryPluginStorageRepository? repository,
  PluginBridgeLogger logger = const NoopPluginBridgeLogger(),
}) {
  final plugin = _installed(permissions: permissions);
  final chat = _FakeChatApi();
  final context = IbukiPluginContext(
    plugin: plugin,
    currentRoute: '/chat/session-1',
    currentSessionId: 'session-1',
    currentProjectId: null,
    storage: PluginStorage(
      pluginId: plugin.id,
      repository: repository ?? InMemoryPluginStorageRepository(),
    ),
    hooks: IbukiHookBus(),
    chat: chat,
  );
  return _BridgeHarness(IbukiWebPluginBridge(context: context, logger: logger));
}

class _FakeChatApi implements IbukiChatApi {
  @override
  Future<PluginCharacterView?> getCurrentPersona() async {
    return const PluginCharacterView(
      id: 'persona-1',
      name: '林筱墨',
      shortDescription: 'safe',
    );
  }

  @override
  Future<PluginChatSessionView?> getCurrentSession() async {
    return const PluginChatSessionView(
      id: 'session-1',
      title: 'RUBY test',
      projectId: null,
      personaId: 'persona-1',
    );
  }

  @override
  Future<List<PluginChatMessageView>> getMessages() async {
    return [
      PluginChatMessageView(
        id: 'message-1',
        role: 'user',
        content: 'safe test',
        createdAt: DateTime.utc(2026, 8, 26),
      ),
    ];
  }

  @override
  Future<List<PluginChatMessageView>> getRecentMessages({
    int limit = 30,
  }) async {
    if (limit < 1 || limit > 200) throw ArgumentError('invalid limit');
    return getMessages();
  }

  @override
  Future<PluginCharacterView?> getSafeCharacterContext() {
    return getCurrentPersona();
  }
}

String _request(String method, [Map<String, Object?> params = const {}]) {
  return jsonEncode({
    'requestId': 'request-1',
    'method': method,
    'params': params,
  });
}

Map<String, dynamic> _decode(String source) {
  return jsonDecode(source) as Map<String, dynamic>;
}

EntityMetadata _metadata(String id) => EntityMetadata(
  id: id,
  createdAt: DateTime.utc(2026, 8, 26),
  updatedAt: DateTime.utc(2026, 8, 26),
  revision: 1,
);
