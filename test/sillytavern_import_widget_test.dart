import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_router.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/application/import/sillytavern_file_picker.dart';
import 'package:ibukihome/application/import/sillytavern_import_providers.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';

void main() {
  testWidgets(
    'import center previews security findings and imports a native character',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = _MemoryImportSource(
        'synthetic-v3.json',
        utf8.encode(jsonEncode(_characterFixture())),
      );
      final container = ProviderContainer(
        overrides: [
          sillyTavernImportPickerProvider.overrideWithValue(
            _FixedImportPicker(source),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(inMemoryIbukiStoreProvider)
          .putProject(
            Project(
              metadata: _metadata('import-project'),
              title: '导入测试作品',
              description: '',
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const IbukiHomeApp(),
        ),
      );
      await tester.pumpAndSettle();
      container.read(appRouterProvider).go(AppRoutes.sillyTavernImport);
      await tester.pumpAndSettle();

      expect(find.text('从 SillyTavern 导入'), findsOneWidget);
      expect(find.textContaining('不会运行'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pick-sillytavern-file')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Synthetic Character'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((item) => item.data)
            .whereType<String>()
            .join(' | '),
      );
      expect(find.text('SillyTavern Character Card 3.0'), findsOneWidget);
      expect(find.text('这是故事中由 AI 扮演的角色。'), findsOneWidget);
      expect(find.text('备用开场白 2'), findsOneWidget);
      expect(find.text('世界书条目 1'), findsOneWidget);

      final importScrollable = find.descendant(
        of: find.byKey(const Key('sillytavern-import-page')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('安全与兼容'),
        220,
        scrollable: importScrollable,
      );
      await tester.tap(find.text('安全与兼容'));
      await tester.pumpAndSettle();
      expect(find.textContaining('扩展脚本'), findsOneWidget);
      expect(find.textContaining('远程资源引用'), findsOneWidget);
      expect(find.textContaining('疑似密钥'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('sillytavern-project-target')),
        -220,
        scrollable: importScrollable,
      );
      await tester.tap(find.byKey(const Key('sillytavern-project-target')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导入测试作品').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('confirm-sillytavern-import')),
        220,
        scrollable: importScrollable,
      );
      await tester.tap(find.byKey(const Key('confirm-sillytavern-import')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('sillytavern-compatibility-detail')),
        findsOneWidget,
      );
      expect(find.text('chara_card_v3'), findsOneWidget);
      expect(find.textContaining('安全标记 ('), findsOneWidget);
      expect(find.textContaining('脚本不会执行'), findsOneWidget);
      final characters = await container
          .read(characterRepositoryProvider)
          .listCharacters('import-project');
      expect(characters, hasLength(1));
      expect(characters.single.name, 'Synthetic Character');
      expect(characters.single.sourceFormat, 'chara_card_v3');
      expect(characters.single.compatibilityPayloadId, isNotNull);
    },
  );
}

Map<String, Object?> _characterFixture() {
  final fakeBearer = ['Bearer', 'TEST_ONLY_TOKEN_1234567890'].join(' ');
  final fakeKey = ['sk', 'TEST_ONLY_ABCDEFGHIJKLMNOP'].join('-');
  return {
    'spec': 'chara_card_v3',
    'spec_version': '3.0',
    'data': {
      'name': 'Synthetic Character',
      'description': 'Synthetic description',
      'personality': 'Calm',
      'scenario': 'A safe local fixture',
      'first_mes': 'Hello',
      'alternate_greetings': ['Hi', 'Welcome'],
      'mes_example': '<START>\nSynthetic example',
      'system_prompt': 'Keep the character voice.',
      'post_history_instructions': 'Stay concise.',
      'character_book': {
        'name': 'Synthetic Book',
        'entries': [
          {
            'id': 1,
            'name': 'Cafe',
            'content': 'The cafe closes at midnight.',
            'keys': ['cafe'],
          },
        ],
      },
      'extensions': {
        'future_ibuki_test': {'retained': true},
        'tavern_helper': {
          'script': 'document.createElement("button")',
          'remote': 'https://invalid.example.test/script.js',
          'authorization': fakeBearer,
          'apiKey': fakeKey,
        },
      },
    },
  };
}

EntityMetadata _metadata(String id) {
  final at = DateTime.utc(2026, 9, 2);
  return EntityMetadata(id: id, createdAt: at, updatedAt: at, revision: 1);
}

class _FixedImportPicker implements SillyTavernImportPicker {
  const _FixedImportPicker(this.source);

  final SillyTavernImportSource source;

  @override
  Future<SillyTavernImportSource?> pick() async => source;
}

class _MemoryImportSource implements SillyTavernImportSource {
  const _MemoryImportSource(this.fileName, this.bytes);

  @override
  final String fileName;
  final List<int> bytes;

  @override
  Future<int> length() async => bytes.length;

  @override
  Stream<List<int>> openRead() => Stream.value(bytes);
}
