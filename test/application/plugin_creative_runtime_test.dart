import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/ai/ai_generation_service.dart';
import 'package:ibukihome/application/ai/ai_model_resolver.dart';
import 'package:ibukihome/application/plugins/ibuki_chat_api.dart';
import 'package:ibukihome/application/plugins/ibuki_hook_bus.dart';
import 'package:ibukihome/application/plugins/ibuki_plugin_ai.dart';
import 'package:ibukihome/application/plugins/ibuki_plugin_context.dart';
import 'package:ibukihome/application/plugins/ibuki_prompt_pipeline.dart';
import 'package:ibukihome/application/plugins/ibuki_web_plugin_bridge.dart';
import 'package:ibukihome/application/plugins/plugin_contributions.dart';
import 'package:ibukihome/application/plugins/plugin_creative_state.dart';
import 'package:ibukihome/application/plugins/plugin_manager.dart';
import 'package:ibukihome/application/plugins/plugin_package_picker.dart';
import 'package:ibukihome/application/plugins/plugin_runtime.dart';
import 'package:ibukihome/application/plugins/plugin_storage.dart';
import 'package:ibukihome/core/errors/plugin_exceptions.dart';
import 'package:ibukihome/core/network/ai_provider_exceptions.dart';
import 'package:ibukihome/data/ai/ai_provider_client.dart';
import 'package:ibukihome/data/memory/in_memory_chat_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_plugin_registry.dart';
import 'package:ibukihome/data/memory/in_memory_plugin_storage_repository.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/domain/ai/ai_default_selection.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/plugins/ibuki_plugin_manifest.dart';
import 'package:ibukihome/domain/plugins/installed_plugin.dart';
import 'package:ibukihome/domain/plugins/plugin_creative_manifest.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_engine_models.dart';

