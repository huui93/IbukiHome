import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/tavern/tavern_presentation_controller.dart';
import 'package:ibukihome/application/tavern/tavern_presentation_providers.dart';
import 'package:ibukihome/application/tavern/tavern_story_service.dart';
import 'package:ibukihome/data/memory/in_memory_tavern_repository.dart';
import 'package:ibukihome/data/memory/in_memory_secure_value_store.dart';
import 'package:ibukihome/domain/tavern/tavern_models.dart';
import 'package:ibukihome/features/tavern/presentation/tavern_transcript.dart';
import 'application/tavern_orchestrator_test.dart' as fixtures;
import 'support/tavern_ui_rig.dart';

void main() {
  for (final count in [100, 500, 1000]) {
    testWidgets(
      '$count real-model Turns × 5 Alternatives: lazy transcript, 360 width and anchored reopen',
      (tester) async {
        final rig = TavernUiRig();
        await tester.runAsync(rig.initialize);
        final repository = InMemoryTavernRepository();
        final now = DateTime.utc(2026);
        await repository.createSession(
          TavernSession(
            id: 'stress',
            title: 'Long story',
            createdAt: now,
            updatedAt: now,
          ),
          TavernStoryLine(
            id: 'stress-main',
            sessionId: 'stress',
            name: 'Main',
            position: 0,
            createdAt: now,
          ),
          participants: [
            const TavernParticipant(
              id: 'stress-speaker',
              sessionId: 'stress',
              kind: TavernParticipantKind.character,
              entityId: 'character',
              displayName: 'A very long character name that still needs to fit',
              position: 0,
            ),
          ],
        );
        for (var i = 0; i < count; i++) {
          await repository.appendTurn(
            TavernTurn(
              id: 'stress-$i',
              sessionId: 'stress',
              storyLineId: 'stress-main',
              position: i,
              participantId: 'stress-speaker',
              role: i % 3 == 0
                  ? TavernTurnRole.narrator
                  : TavernTurnRole.character,
              createdAt: now,
              updatedAt: now,
            ),
            TavernAlternative(
              id: 'stress-$i-0',
              turnId: 'stress-$i',
              position: 0,
              origin: TavernAlternativeOrigin.imported,
              createdAt: now,
            ),
          );
          for (var a = 0; a < 5; a++) {
            if (a > 0) {
              await repository.addAlternative(
                TavernAlternative(
                  id: 'stress-$i-$a',
                  turnId: 'stress-$i',
                  position: a,
                  origin: TavernAlternativeOrigin.imported,
                  createdAt: now,
                ),
              );
            }
            await repository.appendContentPart(
              TavernContentPart(
                id: 'stress-$i-$a-text',
                alternativeId: 'stress-$i-$a',
                position: 0,
                kind: TavernContentKind.text,
                text:
                    'Turn $i. ${List.filled(20, 'A long visible character reaction.').join('\n')}',
                createdAt: now,
              ),
            );
          }
        }
        final env = fixtures.TavernTestEnvironment(
          repository,
          rig.service.characters,
          rig.service.worlds,
        );
        await tester.runAsync(env.initialize);
        final service = TavernStoryService(
          repository: repository,
          characters: rig.service.characters,
          worlds: rig.service.worlds,
          worldCards: rig.service.worldCards,
          projects: rig.service.projects,
          configs: rig.service.configs,
          profiles: rig.service.profiles,
          ids: rig.service.ids,
        );
        final c = TavernSessionController(
          sessionId: 'stress',
          service: service,
          owner: env.owner,
          traces: TavernTraceCache(),
        );
        final watch = Stopwatch()..start();
        await c.load();
        watch.stop();
        debugPrint(
          'Phase12 projection: turns=$count alternatives=${count * 5} elapsedMs=${watch.elapsedMilliseconds}',
        );
        final reading = TavernReadingStore(InMemorySecureValueStore()),
            key = GlobalKey<TavernTranscriptState>();
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget app() => MaterialApp(
          home: Scaffold(
            body: TavernTranscript(
              key: key,
              controller: c,
              reading: reading,
              onTurnMenu: (_) {},
              avatarPath: (_) => null,
            ),
          ),
        );
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(find.byType(TavernTurnView).evaluate().length, lessThan(12));
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView), const Offset(0, 600));
        await tester.pumpAndSettle();
        final scroll = key.currentState!.scroll;
        expect(scroll.offset, greaterThan(0));
        await key.currentState!.savePosition();
        final saved = scroll.offset;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(key.currentState!.scroll.offset, closeTo(saved, 10));
        expect(find.byKey(const Key('tavern-bottom')), findsOneWidget);
        await tester.tap(find.byKey(const Key('tavern-bottom')));
        await tester.pumpAndSettle();
        expect(key.currentState!.scroll.offset, 0);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        await tester.runAsync(env.owner.dispose);
        await tester.runAsync(rig.dispose);
      },
    );
  }
}
