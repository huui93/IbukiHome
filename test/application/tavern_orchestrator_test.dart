import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ibukihome/application/backup/backup_archive_codec.dart';
import 'package:ibukihome/application/tavern/provider/tavern_provider_driver.dart';
import 'package:ibukihome/application/tavern/provider/tavern_provider_models.dart';
import 'package:ibukihome/application/tavern/prompt/prompt_compiler.dart';
import 'package:ibukihome/application/tavern/provider/tavern_model_profile_store.dart';
import 'package:ibukihome/application/tavern/tavern_generation_orchestrator.dart';
import 'package:ibukihome/application/tavern/tavern_generation_runtime.dart';
import 'package:ibukihome/application/tavern/tavern_source_resolver.dart';
import 'package:ibukihome/application/tavern/world_info/world_info_attempt_ledger.dart';
import 'package:ibukihome/data/ai/tavern_provider_adapter.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_character_repository.dart';
import 'package:ibukihome/data/memory/in_memory_world_roleplay_repository.dart';
import 'package:ibukihome/data/memory/in_memory_secure_value_store.dart';
import 'package:ibukihome/data/memory/in_memory_tavern_repository.dart';
import 'package:ibukihome/data/repositories/tavern_repository.dart';
import 'package:ibukihome/data/repositories/character_repository.dart';
import 'package:ibukihome/data/repositories/world_roleplay_repository.dart';
import 'package:ibukihome/data/secure/secure_ai_provider_config_repository.dart';
import 'package:ibukihome/data/secure/secure_storage_api_key_store.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_tavern_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_character_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_world_roleplay_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_project_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_backup_snapshot_store.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/tavern/tavern_models.dart';
import 'package:ibukihome/domain/tavern/tavern_world_info.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_models.dart';
import 'tavern_provider_adapter_test.dart' as fixture;

final _now = DateTime.utc(2026, 10, 14);
EntityMetadata _entity(String id) =>
    EntityMetadata(id: id, createdAt: _now, updatedAt: _now, revision: 1);
Project _project() =>
    Project(metadata: _entity('project'), title: 'Synthetic', description: '');

Future<void> seed(
  TavernRepository repo,
  CharacterRepository characters,
  WorldRoleplayRepository worlds, {
  Map<String, Object?> sessionMetadata = const {},
}) async {
  await characters.upsertCharacter(
    CharacterCard(
      metadata: _entity('character'),
      projectId: 'project',
      name: 'Mira',
      content: 'Playful dragon; concise replies.',
      sortOrder: 0,
    ),
  );
  await worlds.upsertWorld(
    RoleplayWorld(
      entity: _entity('world'),
      name: 'Synthetic world',
      description: 'Dining hall',
    ),
  );
  await worlds.upsertPersona(
    PlayerPersona(
      entity: _entity('persona'),
      worldId: 'world',
      name: 'Player',
      description: 'Public identity',
      notes: 'SECRET-NOT-FOR-SPEAKER',
      metadata: const {
        'knowledgeVisibility': {'notes': 'private'},
      },
    ),
  );
  await worlds.upsertWorldBook(
    WorldBook(entity: _entity('book'), name: 'North tower'),
  );
  await worlds.upsertLoreEntry(
    LoreEntry(
      entity: _entity('lore'),
      worldBookId: 'book',
      title: 'Tower',
      content: 'North tower lore',
      keywords: const ['north'],
    ),
  );
  await worlds.upsertWorldBookReference(
    WorldWorldBookReference(
      entity: _entity('ref'),
      worldId: 'world',
      worldBookId: 'book',
    ),
  );
  await worlds.upsertCharacterWorldBookReference(
    EntityWorldBookReference(
      entity: _entity('char-ref'),
      entityId: 'character',
      worldBookId: 'book',
    ),
  );
  await worlds.upsertPersonaWorldBookReference(
    EntityWorldBookReference(
      entity: _entity('persona-ref'),
      entityId: 'persona',
      worldBookId: 'book',
    ),
  );
  await repo.createSession(
    TavernSession(
      id: 's',
      title: 'Real Foundation fixture',
      createdAt: _now,
      updatedAt: _now,
      worldAssetType: 'roleplayWorld',
      worldAssetId: 'world',
      personaType: 'playerPersona',
      personaId: 'persona',
      metadata: sessionMetadata,
    ),
    TavernStoryLine(
      id: 'main',
      sessionId: 's',
      name: 'Main',
      position: 0,
      createdAt: _now,
    ),
  );
  await repo.addParticipant(
    const TavernParticipant(
      id: 'player',
      sessionId: 's',
      kind: TavernParticipantKind.persona,
      entityId: 'persona',
      position: 0,
    ),
  );
  await repo.addParticipant(
    const TavernParticipant(
      id: 'speaker',
      sessionId: 's',
      kind: TavernParticipantKind.character,
      entityId: 'character',
      displayName: 'Mira',
      position: 1,
    ),
  );
  await userTurn(repo, 'user', line: 'main', position: 0);
}