void main() {
  group('creative manifest', () {
    test('parses prompt contribution and retains unknown fields', () {
      final manifest = _manifest();
      final contribution = manifest.parsePromptContributions().single;
      expect(contribution.supportedOperations, {
        PluginPromptOperation.novelGenerate,
        PluginPromptOperation.chatReply,
        PluginPromptOperation.worldDirector,
        PluginPromptOperation.worldNarration,
        PluginPromptOperation.worldCharacter,
      });
      expect(contribution.unknownFields['futureMode'], 'keep-me');
      expect(manifest.toJson()['promptContributions'], isNotEmpty);
    });

    test('retains unknown operation without executing it', () {
      final json = _manifestJson();
      (json['promptContributions'] as List).add({
        'id': 'future',
        'operations': ['future.operation'],
        'styleInstruction': 'future',
      });
      final parsed = IbukiPluginManifest.fromJson(
        json,
      ).parsePromptContributions().last;
      expect(parsed.operationKeys, ['future.operation']);
      expect(parsed.supportedOperations, isEmpty);
    });

    test('parses boolean enum number and string settings schema', () {
      final settings = _manifest().parseSettingsSchema();
      expect(settings['enabled']!.type, PluginSettingType.boolean);
      expect(settings['tone']!.type, PluginSettingType.enumeration);
      expect(settings['dialogueRatio']!.type, PluginSettingType.number);
      expect(settings['note']!.type, PluginSettingType.string);
    });

    test('invalid enum setting is rejected', () {
      final definition = _manifest().parseSettingsSchema()['tone']!;
      expect(
        () => definition.validate('unknown'),
        throwsA(isA<PluginException>()),
      );
    });
  });

  group('scope and settings persistence', () {
    late _CreativeHarness harness;
    setUp(() async => harness = await _CreativeHarness.create());

    test('installation does not apply a prompt plugin', () async {
      expect(await harness.states.bindingsFor(harness.plugin.id), isEmpty);
    });

    test('project binding persists across store recreation', () async {
      await harness.states.bind(
        plugin: harness.plugin,
        scope: const PluginScopeRef.project('project-a'),
      );
      final reopened = PluginCreativeStateStore(
        registry: harness.registry,
        storage: harness.storage,
      );
      expect(
        await reopened.bindingsFor(harness.plugin.id),
        contains(
          isA<PluginScopeBinding>().having(
            (item) => item.scope,
            'scope',
            const PluginScopeRef.project('project-a'),
          ),
        ),
      );
    });

    test('project settings are isolated', () async {
      await harness.states.setSetting(
        manifest: harness.plugin.manifest,
        scope: const PluginScopeRef.project('project-a'),
        key: 'dialogueRatio',
        value: 70,
      );
      expect(
        (await harness.states.settingsFor(
          harness.plugin.manifest,
          const PluginScopeRef.project('project-a'),
        ))['dialogueRatio'],
        70,
      );
      expect(
        (await harness.states.settingsFor(
          harness.plugin.manifest,
          const PluginScopeRef.project('project-b'),
        ))['dialogueRatio'],
        50,
      );
    });

    test('chat session settings are isolated from global', () async {
      await harness.states.setSetting(
        manifest: harness.plugin.manifest,
        scope: const PluginScopeRef.chatSession('chat-a'),
        key: 'tone',
        value: 'light',
      );
      expect(
        (await harness.states.settingsFor(
          harness.plugin.manifest,
          const PluginScopeRef.chatSession('chat-a'),
        ))['tone'],
        'light',
      );
      expect(
        (await harness.states.settingsFor(
          harness.plugin.manifest,
          const PluginScopeRef.global(),
        ))['tone'],
        'balanced',
      );
    });

    test('plugin storage clear preserves host scope state', () async {
      await harness.states.bind(
        plugin: harness.plugin,
        scope: const PluginScopeRef.project('project-a'),
      );
      final pluginStorage = PluginStorage(
        pluginId: harness.plugin.id,
        repository: harness.storage,
      );
      await pluginStorage.set('user-setting', true);
      await pluginStorage.clear();
      harness.states.invalidate(harness.plugin.id);
      expect(await pluginStorage.get('user-setting'), isNull);
      expect(await harness.states.bindingsFor(harness.plugin.id), isNotEmpty);
    });

    test(
      'same scope exclusive style conflict requires explicit switch',
      () async {
        final second = _installed(_manifest(id: 'dev.ibuki.second'));
        await harness.registry.upsertPlugin(second);
        await harness.states.bind(
          plugin: harness.plugin,
          scope: const PluginScopeRef.project('project-a'),
        );
        expect(
          () => harness.states.bind(
            plugin: second,
            scope: const PluginScopeRef.project('project-a'),
          ),
          throwsA(isA<PluginScopeConflictException>()),
        );
        await harness.states.bind(
          plugin: second,
          scope: const PluginScopeRef.project('project-a'),
          replaceConflicts: true,
        );
        expect(await harness.states.bindingsFor(harness.plugin.id), isEmpty);
      },
    );
  });

  group('prompt pipeline', () {
    late _CreativeHarness harness;
    setUp(() async => harness = await _CreativeHarness.create());

    test(
      'default novel pipeline leaves core request byte-for-byte unchanged',
      () async {
        final core = _request();
        final result = await harness.pipeline.apply(
          core,
          const PluginPromptContext(
            operation: PluginPromptOperation.novelGenerate,
            projectId: 'project-a',
          ),
        );
        expect(identical(result.request, core), isTrue);
        expect(result.diagnostics.contributionCount, 0);
      },
    );

    test('project A applies interpolated novel contribution', () async {
      await harness.bindProjectA();
      await harness.states.setSetting(
        manifest: harness.plugin.manifest,
        scope: const PluginScopeRef.project('project-a'),
        key: 'dialogueRatio',
        value: 70,
      );
      final result = await harness.pipeline.apply(
        _request(),
        const PluginPromptContext(
          operation: PluginPromptOperation.novelGenerate,
          projectId: 'project-a',
        ),
      );
      expect(result.request.systemPrompt, contains('对话比例 70'));
      expect(result.diagnostics.appliedPluginIds, [harness.plugin.id]);
    });

    test('project B remains Core default', () async {
      await harness.bindProjectA();
      final result = await harness.pipeline.apply(
        _request(),
        const PluginPromptContext(
          operation: PluginPromptOperation.novelGenerate,
          projectId: 'project-b',
        ),
      );
      expect(result.diagnostics.contributionCount, 0);
      expect(result.request.systemPrompt, 'CORE SYSTEM third person');
    });

    test('world plugin occupies only the lower priority prompt slot', () async {
      await harness.states.bind(
        plugin: harness.plugin,
        scope: const PluginScopeRef.worldSession('world-session-a'),
      );
      final result = await harness.pipeline.apply(
        const AiGenerationRequest(
          requestId: 'world-layer-request',
          systemPrompt:
              'CORE\nWORLD SYSTEM\nSESSION ADDITIONAL\n$worldPluginPromptLayerMarker\nWORLD CONTEXT\nUSER ACTION',
          messages: [],
        ),
        const PluginPromptContext(
          operation: PluginPromptOperation.worldDirector,
          worldId: 'world-a',
          worldSessionId: 'world-session-a',
        ),
      );
      final prompt = result.request.systemPrompt;
      expect(prompt, contains('对话比例 50'));
      expect(prompt, isNot(contains(worldPluginPromptLayerMarker)));
      expect(
        prompt.indexOf('SESSION ADDITIONAL'),
        lessThan(prompt.indexOf('对话比例 50')),
      );
      expect(
        prompt.indexOf('对话比例 50'),
        lessThan(prompt.indexOf('WORLD CONTEXT')),
      );
    });

    test('chat session scope applies only to its session', () async {
      await harness.states.bind(
        plugin: harness.plugin,
        scope: const PluginScopeRef.chatSession('chat-a'),
      );
      final active = await harness.pipeline.apply(
        _request(),
        const PluginPromptContext(
          operation: PluginPromptOperation.chatReply,
          chatSessionId: 'chat-a',
        ),
      );
      final inactive = await harness.pipeline.apply(
        _request(),
        const PluginPromptContext(
          operation: PluginPromptOperation.chatReply,
          chatSessionId: 'chat-b',
        ),
      );
      expect(active.diagnostics.contributionCount, 1);
      expect(inactive.diagnostics.contributionCount, 0);
    });

    test('global scope applies to novel and chat operations', () async {
      await harness.states.bind(
        plugin: harness.plugin,
        scope: const PluginScopeRef.global(),
      );
      for (final operation in [
        PluginPromptOperation.novelGenerate,
        PluginPromptOperation.chatReply,
      ]) {
        final result = await harness.pipeline.apply(
          _request(),
          PluginPromptContext(operation: operation),
        );
        expect(result.diagnostics.contributionCount, 1);
      }
    });

    test('creative and world prompt operations are addressable', () {
      expect(PluginPromptOperation.values.map((item) => item.key).toSet(), {
        'novel.generate',
        'novel.rewrite',
        'novel.modify',
        'novel.selectionModify',
        'chat.reply',
        'chat.continue',
        'world.director',
        'world.character',
        'world.narration',
      });
    });

    test(
      'Core and explicit user input remain after lower priority style',
      () async {
        await harness.bindProjectA();
        final result = await harness.pipeline.apply(
          _request(),
          const PluginPromptContext(
            operation: PluginPromptOperation.novelGenerate,
            projectId: 'project-a',
          ),
        );
        expect(
          result.request.systemPrompt,
          contains('CORE SYSTEM third person'),
        );
        expect(
          result.request.systemPrompt,
          endsWith('插件不得改变人物、事实、叙事人称或作者明确要求。'),
        );
        expect(
          result.request.messages.single.content,
          'USER EXPLICIT third person',
        );
      },
    );

    test('disable unregister restores Core without prompt pollution', () async {
      await harness.bindProjectA();
      harness.contributions.unregisterPlugin(harness.plugin.id);
      final result = await harness.pipeline.apply(
        _request(),
        const PluginPromptContext(
          operation: PluginPromptOperation.novelGenerate,
          projectId: 'project-a',
        ),
      );
      expect(result.request.systemPrompt, 'CORE SYSTEM third person');
    });

    test('throwing prompt hook falls back to Core', () async {
      await harness.bindProjectA();
      harness.hooks.subscribeTransform(
        pluginId: harness.plugin.id,
        hook: IbukiHook.beforeNovelPromptBuild,
        handler: (_) => throw StateError('boom'),
      );
      final result = await harness.pipeline.apply(
        _request(),
        const PluginPromptContext(
          operation: PluginPromptOperation.novelGenerate,
          projectId: 'project-a',
        ),
      );
      expect(result.request.systemPrompt, 'CORE SYSTEM third person');
      expect(result.userNotice, contains('默认创作流程'));
    });

    test(
      'safe prompt hook contributes style without replacing Core text',
      () async {
        await harness.bindProjectA();
        harness.hooks.subscribeTransform(
          pluginId: harness.plugin.id,
          hook: IbukiHook.afterPromptBuild,
          handler: (_) => {'styleInstruction': '句子更轻快'},
        );
        final result = await harness.pipeline.apply(
          _request(),
          const PluginPromptContext(
            operation: PluginPromptOperation.novelGenerate,
            projectId: 'project-a',
          ),
        );
        expect(result.request.systemPrompt, contains('句子更轻快'));
        expect(result.request.systemPrompt, contains('CORE SYSTEM'));
        expect(result.diagnostics.hookCount, 1);
      },
    );

    test('diagnostics contain IDs and counts but no prompt fields', () async {
      await harness.bindProjectA();
      final result = await harness.pipeline.apply(
        _request(),
        const PluginPromptContext(
          operation: PluginPromptOperation.novelGenerate,
          projectId: 'project-a',
        ),
      );
      expect(result.diagnostics.operation, 'novel.generate');
      expect(result.diagnostics.contributionCount, 1);
      expect(result.diagnostics.toString(), isNot(contains('USER EXPLICIT')));
    });

    test('diagnostics sink emits only structural prompt metadata', () {
      final messages = <String>[];
      final logger = PluginPromptDiagnosticsLogger(sink: messages.add);
      logger.record(
        const PluginPromptDiagnostics(
          operation: 'novel.generate',
          appliedPluginIds: ['dev.ibuki.creative'],
          scopeKeys: ['project:project-a'],
          pipelineStages: ['core', 'plugin-style', 'host-precedence-guard'],
          contributionCount: 1,
          hookCount: 0,
          failedPluginIds: [],
        ),
      );

      expect(messages, hasLength(1));
      expect(messages.single, contains('operation=novel.generate'));
      expect(messages.single, contains('plugins=dev.ibuki.creative'));
      expect(messages.single, isNot(contains('CORE SYSTEM')));
      expect(messages.single, isNot(contains('USER EXPLICIT')));
      expect(messages.single, isNot(contains('Authorization')));
    });
  });

  group('IbukiPluginAI and bridge', () {
    test('permission is required', () async {
      final environment = await _AiEnvironment.create();
      final plugin = _installed(_manifest(permissions: ['ai.prompt.modify']));
      expect(
        () => environment.host.generate(
          plugin: plugin,
          scope: const PluginScopeRef.global(),
          prompt: 'test',
        ),
        throwsA(
          isA<PluginException>().having(
            (error) => error.category,
            'category',
            PluginErrorCategory.permissionDenied,
          ),
        ),
      );
    });

    test('project scope uses project resolver binding', () async {
      final environment = await _AiEnvironment.create();
      final result = await environment.host.generate(
        plugin: environment.plugin,
        scope: const PluginScopeRef.project('project-a'),
        prompt: 'test',
      );
      expect(result.provider, 'gemini');
      expect(result.model, 'gemini-project-model');
      expect(
        environment.runtime.requests.single.providerConfigId,
        'gemini-project',
      );
    });

    test('chat scope uses chat session resolver binding', () async {
      final environment = await _AiEnvironment.create();
      final result = await environment.host.generate(
        plugin: environment.plugin,
        scope: const PluginScopeRef.chatSession('chat-a'),
        prompt: 'test',
      );
      expect(result.provider, 'deepseek');
      expect(result.model, 'deepseek-chat-model');
    });

    test('one active request per plugin is enforced', () async {
      final environment = await _AiEnvironment.create(gated: true);
      final first = environment.host.generate(
        plugin: environment.plugin,
        scope: const PluginScopeRef.global(),
        prompt: 'first',
      );
      await environment.runtime.started.future;
      expect(
        () => environment.host.generate(
          plugin: environment.plugin,
          scope: const PluginScopeRef.global(),
          prompt: 'second',
        ),
        throwsA(
          isA<PluginException>().having(
            (error) => error.category,
            'category',
            PluginErrorCategory.aiRequestBusy,
          ),
        ),
      );
      environment.runtime.release.complete();
      await first;
    });

    test('plugin disable hook cancels its active AI request', () async {
      final environment = await _AiEnvironment.create(gated: true);
      final future = environment.host.generate(
        plugin: environment.plugin,
        scope: const PluginScopeRef.global(),
        prompt: 'test',
      );
      await environment.runtime.started.future;
      await environment.hooks.publish(IbukiHook.onPluginDisabled, {
        'pluginId': environment.plugin.id,
      });
      await expectLater(future, throwsA(isA<PluginException>()));
      expect(environment.runtime.cancelObserved, isTrue);
    });

    test('bridge ai.generate returns safe result only', () async {
      final environment = await _AiEnvironment.create();
      final bridge = IbukiWebPluginBridge(
        context: IbukiPluginContext(
          plugin: environment.plugin,
          currentRoute: '/chat/chat-a',
          currentSessionId: 'chat-a',
          currentProjectId: null,
          storage: PluginStorage(
            pluginId: environment.plugin.id,
            repository: InMemoryPluginStorageRepository(),
          ),
          hooks: environment.hooks,
          chat: const _NoopChatApi(),
          ai: environment.host,
        ),
      );
      final response =
          jsonDecode(
                await bridge.handle(
                  jsonEncode({
                    'requestId': 'bridge-1',
                    'method': 'ai.generate',
                    'params': {'prompt': 'say ok', 'maxOutputTokens': 100},
                  }),
                ),
              )
              as Map<String, dynamic>;
      final result = response['result'] as Map<String, dynamic>;
      expect(result['text'], 'plugin result');
      expect(result.toString(), isNot(contains('apiKey')));
      expect(result.toString(), isNot(contains('Authorization')));
      expect(result.toString(), isNot(contains('headers')));
    });

    test('bridge denies ai.generate without permission', () async {
      final environment = await _AiEnvironment.create();
      final plugin = _installed(_manifest(permissions: const []));
      final bridge = IbukiWebPluginBridge(
        context: IbukiPluginContext(
          plugin: plugin,
          currentRoute: '/plugin',
          currentSessionId: null,
          currentProjectId: null,
          storage: PluginStorage(
            pluginId: plugin.id,
            repository: InMemoryPluginStorageRepository(),
          ),
          hooks: environment.hooks,
          chat: const _NoopChatApi(),
          ai: environment.host,
        ),
      );
      final response =
          jsonDecode(
                await bridge.handle(
                  jsonEncode({
                    'requestId': 'bridge-2',
                    'method': 'ai.generate',
                    'params': {'prompt': 'test'},
                  }),
                ),
              )
              as Map<String, dynamic>;
      expect(response['error']['code'], 'permission_denied');
      expect(environment.runtime.requests, isEmpty);
    });
  });

  group('real Creative Runtime demo packages', () {
    test(
      'Light Novel package installs, scopes, disables and restores Core',
      () async {
        final root = await Directory.systemTemp.createTemp('creative_demo_');
        addTearDown(() => root.delete(recursive: true));
        final registry = InMemoryPluginRegistry();
        final storage = InMemoryPluginStorageRepository();
        final contributions = PluginContributionRegistry();
        final hooks = IbukiHookBus();
        final manager = PluginManager(
          registry: registry,
          applicationSupportDirectory: root,
          picker: const _NullPicker(),
          runtime: DeclarativePluginRuntime(
            contributions: contributions,
            hooks: hooks,
          ),
          hookBus: hooks,
          storageRepository: storage,
        );
        final package = File(
          'artifacts/plugin-packages/Ibuki-LightNovel-Style.ibuki',
        );
        final prepared = await manager.prepareInstall(
          FilePluginPackageSource(package),
        );
        final installed = await manager.installPrepared(prepared);
        expect(installed.manifest.permissions, contains('ai.prompt.modify'));
        expect(installed.manifest.permissions, isNot(contains('ai.generate')));
        expect(contributions.promptContributions, isNotEmpty);

        final states = PluginCreativeStateStore(
          registry: registry,
          storage: storage,
        );
        await states.bind(
          plugin: installed,
          scope: const PluginScopeRef.project('project-a'),
        );
        final pipeline = CorePluginPromptPipeline(
          contributions: contributions,
          states: states,
          registry: registry,
          hooks: hooks,
          diagnosticsLogger: PluginPromptDiagnosticsLogger(),
        );
        final active = await pipeline.apply(
          _request(),
          const PluginPromptContext(
            operation: PluginPromptOperation.novelGenerate,
            projectId: 'project-a',
          ),
        );
        expect(active.request.systemPrompt, contains('轻小说'));
        await manager.disablePlugin(installed.id);
        final disabled = await pipeline.apply(
          _request(),
          const PluginPromptContext(
            operation: PluginPromptOperation.novelGenerate,
            projectId: 'project-a',
          ),
        );
        expect(disabled.request.systemPrompt, 'CORE SYSTEM third person');
        await manager.enablePlugin(installed.id);
        expect(contributions.promptContributions, isNotEmpty);
        await manager.uninstallPlugin(installed.id);
        expect(contributions.promptContributions, isEmpty);
      },
      skip:
          !File(
            'artifacts/plugin-packages/Ibuki-LightNovel-Style.ibuki',
          ).existsSync()
          ? 'Requires a local integration package'
          : false,
    );

    test(
      'AI Bridge development package declares only safe Host permissions',
      () async {
        final root = await Directory.systemTemp.createTemp('creative_bridge_');
        addTearDown(() => root.delete(recursive: true));
        final manager = PluginManager(
          registry: InMemoryPluginRegistry(),
          applicationSupportDirectory: root,
          picker: const _NullPicker(),
        );
        final prepared = await manager.prepareInstall(
          FilePluginPackageSource(
            File('artifacts/plugin-packages/Ibuki-AI-Bridge-Test.ibuki'),
          ),
        );
        expect(
          prepared.manifest.permissions,
          containsAll(['ui.extend', 'ai.generate']),
        );
        expect(prepared.manifest.permissions, isNot(contains('network')));
        expect(prepared.manifest.metadata['developmentOnly'], true);
        await manager.discardPrepared(prepared);
      },
      skip:
          !File(
            'artifacts/plugin-packages/Ibuki-AI-Bridge-Test.ibuki',
          ).existsSync()
          ? 'Requires a local integration package'
          : false,
    );
  });
}

