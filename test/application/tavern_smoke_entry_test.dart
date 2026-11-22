import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ibukihome/application/ai/ai_settings_controller.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/application/world_roleplay/world_roleplay_providers.dart';
import 'package:ibukihome/application/tavern/tavern_execution_providers.dart';
import 'package:ibukihome/data/memory/in_memory_tavern_repository.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/data/memory/in_memory_character_repository.dart';
import 'package:ibukihome/domain/tavern/tavern_models.dart';
import 'tavern_orchestrator_test.dart' as fixture;
import '../../tool/tavern_provider_smoke.dart' as smoke;

void main() {
  testWidgets(
    'smoke preparation creates valid isolated Persona/Character references without sending HTTP',
    (tester) async {
      final env = await fixture.memoryEnvironment();
      addTearDown(env.owner.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tavernRepositoryProvider.overrideWithValue(env.repo),
            projectRepositoryProvider.overrideWithValue(
              InMemoryProjectRepository(
                (env.characters as InMemoryCharacterRepository).store,
              ),
            ),
            characterRepositoryProvider.overrideWithValue(env.characters),
            worldRoleplayRepositoryProvider.overrideWithValue(env.worlds),
            aiSecureValueStoreProvider.overrideWithValue(env.secure),
            aiHttpClientFactoryProvider.overrideWithValue(
              () => throw StateError('Unexpected network request'),
            ),
          ],
          child: const MaterialApp(home: smoke.TavernSmokePage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create synthetic test session'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(
        find.text('Synthetic fixture ready. Live request: NOT RUN'),
        findsOneWidget,
      );
      final repo = env.repo as InMemoryTavernRepository;
      final session = repo.sessions.values.singleWhere(
        (s) => s.id.startsWith('smoke-session-'),
      );
      final participants = await repo.listParticipants(session.id);
      expect(participants, hasLength(2));
      expect(
        participants
            .singleWhere((p) => p.kind == TavernParticipantKind.persona)
            .entityId,
        session.personaId,
      );
      expect(
        (await env.worlds.getPersona(session.personaId!)).name,
        'Test Player',
      );
      expect((await repo.loadTranscript(session.id)).turns, hasLength(1));
      expect(repo.sessions['s'], isNotNull);
      expect(env.sent, isEmpty);
      expect(repo.attempts, isEmpty);
    },
  );
  test(
    'live smoke entry is disabled in ordinary flutter test execution',
    () async {
      await expectLater(smoke.main(), throwsStateError);
    },
  );
}