Future<void> userTurn(
  TavernRepository repo,
  String id, {
  required String line,
  required int position,
}) async {
  await repo.appendTurn(
    TavernTurn(
      id: id,
      sessionId: 's',
      storyLineId: line,
      position: position,
      participantId: 'player',
      role: TavernTurnRole.player,
      createdAt: _now,
      updatedAt: _now,
    ),
    TavernAlternative(
      id: '$id-alt',
      turnId: id,
      position: 0,
      origin: TavernAlternativeOrigin.manual,
      createdAt: _now,
    ),
  );
  await repo.appendContentPart(
    TavernContentPart(
      id: '$id-text',
      alternativeId: '$id-alt',
      position: 0,
      kind: TavernContentKind.text,
      text: 'Look at the north tower.',
      createdAt: _now,
    ),
  );
}

TavernGenerationCommand command(
  String id, {
  String line = 'main',
  String turn = 'reply',
  String alt = 'answer',
  String user = 'user',
  TavernGenerationCommandKind kind = TavernGenerationCommandKind.normal,
}) => TavernGenerationCommand(
  commandId: id,
  sessionId: 's',
  storyLineId: line,
  turnId: turn,
  alternativeId: alt,
  attemptId: id,
  participantId: 'speaker',
  contextTurnId: user,
  kind: kind,
);

class TavernTestEnvironment {
  TavernTestEnvironment(this.repo, this.characters, this.worlds);
  final TavernRepository repo;
  final CharacterRepository characters;
  final WorldRoleplayRepository worlds;
  final secure = InMemorySecureValueStore();
  final clients = <http.Client>[];
  final sent = <fixture.FixtureTransport>[];
  late TavernGenerationOrchestrator owner;
  late TavernProviderBinding binding;
  Future<void> initialize({
    WorldInfoAttemptLedger? ledger,
    TavernSourceResolver? sources,
    PromptCompiler compiler = const PromptCompiler(
      EstimatedPromptTokenCounter(),
    ),
    TavernProviderAdapter? adapter,
  }) async {
    final configs = SecureAiProviderConfigRepository(secure);
    final config = fixture.fixtureConfig(AiProviderType.deepseek);
    await configs.saveConfig(config);
    final keys = SecureStorageApiKeyStore(secure);
    await keys.write(config.apiKeyRef, 'synthetic-credential');
    binding = TavernProviderBinding(
      config: config,
      model: 'configured-model',
      protocol: TavernProviderProtocol.chatCompletions,
      capabilities: const TavernModelCapabilities(
        contextWindow: 4096,
        maximumOutput: 128,
        reasoning: TavernReasoningAvailability.native,
        continuation: TavernContinuation.instruction,
      ),
      outputTokens: 16,
    );
    final driver = TavernProviderDriver(
      adapter ??
          TavernProviderAdapter(() {
            final client = clients.isEmpty
                ? fixture.FixtureTransport(
                    utf8.encode(fixture.chatFixture(reasoning: true)),
                  )
                : clients.removeAt(0);
            if (client is fixture.FixtureTransport) sent.add(client);
            return client;
          }),
      onStage: (id, streaming) => owner.observeProviderStage(id, streaming),
    );
    owner = TavernGenerationOrchestrator(
      repository: repo,
      configs: configs,
      keys: keys,
      compiler: compiler,
      sources:
          sources ??
          NativeTavernSourceResolver(
            repository: repo,
            characters: characters,
            worlds: worlds,
          ),
      driver: driver,
      ledger: ledger,
    );
  }
}