Map<String, Object?> _manifestJson({
  String id = 'dev.ibuki.creative',
  List<String> permissions = const ['ai.prompt.modify', 'storage.private'],
}) => {
  'manifestVersion': 1,
  'extensionApiVersion': 1,
  'id': id,
  'name': 'Creative Test',
  'version': '1.0.0',
  'permissions': permissions,
  'capabilities': ['prompt'],
  'promptContributions': [
    {
      'id': 'style',
      'operations': [
        'novel.generate',
        'chat.reply',
        'world.director',
        'world.narration',
        'world.character',
      ],
      'styleInstruction': '对话比例 {{setting.dialogueRatio}}',
      'futureMode': 'keep-me',
    },
  ],
  'settingsSchema': {
    'enabled': {'type': 'boolean', 'default': true},
    'tone': {
      'type': 'enum',
      'values': ['light', 'balanced', 'serious'],
      'default': 'balanced',
    },
    'dialogueRatio': {'type': 'number', 'min': 0, 'max': 100, 'default': 50},
    'note': {'type': 'string', 'default': ''},
  },
};

IbukiPluginManifest _manifest({
  String id = 'dev.ibuki.creative',
  List<String> permissions = const ['ai.prompt.modify', 'storage.private'],
}) => IbukiPluginManifest.fromJson(
  Map<String, dynamic>.from(_manifestJson(id: id, permissions: permissions)),
);

