import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ibukihome/application/ai/ai_settings_controller.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/domain/ai/ai_default_selection.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/features/ai/presentation/ai_model_binding_sheet.dart';

void main() {
  testWidgets(
    'provider change clears stale model and persists project selection',
    (tester) async {
      final fixture = await _BindingFixture.create(tester);
      await fixture.open(tester, AiModelBindingScope.project);

      await tester.tap(find.byKey(const Key('ai-binding-override')));
      await tester.pump();
      await _chooseProvider(tester, 'Gemini');

      expect(_manualModel(tester), 'gemini-new');
      expect(_manualModel(tester), isNot('deepseek-old'));
      await tester.tap(find.byKey(const Key('save-ai-binding')));
      await tester.pumpAndSettle();

      var project = await fixture.container
          .read(projectRepositoryProvider)
          .getProject('project');
      expect(project.aiProviderConfigId, 'gemini');
      expect(project.aiModel, 'gemini-new');
      expect(
        (await fixture.container
                .read(aiModelResolverProvider)
                .resolveForProject('project'))
            .model,
        'gemini-new',
      );
      expect(_label(tester, 'project-ai-label'), 'Gemini · gemini-new');

      await fixture.open(tester, AiModelBindingScope.project);
      await _chooseProvider(tester, 'DeepSeek');
      expect(_manualModel(tester), 'deepseek-new');
      expect(find.text('gemini-new'), findsNothing);
      await tester.tap(find.byKey(const Key('save-ai-binding')));
      await tester.pumpAndSettle();

      project = await fixture.container
          .read(projectRepositoryProvider)
          .getProject('project');
      expect(project.aiProviderConfigId, 'deepseek');
      expect(project.aiModel, 'deepseek-new');
      expect(_label(tester, 'project-ai-label'), 'DeepSeek · deepseek-new');
    },
  );

  testWidgets(
    'chat session binding and follow default are persisted independently',
    (tester) async {
      final fixture = await _BindingFixture.create(tester);
      await fixture.open(tester, AiModelBindingScope.chatSession);

      await tester.tap(find.byKey(const Key('ai-binding-override')));
      await tester.pump();
      await _chooseProvider(tester, 'Gemini');
      await tester.tap(find.byKey(const Key('save-ai-binding')));
      await tester.pumpAndSettle();

      var session = await fixture.container
          .read(chatRepositoryProvider)
          .getSession('session');
      expect(session.aiProviderConfigId, 'gemini');
      expect(session.aiModel, 'gemini-new');
      expect(_label(tester, 'session-ai-label'), 'Gemini · gemini-new');

      await fixture.open(tester, AiModelBindingScope.chatSession);
      await tester.tap(find.byKey(const Key('ai-binding-follow-default')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('save-ai-binding')));
      await tester.pumpAndSettle();

      session = await fixture.container
          .read(chatRepositoryProvider)
          .getSession('session');
      expect(session.aiProviderConfigId, isNull);
      expect(session.aiModel, isNull);
      expect(
        (await fixture.container
                .read(aiModelResolverProvider)
                .resolveForChatSession('session'))
            .providerConfigId,
        'deepseek',
      );
      expect(_label(tester, 'session-ai-label'), 'DeepSeek · deepseek-old');
    },
  );
}

Future<void> _chooseProvider(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('ai-binding-provider')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

String _manualModel(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('ai-binding-manual-model')))
    .controller!
    .text;

