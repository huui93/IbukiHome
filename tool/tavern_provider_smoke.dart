import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ibukihome/app/bootstrap.dart';
import 'package:ibukihome/application/ai/ai_settings_controller.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/application/world_roleplay/world_roleplay_providers.dart';
import 'package:ibukihome/application/tavern/tavern_execution_providers.dart';
import 'package:ibukihome/application/tavern/tavern_generation_orchestrator.dart';
import 'package:ibukihome/application/tavern/tavern_generation_runtime.dart';
import 'package:ibukihome/application/tavern/provider/tavern_provider_models.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/tavern/tavern_models.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_models.dart';

Future<void> main() async {
  const enabled = bool.fromEnvironment('IBUKI_TAVERN_LIVE_SMOKE');
  if (!enabled) {
    throw StateError(
      'Live smoke is opt-in. Set IBUKI_TAVERN_LIVE_SMOKE=true explicitly.',
    );
  }
  await bootstrap(application: const MaterialApp(home: TavernSmokePage()));
}

class TavernSmokePage extends ConsumerStatefulWidget {
  const TavernSmokePage({super.key});
  @override
  ConsumerState<TavernSmokePage> createState() => _TavernSmokeState();
}

class _TavernSmokeState extends ConsumerState<TavernSmokePage> {
  List<AiProviderConfig> _configs = [];
  AiProviderConfig? _selected;
  String? _session, _line, _speaker, _user;
  String _status = 'Live request: NOT RUN';
  bool _used = false, _preparing = false;
  TavernOrchestrationHandle? _handle;
  TavernReasoningAvailability _reasoning =
      TavernReasoningAvailability.unavailable;
  StreamSubscription<TavernOrchestrationUpdate>? _subscription;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final configs = await ref
        .read(aiProviderConfigRepositoryProvider)
        .listConfigs();
    if (mounted) {
      setState(() {
        _configs = configs
            .where((c) => c.enabled && c.selectedModel.isNotEmpty)
            .toList();
      });
    }
  }

  Future<void> _createFixture() async {
    setState(() {
      _preparing = true;
    });
    try {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final now = DateTime.now().toUtc();
      EntityMetadata entity(String id) => EntityMetadata(
        id: '$id-$suffix',
        createdAt: now,
        updatedAt: now,
        revision: 1,
      );
      final project = Project(
        metadata: entity('smoke-project'),
        title: 'Tavern Smoke Assets',
        description: 'Synthetic developer fixture',
      );
      await ref.read(projectRepositoryProvider).upsertProject(project);
      final card = CharacterCard(
        metadata: entity('smoke-character'),
        projectId: project.id,
        name: 'Mira',
        content:
            'A playful dragon in a quiet dining hall. React briefly to the player, without controlling them.',
        sortOrder: 0,
      );
      await ref.read(characterRepositoryProvider).upsertCharacter(card);
      final worlds = ref.read(worldRoleplayRepositoryProvider);
      final world = RoleplayWorld(
        entity: entity('smoke-world'),
        name: 'Synthetic smoke hall',
        description: 'Isolated developer fixture',
      );
      await worlds.upsertWorld(world);
      final persona = PlayerPersona(
        entity: entity('smoke-persona'),
        worldId: world.id,
        name: 'Test Player',
        description: 'A visitor to the synthetic hall.',
      );
      await worlds.upsertPersona(persona);
      final book = WorldBook(
        entity: entity('smoke-book'),
        name: 'Synthetic hall',
      );
      await worlds.upsertWorldBook(book);
      await worlds.upsertLoreEntry(
        LoreEntry(
          entity: entity('smoke-lore'),
          worldBookId: book.id,
          title: 'North door',
          content: 'The north door leads to the quiet courtyard.',
          keywords: const ['north'],
        ),
      );
      await worlds.upsertCharacterWorldBookReference(
        EntityWorldBookReference(
          entity: entity('smoke-reference'),
          entityId: card.id,
          worldBookId: book.id,
        ),
      );
      final repo = ref.read(tavernRepositoryProvider);
      final sid = 'smoke-session-$suffix',
          line = 'smoke-line-$suffix',
          speaker = 'smoke-speaker-$suffix',
          user = 'smoke-user-$suffix';
      await repo.createSession(
        TavernSession(
          id: sid,
          title: 'Opt-in Provider Smoke',
          createdAt: now,
          updatedAt: now,
          worldAssetType: 'roleplayWorld',
          worldAssetId: world.id,
          personaType: 'playerPersona',
          personaId: persona.id,
        ),
        TavernStoryLine(
          id: line,
          sessionId: sid,
          name: 'Main',
          position: 0,
          createdAt: now,
        ),
      );
      await repo.addParticipant(
        TavernParticipant(
          id: speaker,
          sessionId: sid,
          kind: TavernParticipantKind.character,
          position: 1,
          entityId: card.id,
          displayName: card.name,
        ),
      );
      await repo.addParticipant(
        TavernParticipant(
          id: 'player-$suffix',
          sessionId: sid,
          kind: TavernParticipantKind.persona,
          entityId: persona.id,
          position: 0,
          displayName: 'Test Player',
        ),
      );
      await repo.appendTurn(
        TavernTurn(
          id: user,
          sessionId: sid,
          storyLineId: line,
          position: 0,
          participantId: 'player-$suffix',
          role: TavernTurnRole.player,
          createdAt: now,
          updatedAt: now,
        ),
        TavernAlternative(
          id: '$user-alt',
          turnId: user,
          position: 0,
          origin: TavernAlternativeOrigin.manual,
          createdAt: now,
        ),
      );
      await repo.appendContentPart(
        TavernContentPart(
          id: '$user-text',
          alternativeId: '$user-alt',
          position: 0,
          kind: TavernContentKind.text,
          text: 'I point at the north door. What is beyond it?',
          createdAt: now,
        ),
      );
      if (mounted) {
        setState(() {
          _session = sid;
          _line = line;
          _speaker = speaker;
          _user = user;
          _status = 'Synthetic fixture ready. Live request: NOT RUN';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = 'Fixture preparation failed.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _preparing = false;
        });
      }
    }
  }

  Future<void> _run() async {
    final config = _selected;
    if (config == null || _session == null || _used) return;
    setState(() {
      _used = true;
      _status = 'Preparing one opt-in request';
    });
    final owner = ref.read(tavernExecutionProvider);
    _subscription = owner.updates.listen((u) {
      if (mounted) {
        setState(() {
          _status = u.phase.name;
        });
      }
    });
    try {
      final profile = await ref
          .read(tavernModelProfilesProvider)
          .load(config, config.selectedModel);
      final c = profile.capabilities;
      final binding = TavernProviderBinding(
        config: config,
        model: profile.model,
        protocol: profile.protocol,
        outputTokens: min(128, min(profile.outputTokens, c.maximumOutput)),
        allowLocalHttp: profile.allowLocalHttp,
        parameters: profile.parameters,
        timeout: profile.timeout,
        capabilities: TavernModelCapabilities(
          contextWindow: c.contextWindow,
          maximumOutput: c.maximumOutput,
          streaming: c.streaming,
          streamUsage: c.streamUsage,
          systemRole: c.systemRole,
          developerRole: c.developerRole,
          reasoning: _reasoning,
          continuation: c.continuation,
          allowedParameters: c.allowedParameters,
          tokenAccuracy: c.tokenAccuracy,
        ),
      );
      final id = 'live-${DateTime.now().microsecondsSinceEpoch}';
      _handle = await owner.start(
        TavernGenerationCommand(
          commandId: id,
          sessionId: _session!,
          storyLineId: _line!,
          turnId: '$id-turn',
          alternativeId: '$id-answer',
          attemptId: id,
          kind: TavernGenerationCommandKind.normal,
          participantId: _speaker,
          contextTurnId: _user,
        ),
        binding,
      );
      if (mounted) setState(() {});
      final result = await _handle!.done;
      if (mounted) {
        setState(() {
          _status =
              '${result.generation.phase.name}\n'
              'Provider: ${config.type.name}\nModel: ${profile.model}\n'
              'Visible characters: ${result.trace.provider.visibleCharacters}\n'
              'Reasoning: ${result.trace.provider.reasoning.name}\n'
              'Attempt persisted: ${result.generation.target.attemptId}\n'
              'Ledger: ${result.settlement?.name ?? 'unavailable'}\n'
              'Error: ${result.trace.provider.failure?.kind.name ?? 'none'}';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = error is TavernProviderFailure
              ? error.toString()
              : 'Preflight or runtime validation failed.';
        });
      }
    } finally {
      await _subscription?.cancel();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_handle?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tavern Provider Smoke')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Opt-in developer validation. One request per launch. Only synthetic fixture content is sent.',
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<AiProviderConfig>(
          decoration: const InputDecoration(
            labelText: 'Configured Provider / Model',
          ),
          items: _configs
              .map(
                (c) => DropdownMenuItem(
                  value: c,
                  child: Text(
                    '${c.displayName} / ${c.selectedModel}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: _used
              ? null
              : (c) => setState(() {
                  _selected = c;
                }),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<TavernReasoningAvailability>(
          initialValue: _reasoning,
          decoration: const InputDecoration(
            labelText: 'Explicit reasoning capability',
          ),
          items: TavernReasoningAvailability.values
              .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
              .toList(),
          onChanged: _used
              ? null
              : (r) => setState(() {
                  _reasoning = r!;
                }),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _preparing || _session != null ? null : _createFixture,
          child: const Text('Create synthetic test session'),
        ),
        FilledButton(
          onPressed: _session == null || _selected == null || _used
              ? null
              : _run,
          child: const Text('Send one test request'),
        ),
        OutlinedButton(
          onPressed: _handle == null
              ? null
              : () async {
                  await _handle!.cancel();
                },
          child: const Text('Stop'),
        ),
        const SizedBox(height: 16),
        Text(_status),
      ],
    ),
  );
}