InstalledPlugin _installed(IbukiPluginManifest manifest) => InstalledPlugin(
  manifest: manifest,
  installedPath: '/plugins/${manifest.id}',
  dataPath: '/plugin_data/${manifest.id}',
  enabled: true,
  installedAt: DateTime.utc(2026, 8, 27),
  updatedAt: DateTime.utc(2026, 8, 27),
);

AiGenerationRequest _request() => const AiGenerationRequest(
  requestId: 'core-request',
  systemPrompt: 'CORE SYSTEM third person',
  messages: [
    AiGenerationMessage(
      role: AiMessageRole.user,
      content: 'USER EXPLICIT third person',
    ),
  ],
);

class _CreativeHarness {
  _CreativeHarness({
    required this.registry,
    required this.storage,
    required this.states,
    required this.contributions,
    required this.hooks,
    required this.pipeline,
    required this.plugin,
  });

  final InMemoryPluginRegistry registry;
  final InMemoryPluginStorageRepository storage;
  final PluginCreativeStateStore states;
  final PluginContributionRegistry contributions;
  final IbukiHookBus hooks;
  final CorePluginPromptPipeline pipeline;
  final InstalledPlugin plugin;

  static Future<_CreativeHarness> create() async {
    final registry = InMemoryPluginRegistry();
    final storage = InMemoryPluginStorageRepository();
    final states = PluginCreativeStateStore(
      registry: registry,
      storage: storage,
    );
    final contributions = PluginContributionRegistry();
    final hooks = IbukiHookBus();
    final plugin = _installed(_manifest());
    await registry.upsertPlugin(plugin);
    contributions.registerPlugin(plugin);
    return _CreativeHarness(
      registry: registry,
      storage: storage,
      states: states,
      contributions: contributions,
      hooks: hooks,
      pipeline: CorePluginPromptPipeline(
        contributions: contributions,
        states: states,
        registry: registry,
        hooks: hooks,
        diagnosticsLogger: PluginPromptDiagnosticsLogger(),
      ),
      plugin: plugin,
    );
  }

