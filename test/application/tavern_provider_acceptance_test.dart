import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ibukihome/application/ai/ai_settings_controller.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/application/world_roleplay/world_roleplay_providers.dart';
import 'package:ibukihome/application/tavern/tavern_execution_providers.dart';
import 'package:ibukihome/application/tavern/tavern_generation_runtime.dart';
import 'package:ibukihome/application/tavern/tavern_source_resolver.dart';
import 'package:ibukihome/application/tavern/provider/tavern_provider_models.dart';
import 'package:ibukihome/application/tavern/prompt/prompt_compiler.dart';
import 'package:ibukihome/application/tavern/prompt/prompt_models.dart';
import 'package:ibukihome/application/tavern/world_info/world_info_attempt_ledger.dart';
import 'package:ibukihome/application/tavern/world_info/world_info_models.dart';
import 'package:ibukihome/data/ai/tavern_provider_adapter.dart';
import 'package:ibukihome/data/memory/in_memory_tavern_repository.dart';
import 'package:ibukihome/data/secure/secure_storage_api_key_store.dart';
import 'package:ibukihome/data/secure/secure_ai_provider_config_repository.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';
import 'package:ibukihome/domain/tavern/tavern_models.dart';
import 'package:ibukihome/domain/tavern/tavern_world_info.dart';
import 'package:ibukihome/data/repositories/tavern_world_info_repository.dart';
import 'tavern_orchestrator_test.dart' as integration;
import 'tavern_provider_adapter_test.dart' as fixture;

class _GateSources implements TavernSourceResolver {
  _GateSources(this.delegate);
  final TavernSourceResolver delegate;
  final reached = Completer<void>();
  final release = Completer<void>();
  int calls = 0;
  @override
  Future<TavernSourceBundle> resolve(
    TavernTranscriptProjection p,
    String s,
  ) async {
    calls++;
    if (!reached.isCompleted) reached.complete();
    await release.future;
    return delegate.resolve(p, s);
  }
}

class _FailCompiler extends PromptCompiler {
  const _FailCompiler() : super(const EstimatedPromptTokenCounter());
  @override
  CompiledPrompt compile(PromptCompileInput input) =>
      throw StateError('Synthetic compiler fault');
}

class _CaptureCompiler extends PromptCompiler {
  _CaptureCompiler() : super(const EstimatedPromptTokenCounter());
  CompiledPrompt? captured;
  @override
  CompiledPrompt compile(PromptCompileInput input) =>
      captured = super.compile(input);
}

class _FailLedger extends WorldInfoAttemptLedger {
  _FailLedger({this.prepareFails = false});
  final bool prepareFails;
  @override
  WorldInfoActivationPlan prepare({
    required TavernGenerationAttempt attempt,
    required List<WorldInfoEntry> entries,
    required WorldInfoActivationContext context,
    required WorldInfoRandomSource random,
    WorldInfoSettings settings = const WorldInfoSettings(),
  }) {
    if (prepareFails) throw StateError('Synthetic evaluation fault');
    return super.prepare(
      attempt: attempt,
      entries: entries,
      context: context,
      random: random,
      settings: settings,
    );
  }

  @override
  WorldInfoSettlement settle({
    required TavernGenerationAttempt attempt,
    CompiledPrompt? compiledPrompt,
  }) {
    if (!prepareFails && attempt.status == TavernGenerationStatus.completed) {
      throw StateError('Synthetic ledger fault');
    }
    return super.settle(attempt: attempt, compiledPrompt: compiledPrompt);
  }
}

class _ChangingAdapter extends TavernProviderAdapter {
  _ChangingAdapter(super.factory);
  int calls = 0;
  @override
  Map<String, Object?> requestBody(TavernProviderRequest request) {
    final body = super.requestBody(request);
    if (++calls > 1) body['model'] = 'changed-after-compile';
    return body;
  }
}

