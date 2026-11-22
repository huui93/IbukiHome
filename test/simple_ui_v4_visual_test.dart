import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_router.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/app/theme/app_theme.dart';
import 'package:ibukihome/app/theme/app_tokens.dart';
import 'package:ibukihome/app/theme/bubble_theme.dart';
import 'package:ibukihome/app/theme/ibuki_theme_colors.dart';
import 'package:ibukihome/app/theme/theme_controller.dart';
import 'package:ibukihome/app/widgets/ibuki_buttons.dart';
import 'package:ibukihome/app/widgets/ibuki_text_field.dart';
import 'package:ibukihome/features/settings/presentation/ai_settings_pages.dart';

void main() {
  test('light palette uses warm white, blue primary, and pink accent', () {
    final theme = AppTheme.light();
    final colors = theme.extension<IbukiThemeColors>()!;

    final bubble = theme.extension<BubbleTheme>()!;
    expect(bubble.backgroundMiddle, isNot(Colors.white));
    expect(bubble.backgroundMiddle.computeLuminance(), greaterThan(0.9));
    expect(theme.colorScheme.primary, AppTokens.accentBlue);
    expect(colors.accent, AppTokens.accentPink);
    expect(theme.colorScheme.onSurface, AppTokens.textPrimary);
  });

  test('dark palette avoids pure black and keeps the same brand hierarchy', () {
    final theme = AppTheme.dark();
    final colors = theme.extension<IbukiThemeColors>()!;

    final bubble = theme.extension<BubbleTheme>()!;
    expect(bubble.backgroundMiddle, isNot(Colors.black));
    expect(bubble.backgroundMiddle.computeLuminance(), greaterThan(0));
    expect(theme.colorScheme.primary, AppTokens.accentBlueDark);
    expect(colors.accent, AppTokens.accentPinkDark);
  });

  testWidgets('bottom navigation uses a compact selected marker', (
    tester,
  ) async {
    await _pumpApp(tester);

    final selected = tester.getSize(
      find.byKey(const Key('bottom-nav-selected-聊天')),
    );
    expect(selected.width, lessThan(90));
    expect(selected.height, lessThan(AppTokens.primaryNavigationHeight));
  });

  for (final entry in {
    AppRoutes.novel: Key('novel-workspace-home'),
    AppRoutes.chat: Key('chat-home-page'),
    AppRoutes.settings: Key('settings-page'),
  }.entries) {
    testWidgets('${entry.key} builds with the light Ibuki palette', (
      tester,
    ) async {
      final container = await _pumpApp(tester);
      container.read(appRouterProvider).go(entry.key);
      await tester.pumpAndSettle();
      expect(find.byKey(entry.value), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${entry.key} builds with the dark Ibuki palette', (
      tester,
    ) async {
      final container = await _pumpApp(tester, dark: true);
      container.read(appRouterProvider).go(entry.key);
      await tester.pumpAndSettle();
      expect(find.byKey(entry.value), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('primary button has the shared height and medium radius', (
    tester,
  ) async {
    await _pumpControls(tester);
    final theme = Theme.of(tester.element(find.byType(FilledButton)));
    final style = theme.filledButtonTheme.style!;
    final shape = style.shape!.resolve({})! as RoundedRectangleBorder;

    expect(style.minimumSize!.resolve({})!.height, AppTokens.buttonHeight);
    expect(shape.borderRadius, BorderRadius.circular(AppTokens.radiusM));
  });

  testWidgets('secondary button uses a soft fill without a thick border', (
    tester,
  ) async {
    await _pumpControls(tester);
    final context = tester.element(find.byType(OutlinedButton));
    final theme = Theme.of(context);
    final style = theme.outlinedButtonTheme.style!;

    expect(style.backgroundColor!.resolve({}), context.ibukiColors.primarySoft);
    expect(style.side!.resolve({}), BorderSide.none);
  });

  testWidgets('text fields share the medium input radius', (tester) async {
    await _pumpControls(tester);
    final theme = Theme.of(tester.element(find.byType(TextField)));
    final border =
        theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
    expect(border.borderRadius, BorderRadius.circular(AppTokens.radiusM));
  });

  testWidgets('settings remains stable at 360 by 800', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = await _pumpApp(tester);
    container.read(appRouterProvider).go(AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text keeps the three bottom labels identifiable', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpApp(tester);

    final navigation = find.byKey(const Key('primary-bottom-navigation'));
    for (final label in ['小说', '聊天', '设置']) {
      expect(
        find.descendant(of: navigation, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('long API key and Base URL do not overflow the provider form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = await _pumpApp(tester);
    container.read(appRouterProvider).go(AppRoutes.aiProvider('openai'));
    await tester.pumpAndSettle();
    await _enter(
      tester,
      const Key('provider-api-key-field'),
      List.filled(10, 'not-a-real-key').join(),
    );
    await tester.tap(find.byKey(const Key('provider-advanced-settings')));
    await tester.pump();
    await _enter(
      tester,
      const Key('provider-base-url-field'),
      'https://example.test/a/very/long/provider/path/that/keeps/going/v1',
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('long model names use ellipsis in the picker', (tester) async {
    const model =
        'provider-model-with-a-name-that-is-intentionally-much-longer-than-the-screen-width';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: AiModelPickerSheet(models: [model], currentModel: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(find.text(model));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });
}

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  bool dark = false,
}) async {
  final container = ProviderContainer();
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
  return container;
}

Future<void> _pumpControls(WidgetTester tester) async {
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
            IbukiTextField(controller: controller, label: '输入'),
          ],
        ),
      ),
    ),
  );
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