String _label(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

class _BindingFixture {
  _BindingFixture(this.container);

  final ProviderContainer container;

  static Future<_BindingFixture> create(WidgetTester tester) async {
    final requests = <http.Request>[];
    final container = ProviderContainer(
      overrides: [
        aiHttpClientFactoryProvider.overrideWithValue(
          () => MockClient((request) async {
            requests.add(request);
            if (request.url.host == 'generativelanguage.googleapis.com') {
              return http.Response(
                jsonEncode({
                  'models': [
                    {
                      'name': 'models/gemini-new',
                      'supportedGenerationMethods': ['generateContent'],
                    },
                  ],
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'data': [
                  {'id': 'deepseek-new'},
                ],
              }),
              200,
            );
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    final repository = container.read(aiProviderConfigRepositoryProvider);
    final keys = container.read(secureApiKeyStoreProvider);
    final now = DateTime.utc(2026, 8, 21);
    for (final config in [
      _config(
        id: 'deepseek',
        type: AiProviderType.deepseek,
        selectedModel: 'deepseek-old',
        models: const ['deepseek-old'],
        now: now,
      ),
      _config(
        id: 'gemini',
        type: AiProviderType.gemini,
        selectedModel: 'gemini-old',
        models: const ['gemini-old'],
        now: now,
      ),
    ]) {
      await repository.saveConfig(config);
      await keys.write(config.apiKeyRef, 'unit-test-key-${config.id}');
    }
    await repository.saveDefault(
      AiDefaultSelection(
        providerId: 'deepseek',
        modelId: 'deepseek-old',
        updatedAtUtc: now,
      ),
    );
    await container
        .read(projectRepositoryProvider)
        .upsertProject(
          Project(
            metadata: _metadata('project'),
            title: '测试作品',
            description: '',
          ),
        );
    await container
        .read(chatPersonaRepositoryProvider)
        .upsertPersona(
          ChatPersona(
            metadata: _metadata('persona'),
            name: '测试角色',
            descriptionMode: ChatPersonaDescriptionMode.simple,
            shortDescription: '自然',
            speakingStyle: '简洁',
          ),
        );
    await container
        .read(chatRepositoryProvider)
        .upsertSession(
          ChatSession(
            metadata: _metadata('session'),
            projectId: null,
            personaId: 'persona',
            title: '测试聊天',
          ),
        );
    container.invalidate(aiSettingsControllerProvider);
    await container.read(aiSettingsControllerProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: _BindingHarness())),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    return _BindingFixture(container);
  }

  Future<void> open(WidgetTester tester, AiModelBindingScope scope) async {
    await tester.tap(
      find.byKey(
        Key(
          scope == AiModelBindingScope.project
              ? 'open-project-binding'
              : 'open-session-binding',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

class _BindingHarness extends ConsumerWidget {
  const _BindingHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectLabel = ref.watch(projectAiLabelProvider('project')).value;
    final sessionLabel = ref.watch(chatSessionAiLabelProvider('session')).value;
    return Column(
      children: [
        Text(projectLabel ?? 'loading', key: const Key('project-ai-label')),
        Text(sessionLabel ?? 'loading', key: const Key('session-ai-label')),
        FilledButton(
          key: const Key('open-project-binding'),
          onPressed: () => showAiModelBindingSheet(
            context: context,
            ref: ref,
            scope: AiModelBindingScope.project,
            entityId: 'project',
          ),
          child: const Text('Project'),
        ),
        FilledButton(
          key: const Key('open-session-binding'),
          onPressed: () => showAiModelBindingSheet(
            context: context,
            ref: ref,
            scope: AiModelBindingScope.chatSession,
            entityId: 'session',
          ),
          child: const Text('Session'),
        ),
      ],
    );
  }
}

AiProviderConfig _config({
  required String id,
  required AiProviderType type,
  required String selectedModel,
  required List<String> models,
  required DateTime now,
}) {
  return AiProviderConfig(
    id: id,
    type: type,
    displayName: type.displayName,
    baseUrl: type.defaultBaseUrl,
    apiKeyRef: 'ai.api_key.$id',
    selectedModel: selectedModel,
    enabled: true,
    connectionStatus: AiProviderConnectionStatus.connected,
    availableModels: models,
    verifiedModels: models,
    createdAtUtc: now,
    updatedAtUtc: now,
    lastVerifiedAtUtc: now,
  );
}

EntityMetadata _metadata(String id) => EntityMetadata(
  id: id,
  createdAt: DateTime.utc(2026, 8, 21),
  updatedAt: DateTime.utc(2026, 8, 21),
  revision: 1,
);