class _ControlledTransport extends http.BaseClient {
  _ControlledTransport({this.connecting = false});
  final bool connecting;
  final started = Completer<void>();
  final response = Completer<http.StreamedResponse>();
  final stream = StreamController<List<int>>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    started.complete();
    if (connecting) return response.future;
    return http.StreamedResponse(stream.stream, 200);
  }

  @override
  void close() {
    closed = true;
    if (connecting && !response.isCompleted) {
      response.completeError(http.ClientException('Synthetic abort'));
    }
    if (!stream.isClosed) unawaited(stream.close());
  }
}

class _LifecycleRepository extends InMemoryTavernRepository {
  int recoveries = 0;
  bool holdFinalization = false;
  final finalizing = Completer<void>();
  final releaseFinalization = Completer<void>();
  @override
  Future<List<TavernGenerationAttempt>> recoverInterruptedAttempts() {
    recoveries++;
    return super.recoverInterruptedAttempts();
  }

  @override
  Future<void> persistGenerationBatch(
    String id,
    List<TavernContentPart> parts, {
    TavernGenerationStatus? terminalStatus,
    String? reason,
    bool selectAlternative = false,
    String? expectedSelectedAlternativeId,
  }) async {
    if (holdFinalization &&
        terminalStatus == TavernGenerationStatus.completed) {
      finalizing.complete();
      await releaseFinalization.future;
    }
    await super.persistGenerationBatch(
      id,
      parts,
      terminalStatus: terminalStatus,
      reason: reason,
      selectAlternative: selectAlternative,
      expectedSelectedAlternativeId: expectedSelectedAlternativeId,
    );
  }
}

TavernProviderBinding _binding(
  TavernProviderBinding original, {
  TavernModelCapabilities? capabilities,
  String? baseUrl,
  Map<String, Object?>? parameters,
  Duration? timeout,
}) => TavernProviderBinding(
  config: original.config.copyWith(baseUrl: baseUrl),
  model: original.model,
  protocol: original.protocol,
  capabilities: capabilities ?? original.capabilities,
  parameters: parameters ?? original.parameters,
  outputTokens: original.outputTokens,
  timeout: timeout ?? original.timeout,
);

Future<String> _canonical(integration.TavernTestEnvironment env) async {
  final projection = await env.repo.loadTranscript('s', storyLineId: 'main');
  final signature = <Object?>[];
  for (final t in projection.turns) {
    signature.add([
      t.turn.id,
      t.selectedAlternative.id,
      t.alternatives.map((a) => a.id).toList(),
    ]);
    for (final a in t.alternatives) {
      signature.add(
        (await env.repo.listAttempts(
          a.id,
        )).map((a) => [a.id, a.status.name]).toList(),
      );
      signature.add(
        (await env.repo.listContentParts(
          a.id,
        )).map((p) => [p.id, p.text, p.kind.name]).toList(),
      );
    }
  }
  return jsonEncode(signature);
}