  Future<void> bindProjectA() => states.bind(
    plugin: plugin,
    scope: const PluginScopeRef.project('project-a'),
  );
}

class _AiEnvironment {
  _AiEnvironment({
    required this.runtime,
    required this.hooks,
    required this.host,
    required this.plugin,
  });

  final _PluginAiRuntime runtime;
  final IbukiHookBus hooks;
  final CoreIbukiPluginAi host;
  final InstalledPlugin plugin;

  static Future<_AiEnvironment> create({bool gated = false}) async {
    final runtime = _PluginAiRuntime(gated: gated);
    final store = InMemoryIbukiStore();
    final projects = InMemoryProjectRepository(store);
    final chats = InMemoryChatRepository(store);
    final now = EntityMetadata(
      id: 'metadata-placeholder',
      createdAt: _date,
      updatedAt: _date,
      revision: 1,
    );
    await projects.upsertProject(
      Project(
        metadata: now.copyWith(id: 'project-a'),
        title: 'Project A',
        description: '',
        aiProviderConfigId: 'gemini-project',
        aiModel: 'gemini-project-model',
      ),
    );
    await chats.upsertSession(
      ChatSession(
        metadata: now.copyWith(id: 'chat-a'),
        projectId: null,
        personaId: null,
        title: 'Chat A',
        aiProviderConfigId: 'deepseek-chat',
        aiModel: 'deepseek-chat-model',
      ),
    );
    final hooks = IbukiHookBus();
    final host = CoreIbukiPluginAi(
      runtime: runtime,
      modelResolver: AiModelResolver(
        projects: projects,
        chats: chats,
        runtime: runtime,
      ),
      hooks: hooks,
    );
    return _AiEnvironment(
      runtime: runtime,
      hooks: hooks,
      host: host,
      plugin: _installed(
        _manifest(
          permissions: const [
            'ai.prompt.modify',
            'storage.private',
            'ai.generate',
          ],
        ),
      ),
    );
  }
}