Future<TavernTestEnvironment> memoryEnvironment({
  TavernRepository? repository,
  WorldInfoAttemptLedger? ledger,
  Map<String, Object?> sessionMetadata = const {},
}) async {
  final store = InMemoryIbukiStore()..putProject(_project());
  final env = TavernTestEnvironment(
    repository ?? InMemoryTavernRepository(),
    InMemoryCharacterRepository(store),
    InMemoryWorldRoleplayRepository(store),
  );
  await seed(
    env.repo,
    env.characters,
    env.worlds,
    sessionMetadata: sessionMetadata,
  );
  await env.initialize(ledger: ledger);
  return env;
}

class _StreamingTransport extends http.BaseClient {
  final stream = StreamController<List<int>>();
  final started = Completer<void>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    started.complete();
    return http.StreamedResponse(
      stream.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  @override
  void close() {
    closed = true;
    if (!stream.isClosed) unawaited(stream.close());
  }
}

class ConflictingMemoryRepository extends InMemoryTavernRepository {
  bool fail = true;
  TavernWorldInfoSnapshot? beforeConflict;
  @override
  Future<void> persistGenerationBatch(
    String attemptId,
    List<TavernContentPart> parts, {
    TavernGenerationStatus? terminalStatus,
    String? reason,
    bool selectAlternative = false,
    String? expectedSelectedAlternativeId,
  }) async {
    if (fail && terminalStatus == TavernGenerationStatus.completed) {
      fail = false;
      final line = attempts[attemptId]!.storyLineId;
      final state = beforeConflict = worldInfoStates[line]!;
      worldInfoStates[line] = TavernWorldInfoSnapshot(
        sessionId: state.sessionId,
        storyLineId: line,
        version: state.version + 1,
        data: state.data,
        initialData: state.initialData,
        provenance: state.provenance,
      );
    }
    await super.persistGenerationBatch(
      attemptId,
      parts,
      terminalStatus: terminalStatus,
      reason: reason,
      selectAlternative: selectAlternative,
      expectedSelectedAlternativeId: expectedSelectedAlternativeId,
    );
  }