void main() {
  test(
    'Custom reads only its explicitly configured key reference and never inherits a builtin key',
    () async {
      final env = await integration.memoryEnvironment();
      addTearDown(() => env.owner.dispose());
      final now = DateTime.utc(2026);
      final custom = AiProviderConfig(
        id: 'custom-own',
        type: AiProviderType.custom,
        displayName: 'Synthetic custom',
        baseUrl: 'https://custom.invalid/v1',
        apiKeyRef: 'custom-own-ref',
        selectedModel: 'configured-model',
        enabled: true,
        connectionStatus: AiProviderConnectionStatus.untested,
        availableModels: const ['configured-model'],
        createdAtUtc: now,
        updatedAtUtc: now,
      );
      await SecureAiProviderConfigRepository(env.secure).saveConfig(custom);
      final binding = TavernProviderBinding(
        config: custom,
        model: custom.selectedModel,
        protocol: TavernProviderProtocol.chatCompletions,
        outputTokens: 16,
        capabilities: const TavernModelCapabilities(),
      );
      env.clients.add(
        fixture.FixtureTransport(utf8.encode(fixture.chatFixture())),
      );
      final result = await (await env.owner.start(
        integration.command('custom'),
        binding,
      )).done;
      expect(result.generation.phase, TavernExecutionPhase.completed);
      expect(env.sent.single.request!.url.host, 'custom.invalid');
      expect(
        env.sent.single.request!.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(
        (await env.repo.listAttempts('answer')).single.providerReference,
        'custom-own',
      );
      expect(
        jsonEncode(env.sent.single.body),
        isNot(contains('synthetic-credential')),
      );
    },
  );
  test(
    'different Sessions can pass preflight and generate concurrently',
    () async {
      final env = await integration.memoryEnvironment();
      addTearDown(() => env.owner.dispose());
      final now = DateTime.utc(2026);
      await env.repo.createSession(
        TavernSession(
          id: 's2',
          title: 'Second',
          createdAt: now,
          updatedAt: now,
        ),
        TavernStoryLine(
          id: 'main2',
          sessionId: 's2',
          name: 'Main',
          position: 0,
          createdAt: now,
        ),
      );
      await env.repo.addParticipant(
        const TavernParticipant(
          id: 'player2',
          sessionId: 's2',
          kind: TavernParticipantKind.persona,
          entityId: 'persona',
          position: 0,
        ),
      );
      await env.repo.addParticipant(
        const TavernParticipant(
          id: 'speaker2',
          sessionId: 's2',
          kind: TavernParticipantKind.character,
          entityId: 'character',
          position: 1,
        ),
      );
      await env.repo.appendTurn(
        TavernTurn(
          id: 'user2',
          sessionId: 's2',
          storyLineId: 'main2',
          position: 0,
          participantId: 'player2',
          role: TavernTurnRole.player,
          createdAt: now,
          updatedAt: now,
        ),
        TavernAlternative(
          id: 'user2-alt',
          turnId: 'user2',
          position: 0,
          origin: TavernAlternativeOrigin.manual,
          createdAt: now,
        ),
      );
      await env.repo.appendContentPart(
        TavernContentPart(
          id: 'user2-text',
          alternativeId: 'user2-alt',
          position: 0,
          kind: TavernContentKind.text,
          text: 'Synthetic input',
          createdAt: now,
        ),
      );
      final sources = _GateSources(env.owner.sources);
      await env.owner.dispose();
      await env.initialize(sources: sources);
      final a = env.owner.start(integration.command('first'), env.binding);
      final b = env.owner.start(
        const TavernGenerationCommand(
          commandId: 'second',
          attemptId: 'second',
          sessionId: 's2',
          storyLineId: 'main2',
          turnId: 'reply2',
          alternativeId: 'answer2',
          participantId: 'speaker2',
          contextTurnId: 'user2',
          kind: TavernGenerationCommandKind.normal,
        ),
        env.binding,
      );
      while (sources.calls < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      sources.release.complete();
      final results = await Future.wait([
        a.then((h) => h.done),
        b.then((h) => h.done),
      ]);
      expect(
        results.every(
          (r) => r.generation.phase == TavernExecutionPhase.completed,
        ),
        isTrue,
      );
      expect(env.sent, hasLength(2));
      expect(env.owner.ledger.stateFor('s', 'main').observedMessageCount, 1);
      expect(env.owner.ledger.stateFor('s2', 'main2').observedMessageCount, 1);
    },
  );

  test('recovery occurs exactly once before the first HTTP request', () async {
    final base = await integration.memoryEnvironment();
    await base.owner.dispose();
    final repo = _LifecycleRepository();
    final env = integration.TavernTestEnvironment(
      repo,
      base.characters,
      base.worlds,
    );
    await integration.seed(repo, base.characters, base.worlds);
    final now = DateTime.utc(2026);
    await repo.appendTurn(
      TavernTurn(
        id: 'interrupted',
        sessionId: 's',
        storyLineId: 'main',
        position: 1,
        participantId: 'speaker',
        role: TavernTurnRole.character,
        createdAt: now,
        updatedAt: now,
      ),
      TavernAlternative(
        id: 'interrupted-alt',
        turnId: 'interrupted',
        position: 0,
        origin: TavernAlternativeOrigin.generated,
        createdAt: now,
      ),
      attempt: TavernGenerationAttempt(
        id: 'old-attempt',
        sessionId: 's',
        storyLineId: 'main',
        turnId: 'interrupted',
        alternativeId: 'interrupted-alt',
        position: 0,
        status: TavernGenerationStatus.queued,
        type: TavernGenerationType.normal,
        createdAt: now,
      ),
    );
    await integration.userTurn(repo, 'next-user', line: 'main', position: 2);
    await env.initialize();
    addTearDown(() => env.owner.dispose());
    expect(repo.recoveries, 0);
    final gate = _GateSources(env.owner.sources);
    await env.owner.dispose();
    await env.initialize(sources: gate);
    final start = env.owner.start(
      integration.command('new', user: 'next-user'),
      env.binding,
    );
    await gate.reached.future;
    expect(repo.recoveries, 1);
    expect(
      (await repo.listAttempts('interrupted-alt')).single.status,
      TavernGenerationStatus.failed,
    );
    expect(env.sent, isEmpty);
    await env.owner.initialize();
    expect(repo.recoveries, 1);
    gate.release.complete();
    await (await start).done;
  });

  test(
    'Stop during finalization preserves exactly one canonical terminal outcome',
    () async {
      final base = await integration.memoryEnvironment();
      await base.owner.dispose();
      final repo = _LifecycleRepository()..holdFinalization = true;
      final env = integration.TavernTestEnvironment(
        repo,
        base.characters,
        base.worlds,
      );
      await integration.seed(repo, base.characters, base.worlds);
      await env.initialize();
      addTearDown(() => env.owner.dispose());
      final handle = await env.owner.start(
        integration.command('finalize'),
        env.binding,
      );
      await repo.finalizing.future;
      final stop = handle.cancel();
      repo.releaseFinalization.complete();
      await stop;
      final result = await handle.done;
      expect(result.generation.phase, TavernExecutionPhase.completed);
      expect(result.settlement, WorldInfoSettlement.committed);
      expect(
        (await repo.listAttempts('answer')).single.status,
        TavernGenerationStatus.completed,
      );
      final before = await _canonical(env);
      await handle.cancel();
      expect(await _canonical(env), before);
      expect(env.sent.single.closed, isTrue);
    },
  );
  for (final fault in [
    'credential',
    'session',
    'line',
    'alternative',
    'capability',
    'overflow',
    'configuration',
    'evaluation',
    'compiler',
  ]) {
    test(
      'preflight $fault is atomic with zero HTTP and unchanged canonical selection',
      () async {
        final env = await integration.memoryEnvironment();
        addTearDown(() => env.owner.dispose());
        await (await env.owner.start(
          integration.command('seed'),
          env.binding,
        )).done;
        await integration.userTurn(
          env.repo,
          'next-user',
          line: 'main',
          position: 2,
        );
        final before = await _canonical(env);
        final durable = env.repo as TavernWorldInfoRepository;
        final beforeState = await durable.loadWorldInfoState('s', 'main');
        final sent = env.sent.length;
        await env.owner.dispose();
        await env.initialize(
          ledger: fault == 'evaluation'
              ? _FailLedger(prepareFails: true)
              : null,
          compiler: fault == 'compiler'
              ? const _FailCompiler()
              : const PromptCompiler(EstimatedPromptTokenCounter()),
        );
        var binding = env.binding;
        if (fault == 'credential') {
          await SecureStorageApiKeyStore(
            env.secure,
          ).delete(binding.config.apiKeyRef);
        }
        if (fault == 'capability') {
          binding = _binding(
            binding,
            capabilities: const TavernModelCapabilities(streaming: false),
          );
        }
        if (fault == 'overflow') {
          binding = _binding(
            binding,
            capabilities: const TavernModelCapabilities(contextWindow: 32),
          );
        }
        if (fault == 'configuration') {
          binding = _binding(
            binding,
            baseUrl: 'https://not-configured.invalid',
          );
        }
        final command = TavernGenerationCommand(
          commandId: fault,
          attemptId: fault,
          sessionId: fault == 'session' ? 'missing' : 's',
          storyLineId: fault == 'line' ? 'missing' : 'main',
          turnId: fault == 'alternative' ? 'reply' : 'reply-two',
          alternativeId: fault == 'alternative' ? 'missing' : 'answer-two',
          contextTurnId: 'next-user',
          participantId: 'speaker',
          kind: fault == 'alternative'
              ? TavernGenerationCommandKind.continueTurn
              : TavernGenerationCommandKind.normal,
        );
        await expectLater(env.owner.start(command, binding), throwsA(anything));
        expect(env.sent.length, sent);
        expect(await _canonical(env), before);
        final afterState = await durable.loadWorldInfoState('s', 'main');
        expect(afterState.version, beforeState.version);
        expect(afterState.data.fingerprint, beforeState.data.fingerprint);
      },
    );
  }

  for (final kind in [
    TavernGenerationCommandKind.regenerate,
    TavernGenerationCommandKind.continueTurn,
  ]) {
    test('double ${kind.name} cannot pass simultaneous preflight', () async {
      final env = await integration.memoryEnvironment();
      addTearDown(() => env.owner.dispose());
      await (await env.owner.start(
        integration.command('seed'),
        env.binding,
      )).done;
      final sources = _GateSources(env.owner.sources);
      await env.owner.dispose();
      await env.initialize(sources: sources);
      final command = integration.command(
        'one',
        kind: kind,
        alt: kind == TavernGenerationCommandKind.regenerate
            ? 'new-answer'
            : 'answer',
      );
      final first = env.owner.start(command, env.binding);
      await sources.reached.future;
      expect(identical(env.owner.start(command, env.binding), first), isTrue);
      await expectLater(
        env.owner.start(integration.command('other', kind: kind), env.binding),
        throwsStateError,
      );
      expect(env.sent, hasLength(1));
      sources.release.complete();
      final result = await (await first).done;
      expect(result.generation.phase, TavernExecutionPhase.completed);
      expect(result.settlement, WorldInfoSettlement.committed);
      expect(sources.calls, 1);
      expect(env.sent, hasLength(2));
    });
  }

  test(
    'dispose during preflight prevents later Runtime creation and HTTP',
    () async {
      final env = await integration.memoryEnvironment();
      final gate = _GateSources(env.owner.sources);
      await env.owner.dispose();
      await env.initialize(sources: gate);
      final start = env.owner.start(integration.command('held'), env.binding);
      final rejected = expectLater(start, throwsStateError);
      await gate.reached.future;
      final dispose = env.owner.dispose();
      gate.release.complete();
      await rejected;
      await dispose;
      expect(env.sent, isEmpty);
      expect((await env.repo.loadTranscript('s')).turns, hasLength(1));
    },
  );

  test('same command cannot silently change an unlisted capability', () async {
    final env = await integration.memoryEnvironment();
    addTearDown(() => env.owner.dispose());
    final command = integration.command('same');
    final first = env.owner.start(command, env.binding);
    await expectLater(
      env.owner.start(
        command,
        _binding(
          env.binding,
          capabilities: const TavernModelCapabilities(systemRole: false),
        ),
      ),
      throwsStateError,
    );
    await (await first).done;
    expect(env.sent, hasLength(1));
  });

  test(
    'compiled segments are exactly the serialized request messages',
    () async {
      final env = await integration.memoryEnvironment();
      addTearDown(() => env.owner.dispose());
      await env.owner.dispose();
      final compiler = _CaptureCompiler();
      await env.initialize(compiler: compiler);
      final result = await (await env.owner.start(
        integration.command('capture'),
        env.binding,
      )).done;
      final prompt = compiler.captured!;
      final serialized = (env.sent.single.body!['messages'] as List)
          .cast<Map>();
      expect(
        serialized.map((m) => m['content']).toList(),
        prompt.segments
            .map((s) => s.atoms.map((a) => a.text ?? '').join('\n'))
            .where((s) => s.isNotEmpty)
            .toList(),
      );
      expect(
        serialized.map((m) => m['role']).toList(),
        prompt.segments
            .map(
              (s) => s.role == PromptRoleIntent.systemLike
                  ? 'system'
                  : s.role == PromptRoleIntent.assistantLike
                  ? 'assistant'
                  : 'user',
            )
            .toList(),
      );
      expect(jsonEncode(serialized), isNot(contains('synthetic-credential')));
      expect(
        result.trace.compilation.decisions.any(
          (d) => d.origin.type == 'worldInfoEntry',
        ),
        isTrue,
      );
      expect(serialized.where((m) => m['role'] == 'system'), hasLength(1));
    },
  );

  test(
    'changed request fingerprint fails before HTTP and discards ledger plan',
    () async {
      final env = await integration.memoryEnvironment();
      addTearDown(() => env.owner.dispose());
      await env.owner.dispose();
      int clients = 0;
      await env.initialize(
        adapter: _ChangingAdapter(() {
          clients++;
          return fixture.FixtureTransport([]);
        }),
      );
      final result = await (await env.owner.start(
        integration.command('fingerprint'),
        env.binding,
      )).done;
      expect(result.generation.phase, TavernExecutionPhase.failed);
      expect(result.settlement, WorldInfoSettlement.discarded);
      expect(
        result.trace.provider.failure?.kind,
        TavernProviderErrorKind.malformedResponse,
      );
      expect(clients, 0);
      expect(env.owner.ledger.stateFor('s', 'main').observedMessageCount, 0);
      expect(
        (await env.repo.loadTranscript('s')).turns.last.visibleParts,
        isEmpty,
      );
    },
  );

  for (final stage in [
    'connecting',
    'streaming',
    'after-final-delta',
    'timeout',
  ]) {
    test('$stage closes request transport with one terminal Attempt', () async {
      final env = await integration.memoryEnvironment();
      addTearDown(() => env.owner.dispose());
      final client = _ControlledTransport(connecting: stage == 'connecting');
      env.clients.add(client);
      final handle = await env.owner.start(
        integration.command('stop'),
        _binding(
          env.binding,
          timeout: stage == 'timeout'
              ? const Duration(milliseconds: 150)
              : null,
        ),
      );
      await client.started.future;
      if (stage != 'connecting') {
        client.stream.add(
          utf8.encode(
            fixture.frame({
              'choices': [
                {
                  'delta': {'content': 'partial'},
                  'finish_reason': stage == 'after-final-delta' ? 'stop' : null,
                },
              ],
            }),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      if (stage != 'timeout') await handle.cancel();
      final result = await handle.done;
      expect(client.closed, isTrue);
      expect(
        result.generation.phase,
        stage == 'timeout'
            ? TavernExecutionPhase.failed
            : TavernExecutionPhase.cancelled,
      );
      expect(await env.repo.listAttempts('answer'), hasLength(1));
      expect(result.settlement, WorldInfoSettlement.discarded);
      expect(
        (await env.repo.loadTranscript('s')).turns.last.visibleParts,
        isEmpty,
      );
      expect(env.owner.ledger.stateFor('s', 'main').observedMessageCount, 0);
    });
  }

  test(
    'Gemini empty summary and signature-only parts persist unavailable, not fabricated reasoning',
    () async {
      final env = await integration.memoryEnvironment();
      addTearDown(() => env.owner.dispose());
      final config = fixture.fixtureConfig(AiProviderType.gemini);
      await SecureAiProviderConfigRepository(env.secure).saveConfig(config);
      final payload = fixture.frame({
        'candidates': [
          {
            'content': {
              'parts': [
                {'thought': true, 'text': ''},
                {'thoughtSignature': 'synthetic-signature'},
                {'text': 'visible'},
              ],
            },
            'finishReason': 'STOP',
          },
        ],
      });
      env.clients.add(fixture.FixtureTransport(utf8.encode(payload)));
      final result = await (await env.owner.start(
        integration.command('gemini'),
        fixture.fixtureBinding(AiProviderType.gemini),
      )).done;
      expect(result.generation.phase, TavernExecutionPhase.completed);
      expect(
        result.trace.provider.reasoning,
        TavernReasoningAvailability.unavailable,
      );
      final parts = await env.repo.listContentParts('answer');
      expect(
        parts.where((p) => p.kind == TavernContentKind.reasoningUnavailable),
        hasLength(1),
      );
      expect(parts.every((p) => p.generationAttemptId == 'gemini'), isTrue);
      expect(
        jsonEncode(parts.map((p) => p.text).toList()),
        isNot(contains('synthetic-signature')),
      );
    },
  );

  test(
    'root ProviderScope owns one non-autoDispose execution environment',
    () async {
      final env = await integration.memoryEnvironment();
      await env.owner.dispose();
      final client = _ControlledTransport();
      final container = ProviderContainer(
        overrides: [
          tavernRepositoryProvider.overrideWithValue(env.repo),
          characterRepositoryProvider.overrideWithValue(env.characters),
          worldRoleplayRepositoryProvider.overrideWithValue(env.worlds),
          aiSecureValueStoreProvider.overrideWithValue(env.secure),
          aiHttpClientFactoryProvider.overrideWithValue(() => client),
        ],
      );
      final owner = container.read(tavernExecutionProvider);
      final first = container.listen(tavernExecutionProvider, (_, _) {});
      first.close();
      await Future<void>.delayed(Duration.zero);
      final second = container.listen(tavernExecutionProvider, (_, _) {});
      expect(identical(owner, second.read()), isTrue);
      expect(identical(owner.initialize(), owner.initialize()), isTrue);
      final handle = await owner.start(
        integration.command('scope'),
        env.binding,
      );
      await client.started.future;
      second.close();
      expect(client.closed, isFalse);
      container.dispose();
      final result = await handle.done;
      expect(result.generation.phase, TavernExecutionPhase.cancelled);
      expect(client.closed, isTrue);
      await owner.dispose();
    },
  );

  test(
    'restart preserves durable reconciliation blockage without any repeated HTTP',
    () async {
      final repo = integration.ConflictingMemoryRepository();
      final env = await integration.memoryEnvironment(repository: repo);
      addTearDown(() => env.owner.dispose());
      final result = await (await env.owner.start(
        integration.command('unsettled'),
        env.binding,
      )).done;
      expect(result.generation.phase, TavernExecutionPhase.completed);
      expect(result.ledgerFailure, isTrue);
      await integration.userTurn(
        env.repo,
        'next-user',
        line: 'main',
        position: 2,
      );
      await expectLater(
        env.owner.start(
          integration.command(
            'blocked',
            user: 'next-user',
            turn: 'next',
            alt: 'next-alt',
          ),
          env.binding,
        ),
        throwsA(isA<TavernReconciliationConflict>()),
      );
      await env.owner.dispose();
      await env.initialize();
      expect(
        (await env.repo.listAttempts('answer')).single.status,
        TavernGenerationStatus.completed,
      );
      expect(
        await env.owner.retryLedgerSettlement('unsettled'),
        WorldInfoSettlement.stale,
      );
      expect(env.owner.ledger.stateFor('s', 'main').observedMessageCount, 0);
      await expectLater(
        env.owner.start(
          integration.command(
            'after-restart',
            user: 'next-user',
            turn: 'next',
            alt: 'next-alt',
          ),
          env.binding,
        ),
        throwsA(isA<TavernReconciliationConflict>()),
      );
      expect(env.sent, hasLength(1));
    },
  );
}
