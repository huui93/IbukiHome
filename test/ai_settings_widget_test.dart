import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_router.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/app/theme/app_theme.dart';
import 'package:ibukihome/app/theme/theme_controller.dart';
import 'package:ibukihome/app/widgets/ibuki_buttons.dart';
import 'package:ibukihome/app/widgets/ibuki_text_field.dart';
import 'package:ibukihome/application/ai/ai_settings_controller.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/data/memory/in_memory_secure_value_store.dart';
import 'package:ibukihome/features/settings/presentation/ai_settings_pages.dart';

void main() {
  testWidgets('settings exposes AI configuration and default AI rows', (
    tester,
  ) async {
    final harness = await _pumpApp(tester);
    harness.go(AppRoutes.settings);
    await tester.pumpAndSettle();

    expect(find.text('AI 与模型'), findsOneWidget);
    expect(find.byKey(const Key('settings-ai-config')), findsOneWidget);
    expect(find.byKey(const Key('settings-default-ai')), findsOneWidget);
  });

  testWidgets('API configuration entry opens the provider list', (
    tester,
  ) async {
    final harness = await _pumpApp(tester);
    harness.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-ai-config')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-provider-list-page')), findsOneWidget);
  });

  testWidgets('provider list contains all official providers and custom', (
    tester,
  ) async {
    final harness = await _pumpApp(tester);
    harness.go(AppRoutes.aiProviders);
    await tester.pumpAndSettle();

    for (final name in [
      'OpenAI',
      'Gemini',
      'DeepSeek',
      'Kimi',
      '千问',
      'Grok',
      'GLM',
      'Claude',
    ]) {
      await tester.scrollUntilVisible(
        find.text(name),
        150,
        scrollable: find.descendant(
          of: find.byKey(const Key('ai-provider-list-page')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text(name), findsOneWidget);
    }
    await tester.scrollUntilVisible(
      find.byKey(const Key('add-custom-provider')),
      150,
      scrollable: find.descendant(
        of: find.byKey(const Key('ai-provider-list-page')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.byKey(const Key('add-custom-provider')), findsOneWidget);
    expect(find.textContaining('自定义 · 0'), findsOneWidget);
  });

  testWidgets('unconfigured providers show a restrained status', (
    tester,
  ) async {
    final harness = await _pumpApp(tester);
    harness.go(AppRoutes.aiProviders);
    await tester.pumpAndSettle();

    expect(find.text('未配置'), findsWidgets);
    expect(find.text('连接失败'), findsNothing);
  });

  testWidgets('OpenAI configuration hides the API key by default', (
    tester,
  ) async {
    final harness = await _pumpApp(tester);
    harness.go(AppRoutes.aiProvider('openai'));
    await tester.pumpAndSettle();

    final field = _textFieldInside(const Key('provider-api-key-field'), tester);
    expect(field.obscureText, isTrue);
    expect(find.text('OpenAI'), findsWidgets);
  });

  testWidgets('API key visibility can be toggled and starts hidden again', (
    tester,
  ) async {
    final harness = await _pumpApp(tester);
    harness.go(AppRoutes.aiProvider('openai'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('provider-api-key-field')),
        matching: find.byType(TextField),
      ),
      'unit-test-secret',
    );
    await tester.tap(find.byKey(const Key('toggle-api-key-visibility')));
    await tester.pump();
    expect(
      _textFieldInside(const Key('provider-api-key-field'), tester).obscureText,
      isFalse,
    );

    harness.go(AppRoutes.aiProviders);
    await tester.pumpAndSettle();
    harness.go(AppRoutes.aiProvider('openai'));
    await tester.pumpAndSettle();
    expect(
      _textFieldInside(const Key('provider-api-key-field'), tester).obscureText,
      isTrue,
    );
  });

  for (final entry in {
    'gemini': 'Gemini',
    'deepseek': 'DeepSeek',
    'kimi': 'Kimi',
  }.entries) {
    testWidgets('${entry.value} has its own provider configuration page', (
      tester,
    ) async {
      final harness = await _pumpApp(tester);
      harness.go(AppRoutes.aiProvider(entry.key));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai-provider-config-page')), findsOneWidget);
      expect(find.text(entry.value), findsWidgets);
    });
  }

  testWidgets('Kimi page identifies Moonshot without changing its UI name', (
    tester,
  ) async {
    final harness = await _pumpApp(tester);
    harness.go(AppRoutes.aiProvider('kimi'));
    await tester.pumpAndSettle();

    expect(find.text('Kimi'), findsWidgets);
    expect(find.text('由 Moonshot AI 提供'), findsOneWidget);
  });

  testWidgets('custom form has name, base URL, optional key, and model', (
    tester,
  ) async {
    final harness = await _pumpApp(tester);
    harness.go(AppRoutes.newCustomAiProvider);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('provider-name-field')), findsOneWidget);
    expect(find.text('API Key（可留空）'), findsOneWidget);
    expect(find.byKey(const Key('provider-base-url-field')), findsOneWidget);
    expect(find.byKey(const Key('provider-model-field')), findsOneWidget);
    expect(find.text('添加自定义 API'), findsWidgets);
  });

  testWidgets('custom provider can be saved without an API key', (
    tester,
  ) async {
    final harness = await _pumpApp(tester);
    harness.go(AppRoutes.newCustomAiProvider);
    await tester.pumpAndSettle();
    await _enter(tester, const Key('provider-name-field'), '本地兼容服务');
    await _enter(
      tester,
      const Key('provider-base-url-field'),
      'http://127.0.0.1:1234/v1',
    );
    await _enter(tester, const Key('provider-model-field'), 'local-model');
    await tester.tap(find.byKey(const Key('save-ai-provider')));
    await tester.pumpAndSettle();

    final state = harness.container
        .read(aiSettingsControllerProvider)
        .requireValue;
    expect(state.configById('custom-widget-1')?.displayName, '本地兼容服务');
    expect(state.providerIdsWithKeys, isNot(contains('custom-widget-1')));
    expect(find.byKey(const Key('ai-provider-list-page')), findsOneWidget);
  });

  testWidgets('custom Base URL validation is shown as a friendly message', (
    tester,
  ) async {
    final harness = await _pumpApp(tester);
    harness.go(AppRoutes.newCustomAiProvider);
    await tester.pumpAndSettle();
    await _enter(tester, const Key('provider-name-field'), '无效服务');
    await _enter(tester, const Key('provider-model-field'), 'model');
    await tester.tap(find.byKey(const Key('save-ai-provider')));
    await tester.pump();

    expect(find.textContaining('Base URL 无效'), findsOneWidget);
  });

  testWidgets('model picker supports manual model IDs', (tester) async {
    final harness = await _pumpApp(tester);
    harness.go(AppRoutes.aiProvider('openai'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-model-picker')));
    await tester.pumpAndSettle();
    await _enter(tester, const Key('manual-model-field'), 'future-model-id');
    await tester.tap(find.byKey(const Key('confirm-manual-model')));
    await tester.pumpAndSettle();

    final controller = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('provider-model-field')),
        matching: find.byType(TextField),
      ),
    );
    expect(controller.controller?.text, 'future-model-id');
  });

  testWidgets('model picker searches an API-provided list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: AiModelPickerSheet(
            models: ['alpha-model', 'beta-model', 'very-long-model-name'],
            currentModel: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _enter(tester, const Key('model-search-field'), 'beta');
    await tester.pump();

    expect(find.text('beta-model'), findsOneWidget);
    expect(find.text('alpha-model'), findsNothing);
  });

  testWidgets('successful connection test loads models without app content', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final harness = await _pumpApp(
      tester,
      handler: (request) async {
        requests.add(request);
        return http.Response(
          '{"data":[{"id":"model-one"},{"id":"model-two"}]}',
          200,
        );
      },
    );
    harness.go(AppRoutes.aiProvider('openai'));
    await tester.pumpAndSettle();
    await _enter(
      tester,
      const Key('provider-api-key-field'),
      'unit-test-secret',
    );
    await tester.tap(find.byKey(const Key('test-ai-provider')));
    await tester.pumpAndSettle();

    expect(find.textContaining('请选择或填写模型 ID'), findsOneWidget);
    expect(requests, hasLength(1));
    expect(requests.single.body, isEmpty);
    expect(requests.single.url.path, endsWith('/models'));
  });

  testWidgets('refresh marks a selected model unavailable before generation', (
    tester,
  ) async {
    final harness = await _pumpApp(
      tester,
      handler: (request) async => request.method == 'GET'
          ? http.Response('{"data":[{"id":"deepseek-v4-flash"}]}', 200)
          : http.Response('{"error":{"code":"model_not_found"}}', 404),
    );
    harness.go(AppRoutes.aiProvider('deepseek'));
    await tester.pumpAndSettle();
    await _enter(
      tester,
      const Key('provider-api-key-field'),
      'unit-test-secret',
    );
    await _enter(tester, const Key('provider-model-field'), 'deepseek-chat');

    await tester.tap(find.byKey(const Key('test-ai-provider')));
    await tester.pumpAndSettle();

    expect(find.textContaining('模型不可用'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('provider-model-field')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller?.text, 'deepseek-chat');
  });

  testWidgets('official provider with no key never sends a request', (
    tester,
  ) async {
    var requests = 0;
    final harness = await _pumpApp(
      tester,
      handler: (_) async {
        requests += 1;
        return http.Response('{"data":[]}', 200);
      },
    );
    harness.go(AppRoutes.aiProvider('openai'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('test-ai-provider')));
    await tester.pump();

    expect(requests, 0);
    expect(find.text('请先填写 API Key。'), findsOneWidget);
  });

  testWidgets('connection testing ignores repeated taps while loading', (
    tester,
  ) async {
    var requests = 0;
    final completer = Completer<http.Response>();
    final harness = await _pumpApp(
      tester,
      handler: (_) {
        requests += 1;
        return completer.future;
      },
    );
    harness.go(AppRoutes.aiProvider('openai'));
    await tester.pumpAndSettle();
    await _enter(
      tester,
      const Key('provider-api-key-field'),
      'unit-test-secret',
    );
    await tester.tap(find.byKey(const Key('test-ai-provider')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('test-ai-provider')));
    await tester.pump();

    expect(requests, 1);
    expect(find.text('测试中…'), findsOneWidget);
    completer.complete(http.Response('{"data":[{"id":"model"}]}', 200));
    await tester.pumpAndSettle();
  });

  testWidgets('server error does not expose response body or API key', (
    tester,
  ) async {
    final harness = await _pumpApp(
      tester,
      handler: (_) async =>
          http.Response('private-server-stack unit-test-secret', 500),
    );
    harness.go(AppRoutes.aiProvider('openai'));
    await tester.pumpAndSettle();
    await _enter(
      tester,
      const Key('provider-api-key-field'),
      'unit-test-secret',
    );
    await tester.tap(find.byKey(const Key('test-ai-provider')));
    await tester.pumpAndSettle();

    expect(find.text('服务器暂时不可用，请稍后重试。'), findsOneWidget);
    expect(find.textContaining('private-server-stack'), findsNothing);
  });

  testWidgets('settings and provider pages build in dark mode', (tester) async {
    final harness = await _pumpApp(tester, dark: true);
    harness.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-page')), findsOneWidget);
    harness.go(AppRoutes.aiProvider('deepseek'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-provider-config-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('API settings surfaces inherit light and dark app themes', (
    tester,
  ) async {
    var harness = await _pumpApp(tester);
    harness.go(AppRoutes.aiSettings);
    await tester.pumpAndSettle();
    expect(
      Theme.of(
        tester.element(find.byKey(const Key('ai-settings-page'))),
      ).brightness,
      Brightness.light,
    );
    harness.go(AppRoutes.aiProvider('openai'));
    await tester.pumpAndSettle();
    final lightScaffold = tester.widget<Scaffold>(
      find.byKey(const Key('ai-provider-config-page')),
    );
    expect(lightScaffold.backgroundColor, AppTheme.light().colorScheme.surface);
    await tester.tap(find.byKey(const Key('open-model-picker')));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(AiModelPickerSheet))).brightness,
      Brightness.light,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    harness = await _pumpApp(tester, dark: true);
    harness.go(AppRoutes.aiProvider('openai'));
    await tester.pumpAndSettle();
    final darkScaffold = tester.widget<Scaffold>(
      find.byKey(const Key('ai-provider-config-page')),
    );
    expect(darkScaffold.backgroundColor, AppTheme.dark().colorScheme.surface);
    await tester.tap(find.byKey(const Key('open-model-picker')));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(AiModelPickerSheet))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('API configuration fits 360 by 800', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = await _pumpApp(tester);
    harness.go(AppRoutes.aiProvider('openai'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings remains usable with large system text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final harness = await _pumpApp(tester);
    harness.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-ai-config')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared buttons and text fields use the Ibuki theme', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              IbukiPrimaryButton(label: '主要操作', onPressed: () {}),
              IbukiSecondaryButton(label: '次要操作', onPressed: () {}),
              IbukiTextField(controller: controller, label: '统一输入'),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.text('统一输入'), findsOneWidget);
  });
}

class _Harness {
  const _Harness(this.container);

  final ProviderContainer container;

  void go(String location) => container.read(appRouterProvider).go(location);
}

Future<_Harness> _pumpApp(
  WidgetTester tester, {
  bool dark = false,
  Future<http.Response> Function(http.Request)? handler,
}) async {
  final secureStore = InMemorySecureValueStore();
  final container = ProviderContainer(
    overrides: [
      aiSecureValueStoreProvider.overrideWithValue(secureStore),
      aiHttpClientFactoryProvider.overrideWithValue(
        () => MockClient(
          handler ??
              (_) async => http.Response('{"data":[{"id":"mock-model"}]}', 200),
        ),
      ),
      entityIdGeneratorProvider.overrideWithValue(_FixedIdGenerator()),
    ],
  );
  addTearDown(container.dispose);
  if (dark) {
    container.read(themeModeControllerProvider.notifier).setDarkMode(true);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const IbukiHomeApp(),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(container);
}

Future<void> _enter(WidgetTester tester, Key wrapperKey, String value) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(wrapperKey),
      matching: find.byType(TextField),
    ),
    value,
  );
  await tester.pump();
}

TextField _textFieldInside(Key key, WidgetTester tester) {
  return tester.widget<TextField>(
    find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
  );
}

class _FixedIdGenerator extends EntityIdGenerator {
  @override
  String nextId([String prefix = 'id']) => 'custom-widget-1';
}