  void repairInjectedVersion() =>
      worldInfoStates[beforeConflict!.storyLineId] = beforeConflict!;
}

void main() {
  test(
    'native source resolver restricts books and session overrides without copying entries',
    () async {
      final env = await memoryEnvironment(
        sessionMetadata: const {
          'worldInfoBookOverridesV1': {
            'book': 'disabled',
            'unreferenced': 'enabled',
          },
        },
      );
      addTearDown(env.owner.dispose);
      await env.worlds.upsertWorldBook(
        WorldBook(entity: _entity('unreferenced'), name: 'Not authorized'),
      );
      await env.worlds.upsertLoreEntry(
        LoreEntry(
          entity: _entity('hidden-lore'),
          worldBookId: 'unreferenced',
          title: 'Unknown',
          content: 'UNREFERENCED-NOT-SENT',
          activationMode: LoreActivationMode.always,
        ),
      );
      final result = await (await env.owner.start(
        command('books'),
        env.binding,
      )).done;
      expect(result.trace.activation.checked, 0);
      expect(
        jsonEncode(env.sent.single.body),
        isNot(contains('UNREFERENCED-NOT-SENT')),
      );
    },
  );
  test(
    'session enables known disabled reference, while hidden lore stays excluded',
    () async {
      final env = await memoryEnvironment(
        sessionMetadata: const {
          'worldInfoBookOverridesV1': {'book': 'enabled'},
        },
      );
      addTearDown(env.owner.dispose);
      await env.worlds.deleteCharacterWorldBookReference('char-ref');
      await env.worlds.deletePersonaWorldBookReference('persona-ref');
      final reference = (await env.worlds.listWorldBookReferences(
        'world',
      )).single;
      await env.worlds.upsertWorldBookReference(
        reference.copyWith(enabled: false),
      );
      await env.worlds.upsertLoreEntry(
        LoreEntry(
          entity: _entity('private-lore'),
          worldBookId: 'book',
          title: 'Hidden',
          content: 'PRIVATE-LORE-NOT-SENT',
          scope: 'private',
          activationMode: LoreActivationMode.always,
        ),
      );
      final result = await (await env.owner.start(
        command('known-book'),
        env.binding,
      )).done;
      expect(result.trace.activation.active, 1);
      expect(
        jsonEncode(env.sent.single.body),
        isNot(contains('PRIVATE-LORE-NOT-SENT')),
      );
    },
  );
  test(
    'completed domain result with failed ledger blocks next request until idempotent reconciliation',
    () async {
      final repo = ConflictingMemoryRepository();
      final env = await memoryEnvironment(repository: repo);
      addTearDown(env.owner.dispose);
      final result = await (await env.owner.start(
        command('one'),
        env.binding,
      )).done;
      expect(result.generation.phase, TavernExecutionPhase.completed);
      expect(result.ledgerFailure, isTrue);
      expect(
        (await env.repo.listAttempts('answer')).single.status,
        TavernGenerationStatus.completed,
      );
      await userTurn(env.repo, 'next-user', line: 'main', position: 2);
      await expectLater(
        env.owner.start(
          command(
            'blocked',
            user: 'next-user',
            turn: 'reply-two',
            alt: 'alt-two',
          ),
          env.binding,
        ),
        throwsA(isA<TavernReconciliationConflict>()),
      );
      expect(env.sent, hasLength(1));
      repo.repairInjectedVersion();
      expect(
        await env.owner.retryLedgerSettlement('one'),
        WorldInfoSettlement.committed,
      );
      expect(env.sent, hasLength(1));
      final next = await (await env.owner.start(
        command('next', user: 'next-user', turn: 'reply-two', alt: 'alt-two'),
        env.binding,
      )).done;
      expect(next.ledgerFailure, isFalse);
    },
  );
  test(
    'awaited app dispose closes active HTTP and leaves no active Attempt',
    () async {
      final env = await memoryEnvironment();
      final transport = _StreamingTransport();
      env.clients.add(transport);
      final handle = await env.owner.start(command('dispose'), env.binding);
      await transport.started.future;
      await env.owner.dispose();
      expect(transport.closed, isTrue);
      expect(
        (await handle.done).generation.phase,
        TavernExecutionPhase.cancelled,
      );
      expect(
        (await env.repo.listAttempts('answer')).single.status,
        TavernGenerationStatus.cancelled,
      );
    },
  );
  test(
    'summary and unavailable persist as independent typed content, never visible RP text',
    () async {
      for (final summary in [true, false]) {
        final env = await memoryEnvironment();
        addTearDown(env.owner.dispose);
        final config = fixture.fixtureConfig(AiProviderType.openai);
        await SecureAiProviderConfigRepository(env.secure).saveConfig(config);
        final binding = TavernProviderBinding(
          config: config,
          model: 'configured-model',
          protocol: TavernProviderProtocol.responses,
          outputTokens: 16,
          capabilities: TavernModelCapabilities(
            contextWindow: 4096,
            maximumOutput: 128,
            reasoning: summary
                ? TavernReasoningAvailability.summary
                : TavernReasoningAvailability.unavailable,
          ),
        );
        env.clients.add(
          fixture.FixtureTransport(
            utf8.encode(fixture.responsesFixture(reasoning: summary)),
          ),
        );
        final result = await (await env.owner.start(
          command('reasoning'),
          binding,
        )).done;
        expect(result.generation.phase, TavernExecutionPhase.completed);
        final parts = await env.repo.listContentParts('answer');
        expect(
          parts.any(
            (p) =>
                p.kind ==
                (summary
                    ? TavernContentKind.reasoningSummary
                    : TavernContentKind.reasoningUnavailable),
          ),
          isTrue,
        );
        expect(
          (await env.repo.loadTranscript(
            's',
          )).turns.last.visibleParts.map((p) => p.text).join(),
          '你好',
        );
      }
    },
  );
  test(
    'formal Foundation -> native sources -> WI -> compiler -> HTTP driver -> Runtime -> ledger',
    () async {
      final env = await memoryEnvironment();
      addTearDown(env.owner.dispose);
      final handle = await env.owner.start(command('normal'), env.binding);
      final result = await handle.done;
      expect(result.generation.phase, TavernExecutionPhase.completed);
      expect(result.settlement, WorldInfoSettlement.committed);
      expect(result.ledgerFailure, isFalse);
      expect(result.trace.activation.active, 1);
      expect(
        result.trace.compilation.decisions.where(
          (d) => d.origin.type == 'worldInfoEntry',
        ),
        hasLength(1),
      );
      final projection = await env.repo.loadTranscript('s');
      expect(
        projection.turns.last.visibleParts.map((p) => p.text).join(),
        '你好',
      );
      final parts = await env.repo.listContentParts('answer');
      expect(
        parts.where((p) => p.kind == TavernContentKind.reasoning).single.text,
        '思考',
      );
      expect(
        (await env.repo.listAttempts('answer')).single.providerReference,
        'deepseek',
      );
      final body = jsonEncode(env.sent.single.body);
      expect(body, contains('North tower lore'));
      expect(body, contains('Public identity'));
      expect(body, isNot(contains('SECRET-NOT-FOR-SPEAKER')));
      expect(env.owner.ledger.stateFor('s', 'main').observedMessageCount, 1);
      expect(result.trace.provider.inputTokens, 12);
    },
  );
  test(
    'preflight failure sends zero requests and creates no Attempt or Turn',
    () async {
      final env = await memoryEnvironment();
      addTearDown(env.owner.dispose);
      final config = env.binding.config;
      final invalid = TavernProviderBinding(
        config: config,
        model: 'configured-model',
        protocol: env.binding.protocol,
        capabilities: const TavernModelCapabilities(
          contextWindow: 16,
          maximumOutput: 8,
        ),
        outputTokens: 8,
      );
      await expectLater(
        env.owner.start(command('invalid'), invalid),
        throwsA(anything),
      );
      expect((await env.repo.loadTranscript('s')).turns, hasLength(1));
      expect(env.sent, isEmpty);
      expect(env.owner.ledger.stateFor('s', 'main').observedMessageCount, 0);
    },
  );
  test(
    'double send reuses same command; different command is rejected during preflight',
    () async {
      final env = await memoryEnvironment();
      addTearDown(env.owner.dispose);
      final a = env.owner.start(command('same'), env.binding);
      final b = env.owner.start(command('same'), env.binding);
      expect(identical(a, b), isTrue);
      await expectLater(
        env.owner.start(command('different'), env.binding),
        throwsStateError,
      );
      await (await a).done;
      await (await b).done;
      expect(env.sent, hasLength(1));
      expect(await env.repo.listAttempts('answer'), hasLength(1));
    },
  );
  test(
    'HTTP failure leaves lore uncommitted, retry keeps Alternative and persists new Attempt',
    () async {
      final env = await memoryEnvironment();
      addTearDown(env.owner.dispose);
      env.clients.add(
        fixture.FixtureTransport(
          utf8.encode('{"error":"unauthorized"}'),
          status: 401,
        ),
      );
      final failed = await (await env.owner.start(
        command('failed'),
        env.binding,
      )).done;
      expect(failed.generation.phase, TavernExecutionPhase.failed);
      expect(
        failed.trace.provider.failure?.kind,
        TavernProviderErrorKind.authentication,
      );
      expect(failed.settlement, WorldInfoSettlement.discarded);
      final retried = await (await env.owner.start(
        command('retry', kind: TavernGenerationCommandKind.retry),
        env.binding,
      )).done;
      expect(retried.settlement, WorldInfoSettlement.committed);
      expect((await env.repo.listAttempts('answer')).map((a) => a.status), [
        TavernGenerationStatus.failed,
        TavernGenerationStatus.completed,
      ]);
      expect(
        (await env.repo.loadTranscript('s')).turns.last.alternatives,
        hasLength(1),
      );
    },
  );
  test(
    'stream Stop aborts transport, late text is isolated and partial excluded from retry',
    () async {
      final env = await memoryEnvironment();
      addTearDown(env.owner.dispose);
      final transport = _StreamingTransport();
      env.clients.add(transport);
      final handle = await env.owner.start(command('cancel'), env.binding);
      await transport.started.future;
      transport.stream.add(
        utf8.encode(
          fixture.frame({
            'choices': [
              {
                'delta': {'content': 'PARTIAL-EXCLUDED'},
                'finish_reason': null,
              },
            ],
          }),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await handle.cancel();
      final result = await handle.done;
      expect(transport.closed, isTrue);
      expect(result.generation.phase, TavernExecutionPhase.cancelled);
      expect(result.settlement, WorldInfoSettlement.discarded);
      expect(
        (await env.repo.loadTranscript('s')).turns.last.visibleParts,
        isEmpty,
      );
      await (await env.owner.start(
        command('retry', kind: TavernGenerationCommandKind.retry),
        env.binding,
      )).done;
      expect(
        jsonEncode(env.sent.last.body),
        isNot(contains('PARTIAL-EXCLUDED')),
      );
    },
  );
  test(
    'Normal, Regenerate, frozen branch, Continue, failure and Retry preserve history',
    () async {
      final env = await memoryEnvironment();
      addTearDown(env.owner.dispose);
      await (await env.owner.start(command('normal'), env.binding)).done;
      await env.repo.createStoryLine(
        TavernStoryLine(
          id: 'child',
          sessionId: 's',
          name: 'Child',
          position: 1,
          createdAt: _now,
          parentId: 'main',
          originTurnId: 'reply',
          originAlternativeId: 'answer',
        ),
      );
      await (await env.owner.start(
        command(
          'regenerate',
          kind: TavernGenerationCommandKind.regenerate,
          alt: 'answer-2',
        ),
        env.binding,
      )).done;
      expect(
        (await env.repo.loadTranscript(
          's',
          storyLineId: 'child',
        )).turns.last.selectedAlternative.id,
        'answer',
      );
      expect(
        (await env.repo.loadTranscript(
          's',
          storyLineId: 'main',
        )).turns.last.selectedAlternative.id,
        'answer-2',
      );
      await env.repo.selectAlternative('reply', 'answer');
      env.clients.add(
        fixture.FixtureTransport(
          utf8.encode(fixture.chatFixture(finish: 'length')),
        ),
      );
      final failed = await (await env.owner.start(
        command(
          'continue-fail',
          kind: TavernGenerationCommandKind.continueTurn,
        ),
        env.binding,
      )).done;
      expect(failed.generation.phase, TavernExecutionPhase.failed);
      final retry = await (await env.owner.start(
        command('continue-retry', kind: TavernGenerationCommandKind.retry),
        env.binding,
      )).done;
      expect(retry.generation.phase, TavernExecutionPhase.completed);
      expect(
        (await env.repo.loadTranscript(
          's',
        )).turns.last.visibleParts.map((p) => p.text).join(),
        '你好你好',
      );
      expect((env.sent.last.body!['messages'] as List).last['role'], 'user');
    },
  );
  test(
    'switching displayed Story Line never changes terminal ledger target',
    () async {
      final env = await memoryEnvironment();
      addTearDown(env.owner.dispose);
      final transport = _StreamingTransport();
      env.clients.add(transport);
      final handle = await env.owner.start(command('slow'), env.binding);
      await transport.started.future;
      await env.repo.createStoryLine(
        TavernStoryLine(
          id: 'empty',
          sessionId: 's',
          name: 'Other',
          position: 1,
          createdAt: _now,
          parentId: 'main',
          originTurnId: 'user',
          originAlternativeId: 'user-alt',
        ),
        activate: true,
      );
      transport.stream.add(utf8.encode(fixture.chatFixture()));
      await transport.stream.close();
      final result = await handle.done;
      expect(result.settlement, WorldInfoSettlement.committed);
      expect(env.owner.ledger.stateFor('s', 'main').observedMessageCount, 1);
      expect(env.owner.ledger.stateFor('s', 'empty').observedMessageCount, 0);
    },
  );
  test(
    'explicit capabilities persist independently without reading or storing API keys',
    () async {
      final env = await memoryEnvironment();
      addTearDown(env.owner.dispose);
      final profiles = TavernModelProfileStore(env.secure);
      await profiles.save(env.binding);
      final loaded = await profiles.load(env.binding.config, env.binding.model);
      expect(loaded.capabilities.reasoning, TavernReasoningAvailability.native);
      expect(loaded.capabilities.continuation, TavernContinuation.instruction);
      expect(
        env.secure.debugSnapshot.entries
            .where((e) => e.key.startsWith('tavern.model-profile'))
            .single
            .value,
        isNot(contains('synthetic-credential')),
      );
    },
  );
  test(
    'SQLite E2E preserves typed content/attempts and canonical branch through archive/reopen',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp(
        'tavern_phase10_',
      );
      IbukiDatabase db(String name) => IbukiDatabase(
        pathResolver: () async => p.join(directory.path, name),
        databaseFactory: databaseFactoryFfi,
      );
      final sourceDb = db('source.db');
      final source = SQLiteTavernRepository(sourceDb);
      try {
        await SQLiteProjectRepository(sourceDb).upsertProject(_project());
        final chars = SQLiteCharacterRepository(sourceDb);
        final worlds = SQLiteWorldRoleplayRepository(sourceDb);
        await seed(source, chars, worlds);
        final env = TavernTestEnvironment(source, chars, worlds);
        await env.initialize();
        await (await env.owner.start(command('normal'), env.binding)).done;
        await source.createStoryLine(
          TavernStoryLine(
            id: 'child',
            sessionId: 's',
            name: 'Child',
            position: 1,
            createdAt: _now,
            parentId: 'main',
            originTurnId: 'reply',
            originAlternativeId: 'answer',
          ),
        );
        await (await env.owner.start(
          command(
            'regen',
            kind: TavernGenerationCommandKind.regenerate,
            alt: 'answer-2',
          ),
          env.binding,
        )).done;
        await (await env.owner.start(
          command(
            'continue',
            kind: TavernGenerationCommandKind.continueTurn,
            alt: 'answer-2',
          ),
          env.binding,
        )).done;
        env.clients.add(
          fixture.FixtureTransport(
            utf8.encode(fixture.chatFixture(finish: 'length', reasoning: true)),
          ),
        );
        final failed = await (await env.owner.start(
          command(
            'failed-continuation',
            kind: TavernGenerationCommandKind.continueTurn,
            alt: 'answer-2',
          ),
          env.binding,
        )).done;
        expect(failed.generation.phase, TavernExecutionPhase.failed);
        expect(failed.settlement, WorldInfoSettlement.discarded);
        final transport = _StreamingTransport();
        env.clients.add(transport);
        final cancelled = await env.owner.start(
          command(
            'cancelled-retry',
            kind: TavernGenerationCommandKind.retry,
            alt: 'answer-2',
          ),
          env.binding,
        );
        await transport.started.future;
        await cancelled.cancel();
        expect(
          (await cancelled.done).generation.phase,
          TavernExecutionPhase.cancelled,
        );
        final retried = await (await env.owner.start(
          command(
            'completed-retry',
            kind: TavernGenerationCommandKind.retry,
            alt: 'answer-2',
          ),
          env.binding,
        )).done;
        expect(retried.settlement, WorldInfoSettlement.committed);
        expect(
          (await source.loadTranscript(
            's',
          )).turns.last.visibleParts.map((p) => p.text).join(),
          '你好你好你好',
        );
        await env.owner.dispose();
        Future<String> signature(TavernRepository repo) async {
          final lines = <Object?>[];
          for (final line in ['main', 'child']) {
            final projection = await repo.loadTranscript(
              's',
              storyLineId: line,
            );
            lines.add([
              line,
              projection.turns
                  .map(
                    (t) => [
                      t.turn.id,
                      t.selectedAlternative.id,
                      t.alternatives.map((a) => [a.id, a.position]).toList(),
                      t.selectedParts
                          .map(
                            (p) => [
                              p.kind.name,
                              p.text,
                              p.generationAttemptId,
                              p.metadata,
                            ],
                          )
                          .toList(),
                    ],
                  )
                  .toList(),
            ]);
          }
          for (final alt in ['answer', 'answer-2']) {
            lines.add(
              (await repo.listAttempts(alt))
                  .map(
                    (a) => [
                      a.id,
                      a.status.name,
                      a.type.name,
                      a.providerReference,
                      a.modelReference,
                      a.position,
                      a.hasPartialContent,
                      a.failureReason,
                      a.cancelReason,
                    ],
                  )
                  .toList(),
            );
            lines.add(
              (await repo.listContentParts(alt))
                  .map(
                    (p) => [
                      p.id,
                      p.position,
                      p.kind.name,
                      p.text,
                      p.generationAttemptId,
                      p.metadata,
                    ],
                  )
                  .toList(),
            );
          }
          return jsonEncode(lines);
        }

        final before = await signature(source);
        final codec = BackupArchiveCodec(
          applicationSupportDirectory: directory,
        );
        final archive = File(p.join(directory.path, 'phase10.ibukibackup'));
        await codec.write(
          snapshot: await SQLiteBackupSnapshotStore(sourceDb).buildSnapshot(),
          destination: archive,
          appVersion: 'test',
          schemaVersion: SqliteSchema.version,
        );
        final decoded = await codec.read(
          source: archive,
          staging: Directory(p.join(directory.path, 'stage')),
        );
        final targetDb = db('target.db');
        await SQLiteBackupSnapshotStore(targetDb).restore(
          decoded.snapshot,
          mode: BackupRestoreMode.fresh,
          restoredAssets: const {},
        );
        expect(await signature(SQLiteTavernRepository(targetDb)), before);
        await targetDb.close();
        final reopened = db('target.db');
        expect(await signature(SQLiteTavernRepository(reopened)), before);
        await reopened.close();
      } finally {
        await sourceDb.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