class _PluginAiRuntime implements AiDetailedGenerationRuntime {
  _PluginAiRuntime({required this.gated});

  final bool gated;
  final List<AiGenerationRequest> requests = [];
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  bool cancelObserved = false;

  @override
  Future<AiResolvedProvider> resolveDefault() async {
    return _resolved('default-deepseek', 'deepseek-default');
  }

  @override
  Future<AiResolvedProvider> resolveSelection({
    String? providerConfigId,
    String? model,
  }) async {
    return _resolved(
      providerConfigId ?? 'default-deepseek',
      model ?? 'deepseek-default',
    );
  }

  AiResolvedProvider _resolved(String providerId, String model) {
    final gemini = providerId.contains('gemini');
    return AiResolvedProvider(
      config: AiProviderConfig(
        id: providerId,
        type: gemini ? AiProviderType.gemini : AiProviderType.deepseek,
        displayName: gemini ? 'Gemini' : 'DeepSeek',
        baseUrl: 'https://example.invalid',
        apiKeyRef: 'secret-never-returned',
        selectedModel: model,
        enabled: true,
        connectionStatus: AiProviderConnectionStatus.connected,
        availableModels: [model],
        createdAtUtc: _date,
        updatedAtUtc: _date,
      ),
      selection: AiDefaultSelection(
        providerId: providerId,
        modelId: model,
        updatedAtUtc: _date,
      ),
    );
  }

