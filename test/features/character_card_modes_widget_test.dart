import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/ai/card_completion.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/features/ai/presentation/card_completion_dialog.dart';
import 'package:ibukihome/features/characters/presentation/character_pages.dart';

void main() {
  testWidgets(
    'original is a simple two-field form and fanfic optional details expand',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = InMemoryIbukiStore()
        ..putProject(
          Project(
            metadata: _metadata('project'),
            title: '测试作品',
            description: '',
          ),
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [inMemoryIbukiStoreProvider.overrideWithValue(store)],
          child: const MaterialApp(
            home: Scaffold(body: NewCharacterPage(projectId: 'project')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('同人角色'), findsOneWidget);
      expect(find.text('原创角色'), findsOneWidget);
      expect(
        find.byKey(const Key('character-original-idea-field')),
        findsNothing,
      );
      await tester.tap(find.text('原创角色'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('character-original-idea-field')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('character-creativity-selector')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      expect(find.byKey(const Key('character-ai-completion')), findsNothing);
      expect(find.text('新建角色'), findsNothing);
      expect(find.text('这是什么角色？'), findsNothing);
      await tester.tap(find.text('同人角色'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('character-source-work-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('character-source-name-field')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('character-fanfic-details')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('character-fanfic-details')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('character-source-version-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('character-adaptation-field')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('character-ai-completion')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('AI 参考原作'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preview leaves inferred changes unselected and names source', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCardCompletionPreview(
                context: context,
                mode: CardCompletionMode.canonReference,
                suggestions: const [
                  CardCompletionSuggestion(
                    field: 'content',
                    currentValue: '',
                    suggestedValue: '不确定的补充',
                    reason: '模型推测',
                    inferred: true,
                  ),
                ],
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final checkbox = tester.widget<CheckboxListTile>(
      find.byKey(const Key('card-suggestion-content')),
    );
    expect(checkbox.value, isFalse);
    expect(find.text('来源：推测'), findsOneWidget);
    expect(find.text('推测建议 · 默认未选择'), findsOneWidget);
  });

  testWidgets('canon comparison is read-only', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCardCompletionPreview(
                context: context,
                mode: CardCompletionMode.canonComparison,
                suggestions: const [
                  CardCompletionSuggestion(
                    field: 'content',
                    currentValue: '作者改设',
                    suggestedValue: '与原作存在差异，不会自动修改。',
                    reason: '对照结果',
                    inferred: false,
                    source: CardSuggestionSource.modelKnowledge,
                  ),
                ],
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(
      find.byKey(const Key('accept-selected-card-suggestions')),
      findsNothing,
    );
    expect(find.text('与原作存在差异，不会自动修改。'), findsOneWidget);
  });
}

EntityMetadata _metadata(String id) =>
    EntityMetadata(id: id, createdAt: _now, updatedAt: _now, revision: 1);

final _now = DateTime.utc(2026, 8, 13);