  @override
  Stream<AiStreamEvent> streamEvents(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    requests.add(request);
    if (!started.isCompleted) started.complete();
    if (gated) {
      while (!release.isCompleted) {
        if (cancellation?.isCancelled == true) {
          cancelObserved = true;
          throw const AiProviderCancelledException();
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }
    yield const AiStreamEvent.content('plugin result');
    yield const AiStreamEvent.finished(AiFinishReason.stop);
  }

  @override
  Stream<String> stream(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    await for (final event in streamEvents(
      request,
      cancellation: cancellation,
    )) {
      if (!event.isTerminal) yield event.content;
    }
  }

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async => 'plugin result';
}

class _NoopChatApi implements IbukiChatApi {
  const _NoopChatApi();

  @override
  Future<PluginCharacterView?> getCurrentPersona() async => null;

  @override
  Future<PluginChatSessionView?> getCurrentSession() async => null;

  @override
  Future<PluginCharacterView?> getSafeCharacterContext() async => null;

  @override
  Future<List<PluginChatMessageView>> getMessages() async => const [];

  @override
  Future<List<PluginChatMessageView>> getRecentMessages({
    int limit = 30,
  }) async => const [];
}

class _NullPicker implements PluginPackagePicker {
  const _NullPicker();

  @override
  Future<PluginPackageSource?> pickPlugin() async => null;
}

final _date = DateTime.utc(2026, 8, 27);
