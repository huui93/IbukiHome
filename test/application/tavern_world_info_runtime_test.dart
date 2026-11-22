import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/tavern/prompt/prompt_compiler.dart';
import 'package:ibukihome/application/tavern/prompt/prompt_models.dart';
import 'package:ibukihome/application/tavern/world_info/world_info_models.dart';
import 'package:ibukihome/application/tavern/world_info/world_info_native_adapter.dart';
import 'package:ibukihome/application/tavern/world_info/world_info_runtime.dart';
import 'package:ibukihome/application/tavern/world_info/world_info_scan_context.dart';
import 'package:ibukihome/data/memory/in_memory_tavern_repository.dart';
import 'package:ibukihome/domain/tavern/tavern_models.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_models.dart';

final _now = DateTime.utc(2026, 10, 14);

class _FixedRandom implements WorldInfoRandomSource {
  const _FixedRandom(this.value);
  final double value;
  @override
  double sample(String key) => value;
}

class _Counter implements PromptTokenCounter {
  const _Counter();
  @override
  int countText(String text) => text.length;
  @override
  int get segmentOverhead => 0;
}

WorldInfoEntry _entry(
  String id, {
  String book = 'book',
  String? title,
  String content = 'lore',
  List<String> keys = const [],
  List<String> secondary = const [],
  WorldInfoSelectiveLogic logic = WorldInfoSelectiveLogic.andAny,
  bool constant = false,
  bool enabled = true,
  bool bookEnabled = true,
  bool manualOnly = false,
  int probability = 100,
  int priority = 0,
  int order = 0,
  List<String> groups = const [],
  int groupWeight = 100,
  bool prioritizeGroup = false,
  bool scoreGroup = false,
  bool excludeRecursion = false,
  bool preventRecursion = false,
  bool recursionOnly = false,
  int sticky = 0,
  int cooldown = 0,
  int delay = 0,
  int? scanDepth,
  bool caseSensitive = false,
  bool wholeWords = true,
  Set<String> worldIds = const {},
  Set<String> characterIds = const {},
  Set<String> personaIds = const {},
  Set<String> characterTags = const {},
  bool excludeCharacterFilter = false,
  Set<WorldInfoAdditionalScanSource> additionalScanSources = const {},
  Set<WorldInfoGenerationType> types = const {},
  PromptPlacement placement = const PromptPlacement(
    PromptPlacementKind.beforeHistory,
  ),
}) => WorldInfoEntry(
  bookId: book,
  entryId: id,
  title: title ?? id,
  content: content,
  primaryKeys: keys,
  secondaryKeys: secondary,
  selectiveLogic: logic,
  constant: constant,
  enabled: enabled,
  bookEnabled: bookEnabled,
  manualOnly: manualOnly,
  probabilityPercent: probability,
  priority: priority,
  order: order,
  groups: groups,
  groupWeight: groupWeight,
  prioritizeGroup: prioritizeGroup,
  scoreGroup: scoreGroup,
  excludeRecursion: excludeRecursion,
  preventRecursion: preventRecursion,
  recursionOnly: recursionOnly,
  stickyMessages: sticky,
  cooldownMessages: cooldown,
  delayMessages: delay,
  scanDepth: scanDepth,
  caseSensitive: caseSensitive,
  wholeWords: wholeWords,
  worldIds: worldIds,
  characterIds: characterIds,
  personaIds: personaIds,
  characterTags: characterTags,
  excludeCharacterFilter: excludeCharacterFilter,
  additionalScanSources: additionalScanSources,
  generationTypes: types,
  placement: placement,
);

WorldInfoActivationContext _context(
  String text, {
  String session = 's',
  String line = 'main',
  WorldInfoGenerationType type = WorldInfoGenerationType.normal,
  int count = 1,
  String? marker,
  String? world,
  Set<String> characters = const {},
  Set<String> characterTags = const {},
  Map<WorldInfoAdditionalScanSource, String> additionalScanText = const {},
  String? persona,
}) => WorldInfoActivationContext(
  sessionId: session,
  storyLineId: line,
  generationType: type,
  messages: [
    for (var i = 0; i < count - 1; i++)
      WorldInfoScanMessage(turnId: 'old-$i', text: 'unrelated'),
    WorldInfoScanMessage(turnId: 'current', text: text),
  ],
  historyMarker: marker ?? '$line:$count:$text',
  worldId: world,
  characterIds: characters,
  characterTags: characterTags,
  additionalScanText: additionalScanText,
  personaId: persona,
);

WorldInfoRuntimeState _state([String line = 'main', String session = 's']) =>
    WorldInfoRuntimeState(sessionId: session, storyLineId: line);

WorldInfoActivationPlan _evaluate(
  List<WorldInfoEntry> entries,
  WorldInfoActivationContext context, {
  WorldInfoRuntimeState? state,
  double sample = 0.0,
  WorldInfoSettings settings = const WorldInfoSettings(),
}) => const WorldInfoRuntime().evaluate(
  entries: entries,
  context: context,
  state: state ?? _state(context.storyLineId, context.sessionId),
  random: _FixedRandom(sample),
  settings: settings,
);

WorldInfoActivationDecision _decision(
  WorldInfoActivationPlan plan,
  String id, [
  String book = 'book',
]) => plan.trace.decisions.singleWhere(
  (decision) => decision.identity == (book, id),
);

Future<InMemoryTavernRepository> _projectionFixture() async {
  final repo = InMemoryTavernRepository();
  await repo.createSession(
    TavernSession(id: 's', title: 'Story', createdAt: _now, updatedAt: _now),
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
      id: 'character',
      sessionId: 's',
      kind: TavernParticipantKind.character,
      entityId: 'card',
      position: 1,
    ),
  );
  Future<void> turn(
    String id,
    String line,
    int position,
    TavernTurnRole role,
    String text,
    String participant,
  ) async {
    await repo.appendTurn(
      TavernTurn(
        id: id,
        sessionId: 's',
        storyLineId: line,
        position: position,
        role: role,
        participantId: participant,
        createdAt: _now,
        updatedAt: _now,
      ),
      TavernAlternative(
        id: '$id-a',
        turnId: id,
        position: 0,
        origin: TavernAlternativeOrigin.manual,
        createdAt: _now,
      ),
    );
    await repo.appendContentPart(
      TavernContentPart(
        id: '$id-text',
        alternativeId: '$id-a',
        position: 0,
        kind: TavernContentKind.text,
        text: text,
        createdAt: _now,
      ),
    );
  }

  await turn('u1', 'main', 0, TavernTurnRole.player, '北塔', 'player');
  await turn('a1', 'main', 1, TavernTurnRole.character, '旧答案', 'character');
  await repo.addAlternative(
    TavernAlternative(
      id: 'a1-b',
      turnId: 'a1',
      position: 1,
      origin: TavernAlternativeOrigin.generated,
      createdAt: _now,
    ),
  );
  await repo.appendContentPart(
    TavernContentPart(
      id: 'a1-b-text',
      alternativeId: 'a1-b',
      position: 0,
      kind: TavernContentKind.text,
      text: '南门',
      createdAt: _now,
    ),
  );
  await repo.createStoryLine(
    TavernStoryLine(
      id: 'child',
      sessionId: 's',
      name: 'Child',
      position: 1,
      parentId: 'main',
      originTurnId: 'a1',
      originAlternativeId: 'a1-a',
      createdAt: _now,
    ),
  );
  await repo.selectAlternative('a1', 'a1-b');
  await turn('u2', 'main', 2, TavernTurnRole.player, '继续', 'player');
  await turn('a2', 'main', 3, TavernTurnRole.character, '西桥', 'character');
  await turn('u3', 'main', 4, TavernTurnRole.player, '前进', 'player');
  return repo;
}

void main() {
  test(
    'primary, multilingual, case and whole-word matching are deterministic',
    () {
      final entries = [
        _entry('latin', keys: ['king']),
        _entry('cjk', keys: ['北塔']),
        _entry('case', keys: ['Rose'], caseSensitive: true),
        _entry('phrase', keys: ['red moon']),
      ];
      final result = _evaluate(
        entries,
        _context('The KING visits 北塔; a red  moon rises.'),
      );
      expect(result.activated, [
        ('book', 'cjk'),
        ('book', 'latin'),
        ('book', 'phrase'),
      ]);
      expect(
        _decision(result, 'case').reason,
        WorldInfoActivationReason.primaryNotMatched,
      );
      expect(
        _evaluate([
          _entry('king', keys: ['king']),
        ], _context('kingdom')).activated,
        isEmpty,
      );
      expect(
        _evaluate([
          _entry('jp', keys: ['東京']),
        ], _context('夜の東京都')).activated,
        [('book', 'jp')],
      );
    },
  );

  test('all four selective conditions preserve primary requirement', () {
    final entries = [
      for (final logic in WorldInfoSelectiveLogic.values)
        _entry(
          logic.name,
          keys: ['cake'],
          secondary: ['tea', 'dragon'],
          logic: logic,
        ),
    ];
    final one = _evaluate(entries, _context('cake and tea'));
    expect(one.activated.toSet(), {('book', 'andAny'), ('book', 'notAll')});
    expect(
      _decision(one, 'andAll').reason,
      WorldInfoActivationReason.secondaryNotMatched,
    );
    expect(_evaluate(entries, _context('cake tea dragon')).activated.toSet(), {
      ('book', 'andAny'),
      ('book', 'andAll'),
    });
    expect(_evaluate(entries, _context('cake')).activated.toSet(), {
      ('book', 'notAny'),
      ('book', 'notAll'),
    });
    expect(_evaluate(entries, _context('tea dragon')).activated, isEmpty);
  });

  test(
    'additional scan sources are explicit and character tags filter scope',
    () {
      final entries = [
        _entry(
          'persona',
          keys: ['moon traveller'],
          additionalScanSources: {
            WorldInfoAdditionalScanSource.personaDescription,
          },
        ),
        _entry('not-opted', keys: ['moon traveller']),
        _entry('tag', constant: true, characterTags: {'mage'}),
        _entry(
          'excluded',
          constant: true,
          characterTags: {'mage'},
          excludeCharacterFilter: true,
        ),
      ];
      final context = _context(
        'ordinary dialogue',
        characterTags: {'mage'},
        additionalScanText: {
          WorldInfoAdditionalScanSource.personaDescription: 'moon traveller',
        },
      );
      final result = _evaluate(entries, context);
      expect(result.activated.toSet(), {('book', 'persona'), ('book', 'tag')});
      expect(
        _decision(result, 'not-opted').reason,
        WorldInfoActivationReason.primaryNotMatched,
      );
      expect(
        _decision(result, 'excluded').reason,
        WorldInfoActivationReason.scopeMismatch,
      );
    },
  );

  test(
    'constant, disabled, manual, scope, delay and generation filter trace',
    () {
      final result = _evaluate([
        _entry('constant', constant: true),
        _entry('disabled', constant: true, enabled: false),
        _entry('book-off', constant: true, bookEnabled: false),
        _entry('manual', keys: ['hello'], manualOnly: true),
        _entry('scope', constant: true, worldIds: {'other'}),
        _entry('delay', constant: true, delay: 3),
        _entry(
          'regen',
          constant: true,
          types: {WorldInfoGenerationType.regenerate},
        ),
      ], _context('hello', world: 'world'));
      expect(result.activated, [('book', 'constant')]);
      expect(
        _decision(result, 'disabled').reason,
        WorldInfoActivationReason.disabled,
      );
      expect(
        _decision(result, 'book-off').reason,
        WorldInfoActivationReason.disabled,
      );
      expect(
        _decision(result, 'manual').reason,
        WorldInfoActivationReason.manualOnly,
      );
      expect(
        _decision(result, 'scope').reason,
        WorldInfoActivationReason.scopeMismatch,
      );
      expect(_decision(result, 'delay').delayRemaining, 2);
      expect(
        _decision(result, 'regen').reason,
        WorldInfoActivationReason.generationMismatch,
      );
      expect(result.trace.checked, 7);
    },
  );

  test('probability rolls after group and is reproducible', () {
    final entries = [
      _entry(
        'a',
        keys: ['cake'],
        groups: ['one'],
        prioritizeGroup: true,
        order: 10,
        probability: 50,
      ),
      _entry('b', keys: ['cake'], groups: ['one'], order: 1),
    ];
    final failed = _evaluate(entries, _context('cake'), sample: .8);
    expect(failed.activated, isEmpty);
    expect(
      _decision(failed, 'a').reason,
      WorldInfoActivationReason.probabilityFailed,
    );
    expect(_decision(failed, 'a').probabilitySample, .8);
    expect(_decision(failed, 'b').reason, WorldInfoActivationReason.groupLost);
    expect(_evaluate(entries, _context('cake'), sample: .2).activated, [
      ('book', 'a'),
    ]);
  });

  test('group scoring, weighted winner and constant competition', () {
    final scored = _evaluate([
      _entry('a', keys: ['song'], groups: ['songs'], scoreGroup: true),
      _entry('b', keys: ['song', 'ghost'], groups: ['songs'], scoreGroup: true),
    ], _context('song ghost'));
    expect(scored.activated, [('book', 'b')]);
    final weighted = [
      _entry('a', constant: true, groups: ['g'], groupWeight: 1),
      _entry('b', keys: ['cake'], groups: ['g'], groupWeight: 9),
    ];
    expect(_evaluate(weighted, _context('cake'), sample: .05).activated, [
      ('book', 'a'),
    ]);
    expect(_evaluate(weighted, _context('cake'), sample: .9).activated, [
      ('book', 'b'),
    ]);
  });

  test('recursive chain, guard, prevent and exclude recursion', () {
    final entries = [
      _entry('a', keys: ['cake'], content: 'north tower'),
      _entry('b', keys: ['north tower'], content: 'moon gate'),
      _entry('c', keys: ['moon gate'], content: 'cake'),
      _entry('excluded', keys: ['north tower'], excludeRecursion: true),
      _entry(
        'stopped',
        keys: ['cake'],
        content: 'secret',
        preventRecursion: true,
      ),
      _entry('secret', keys: ['secret']),
    ];
    final result = _evaluate(
      entries,
      _context('cake'),
      settings: const WorldInfoSettings(maxRecursionPasses: 4),
    );
    expect(result.activated.toSet(), {
      ('book', 'a'),
      ('book', 'b'),
      ('book', 'c'),
      ('book', 'stopped'),
    });
    expect(_decision(result, 'b').pass, 1);
    expect(_decision(result, 'b').recursionSource, ('book', 'a'));
    expect(_decision(result, 'c').pass, 2);
    expect(
      _decision(result, 'excluded').reason,
      WorldInfoActivationReason.recursionExcluded,
    );
    expect(_decision(result, 'secret').active, isFalse);
    expect(result.trace.recursionGuarded, contains(('book', 'a')));
  });

  test(
    'sticky survives probability, then cooldown; failed plan is dry run',
    () {
      final entry = _entry(
        'timed',
        keys: ['bell'],
        probability: 50,
        sticky: 2,
        cooldown: 2,
      );
      final first = _evaluate([entry], _context('bell', count: 1), sample: .1);
      expect(first.activated, [('book', 'timed')]);
      final preview = _evaluate(
        [entry],
        _context('nothing', count: 2),
        state: first.nextState,
        sample: .9,
      );
      expect(
        _decision(preview, 'timed').reason,
        WorldInfoActivationReason.activatedSticky,
      );
      expect(_decision(preview, 'timed').probabilitySample, isNull);
      // A failed/cancelled generation simply does not adopt preview.nextState.
      final same = _evaluate(
        [entry],
        _context('nothing', count: 2),
        state: first.nextState,
        sample: .9,
      );
      expect(same.activated, preview.activated);
      expect(
        _evaluate(
          [entry],
          _context('nothing', count: 3),
          state: first.nextState,
        ).activated,
        [('book', 'timed')],
      );
      final cooling = _evaluate(
        [entry],
        _context('bell', count: 4),
        state: first.nextState,
      );
      expect(
        _decision(cooling, 'timed').reason,
        WorldInfoActivationReason.cooldown,
      );
      expect(
        _evaluate(
          [entry],
          _context('bell', count: 6),
          state: first.nextState,
          sample: .1,
        ).activated,
        [('book', 'timed')],
      );
    },
  );

  test('state isolates story lines, resets on edit, disable and deletion', () {
    final entry = _entry('a', keys: ['cake'], sticky: 3);
    final first = _evaluate([entry], _context('cake', count: 1));
    final other = _evaluate(
      [entry],
      _context('nothing', line: 'other', count: 2),
      state: _state('other'),
    );
    expect(other.activated, isEmpty);
    expect(
      () => _evaluate(
        [entry],
        _context('nothing', line: 'other', count: 2),
        state: first.nextState,
      ),
      throwsArgumentError,
    );
    final changed = _entry('a', keys: ['cake'], content: 'edited', sticky: 3);
    expect(
      _evaluate(
        [changed],
        _context('nothing', count: 2),
        state: first.nextState,
      ).activated,
      isEmpty,
    );
    final disabled = _evaluate(
      [_entry('a', enabled: false, sticky: 3)],
      _context('nothing', count: 2),
      state: first.nextState,
    );
    expect(disabled.nextState.timed, isEmpty);
    expect(
      _evaluate(
        [],
        _context('nothing', count: 2),
        state: first.nextState,
      ).nextState.timed,
      isEmpty,
    );
  });

  test('multiple books have composite identities and scope isolation', () {
    final result = _evaluate([
      _entry('12', book: 'world', keys: ['cake'], worldIds: {'w'}),
      _entry('12', book: 'character', keys: ['cake'], characterIds: {'c'}),
      _entry('12', book: 'persona', keys: ['cake'], personaIds: {'p'}),
      _entry('12', book: 'wrong', keys: ['cake'], personaIds: {'other'}),
    ], _context('cake', world: 'w', characters: {'c'}, persona: 'p'));
    expect(result.activated.toSet(), {
      ('world', '12'),
      ('character', '12'),
      ('persona', '12'),
    });
    expect(result.promptSources.map((s) => s.id).toSet().length, 3);
    expect(
      result.promptSources
          .singleWhere((s) => s.origin.parentId == 'world')
          .origin
          .label,
      '12',
    );
    expect(
      _decision(result, '12', 'wrong').reason,
      WorldInfoActivationReason.scopeMismatch,
    );
  });

  test('activation and compilation traces remain separate under budget', () {
    final entries = [
      for (var i = 0; i < 8; i++)
        _entry('lore-$i', constant: true, content: 'xx', priority: 8 - i),
    ];
    final activation = _evaluate(entries, _context('hello'));
    expect(activation.trace.active, 8);
    final compiled = const PromptCompiler(_Counter()).compile(
      PromptCompileInput(
        sources: activation.promptSources,
        constraints: const PromptCompileConstraints(
          maxContextTokens: 10,
          reservedOutputTokens: 0,
        ),
      ),
    );
    expect(compiled.segments, hasLength(5));
    expect(
      compiled.trace.decisions.where(
        (d) => d.outcome == PromptCompileOutcome.dropped,
      ),
      hasLength(3),
    );
    expect(activation.trace.active, 8);
    expect(compiled.segments.first.origin.parentId, 'book');
  });

  test('depth and priority map to Compiler without a second sort', () {
    final entries = [
      _entry('low', constant: true, priority: 1, order: 1),
      _entry(
        'high',
        constant: true,
        priority: 9,
        order: 2,
        placement: const PromptPlacement(
          PromptPlacementKind.atHistoryDepth,
          depth: 1,
        ),
      ),
    ];
    final activation = _evaluate(entries, _context('x'));
    final history = PromptSource(
      id: 'h',
      type: PromptSourceType.history,
      origin: const PromptOrigin('turn', 'h'),
      role: PromptRoleIntent.userLike,
      placement: const PromptPlacement(PromptPlacementKind.history),
      atoms: const [
        PromptAtom(id: 'h:text', kind: PromptAtomKind.text, text: 'history'),
      ],
      budgetClass: PromptBudgetClass.history,
    );
    final compiled = const PromptCompiler(_Counter()).compile(
      PromptCompileInput(
        sources: [...activation.promptSources, history],
        constraints: const PromptCompileConstraints(
          maxContextTokens: 100,
          reservedOutputTokens: 0,
        ),
      ),
    );
    expect(compiled.segments.map((s) => s.sourceId), [
      entries[0].sourceId,
      entries[1].sourceId,
      'h',
    ]);
    expect(
      activation.promptSources
          .singleWhere((s) => s.id == entries[1].sourceId)
          .placement
          .depth,
      1,
    );
  });

  test(
    'Foundation projection excludes unselected, old regen target and failures',
    () async {
      final repo = await _projectionFixture();
      final builder = const WorldInfoScanContextBuilder();
      final main = await repo.loadTranscript('s', storyLineId: 'main');
      final normal = builder.fromProjection(
        main,
        mode: PromptCompileMode.normal,
        targetTurnId: 'u3',
      );
      expect(normal.messages.map((m) => m.text), [
        '北塔',
        '南门',
        '继续',
        '西桥',
        '前进',
      ]);
      final regen = builder.fromProjection(
        main,
        mode: PromptCompileMode.regenerate,
        targetTurnId: 'a2',
      );
      expect(regen.messages.map((m) => m.text), ['北塔', '南门', '继续']);
      final continuation = builder.fromProjection(
        main,
        mode: PromptCompileMode.continueTurn,
        targetTurnId: 'a2',
      );
      expect(continuation.messages.last.text, '西桥');
      final child = builder.fromProjection(
        await repo.loadTranscript('s', storyLineId: 'child'),
        mode: PromptCompileMode.continueTurn,
        targetTurnId: 'a1',
      );
      expect(child.messages.last.text, '旧答案');
      expect(
        _evaluate([
          _entry('old', keys: ['旧答案']),
        ], child).activated,
        [('book', 'old')],
      );
      expect(
        _evaluate([
          _entry('old', keys: ['旧答案']),
        ], normal).activated,
        isEmpty,
      );
    },
  );

  test(
    'failed partial and reasoning do not scan; tool text is opt-in',
    () async {
      final repo = await _projectionFixture();
      await repo.recordAttempt(
        TavernGenerationAttempt(
          id: 'failed',
          sessionId: 's',
          storyLineId: 'main',
          turnId: 'a2',
          alternativeId: 'a2-a',
          position: 0,
          status: TavernGenerationStatus.queued,
          type: TavernGenerationType.continueTurn,
          createdAt: _now,
        ),
      );
      await repo.appendContentPart(
        TavernContentPart(
          id: 'failed-text',
          alternativeId: 'a2-a',
          position: 1,
          kind: TavernContentKind.text,
          text: 'secret lighthouse',
          generationAttemptId: 'failed',
          createdAt: _now,
        ),
      );
      await repo.updateAttempt(
        'failed',
        TavernGenerationStatus.failed,
        hasPartialContent: true,
      );
      await repo.appendContentPart(
        TavernContentPart(
          id: 'reasoning',
          alternativeId: 'a2-a',
          position: 2,
          kind: TavernContentKind.reasoning,
          text: 'hidden fortress',
          createdAt: _now,
        ),
      );
      await repo.appendContentPart(
        TavernContentPart(
          id: 'tool',
          alternativeId: 'a2-a',
          position: 3,
          kind: TavernContentKind.toolResult,
          toolCallId: 'call',
          result: {'text': 'visible archive'},
          createdAt: _now,
        ),
      );
      final transcript = await repo.loadTranscript('s', storyLineId: 'main');
      final builder = const WorldInfoScanContextBuilder();
      final normal = builder.fromProjection(
        transcript,
        mode: PromptCompileMode.normal,
        targetTurnId: 'u3',
      );
      final opted = builder.fromProjection(
        transcript,
        mode: PromptCompileMode.normal,
        targetTurnId: 'u3',
        scanToolResultText: true,
      );
      final entries = [
        _entry('failed', keys: ['secret lighthouse']),
        _entry('reasoning', keys: ['hidden fortress']),
        _entry('tool', keys: ['visible archive']),
      ];
      expect(_evaluate(entries, normal).activated, isEmpty);
      expect(_evaluate(entries, opted).activated, [('book', 'tool')]);
    },
  );

  test('forked timed state inherits only branch-point activations', () {
    final early = _entry('early', keys: ['cake'], sticky: 5);
    final late = _entry('late', keys: ['door'], sticky: 5);
    final first = _evaluate([early, late], _context('cake', count: 1));
    final second = _evaluate(
      [early, late],
      _context('door', count: 3),
      state: first.nextState,
    );
    final childState = second.nextState.forkAt(
      childStoryLineId: 'child',
      branchPointMessageCount: 1,
      childHistoryMarker: 'child:1:cake',
    );
    expect(childState.timed.keys, [('book', 'early')]);
    final child = _evaluate(
      [early, late],
      _context('nothing', line: 'child', count: 2),
      state: childState,
    );
    expect(child.activated, [('book', 'early')]);
    expect(_decision(child, 'late').active, isFalse);
  });

  test('group competition follows recursive match and sticky dominates', () {
    final root = _entry('root', keys: ['cake'], content: 'north gate');
    final b = _entry(
      'b',
      keys: ['north gate'],
      groups: ['choice'],
      prioritizeGroup: true,
      order: 5,
      sticky: 2,
    );
    final c = _entry('c', keys: ['north gate'], groups: ['choice'], order: 1);
    final first = _evaluate([root, b, c], _context('cake'));
    expect(first.activated.toSet(), {('book', 'root'), ('book', 'b')});
    expect(_decision(first, 'c').reason, WorldInfoActivationReason.groupLost);
    final next = _evaluate(
      [root, b, c],
      _context('north gate', count: 2),
      state: first.nextState,
    );
    expect(
      _decision(next, 'b').reason,
      WorldInfoActivationReason.activatedSticky,
    );
    expect(_decision(next, 'c').groupWinner, ('book', 'b'));
  });

  test('native LoreEntry adapter maps safe fields, not preserved scripts', () {
    final lore = LoreEntry(
      entity: EntityMetadata(
        id: 'entry',
        createdAt: _now,
        updatedAt: _now,
        revision: 1,
      ),
      worldBookId: 'native-book',
      title: 'North tower',
      content: 'Tower content',
      keywords: const ['north'],
      secondaryKeywords: const ['gate'],
      priority: 42,
      probability: .5,
      metadata: const {
        'hasPreservedAdvancedRules': true,
        'script': 'do-not-run()',
      },
    );
    final mapped = const WorldInfoNativeAdapter().fromLoreEntry(
      lore,
      bookEnabled: true,
      referencePriority: 3,
      worldIds: {'world-a'},
    );
    expect(mapped.identity, ('native-book', 'entry'));
    expect(mapped.primaryKeys, ['north']);
    expect(mapped.secondaryKeys, ['gate']);
    expect(mapped.probabilityPercent, 50);
    expect(mapped.priority, 3);
    expect(mapped.order, 42);
    expect(mapped.worldIds, {'world-a'});
    expect(
      _evaluate(
        [mapped],
        _context('north gate', world: 'world-a'),
        sample: .1,
      ).activated,
      [('native-book', 'entry')],
    );
    expect(mapped.content, isNot(contains('do-not-run')));
  });

  test('15-entry multi-pass fixture keeps trace and state coherent', () {
    final entries = [
      _entry('constant-a', constant: true, content: 'north tower'),
      _entry('constant-b', constant: true, content: 'background'),
      _entry('cake', keys: ['cake'], content: 'moon gate', sticky: 2),
      _entry('chaldea', keys: ['Chaldea']),
      _entry(
        'primary-secondary',
        keys: ['cake'],
        secondary: ['Chaldea'],
        logic: WorldInfoSelectiveLogic.andAny,
      ),
      _entry('secondary-miss', keys: ['cake'], secondary: ['dragon']),
      _entry(
        'group-a',
        keys: ['cake'],
        groups: ['one'],
        prioritizeGroup: true,
        order: 5,
      ),
      _entry('group-b', keys: ['cake'], groups: ['one'], order: 1),
      _entry('recursive-tower', keys: ['north tower'], content: 'old city'),
      _entry('recursive-city', keys: ['old city']),
      _entry('probability', keys: ['cake'], probability: 0),
      _entry('cooldown', keys: ['cake'], cooldown: 2),
      _entry('delayed', constant: true, delay: 3),
      _entry('disabled', constant: true, enabled: false),
      _entry('wrong-scope', constant: true, personaIds: {'other'}),
    ];
    final first = _evaluate(
      entries,
      _context('cake Chaldea', count: 1, persona: 'player'),
      sample: .4,
      settings: const WorldInfoSettings(maxRecursionPasses: 4),
    );
    expect(first.trace.checked, 15);
    expect(
      first.activated,
      containsAll([
        ('book', 'cake'),
        ('book', 'recursive-tower'),
        ('book', 'recursive-city'),
        ('book', 'group-a'),
      ]),
    );
    expect(
      _decision(first, 'probability').reason,
      WorldInfoActivationReason.probabilityFailed,
    );
    expect(
      _decision(first, 'secondary-miss').reason,
      WorldInfoActivationReason.secondaryNotMatched,
    );
    expect(
      _decision(first, 'group-b').reason,
      WorldInfoActivationReason.groupLost,
    );
    final second = _evaluate(
      entries,
      _context('nothing', count: 2),
      state: first.nextState,
      sample: .9,
    );
    expect(
      _decision(second, 'cake').reason,
      WorldInfoActivationReason.activatedSticky,
    );
    expect(
      _decision(second, 'cooldown').reason,
      WorldInfoActivationReason.cooldown,
    );
    expect(
      _decision(second, 'delayed').reason,
      WorldInfoActivationReason.delayPending,
    );
    final third = _evaluate(
      entries,
      _context('nothing', count: 3),
      state: second.nextState,
    );
    expect(_decision(third, 'delayed').active, isTrue);
    expect(
      third.promptSources.map((s) => s.id).toSet().length,
      third.promptSources.length,
    );
  });

  test('scan depth 0, 1 and per-entry override are distinct', () {
    final context = WorldInfoActivationContext(
      sessionId: 's',
      storyLineId: 'main',
      generationType: WorldInfoGenerationType.normal,
      messages: const [
        WorldInfoScanMessage(turnId: 'old', text: 'ancient gate'),
        WorldInfoScanMessage(turnId: 'new', text: 'cake'),
      ],
      historyMarker: 'two',
    );
    final entries = [
      _entry('old', keys: ['ancient gate']),
      _entry('override', keys: ['ancient gate'], scanDepth: 2),
      _entry('new', keys: ['cake']),
    ];
    expect(
      _evaluate(
        entries,
        context,
        settings: const WorldInfoSettings(scanDepth: 1),
      ).activated.toSet(),
      {('book', 'override'), ('book', 'new')},
    );
    expect(
      _evaluate(
        entries,
        context,
        settings: const WorldInfoSettings(scanDepth: 0),
      ).activated,
      [('book', 'override')],
    );
  });

  test(
    'recursion-only activates later, cooldown blocks recursive reactivation',
    () {
      final root = _entry('root', keys: ['cake'], content: 'bell');
      final delayed = _entry(
        'recursive-only',
        keys: ['bell'],
        recursionOnly: true,
      );
      final cool = _entry('cool', keys: ['bell'], cooldown: 2);
      final first = _evaluate([
        root,
        delayed,
        cool,
      ], _context('cake bell', count: 1));
      expect(_decision(first, 'recursive-only').pass, 1);
      final second = _evaluate(
        [root, delayed, cool],
        _context('cake', count: 2),
        state: first.nextState,
      );
      expect(
        _decision(second, 'cool').reason,
        WorldInfoActivationReason.cooldown,
      );
      expect(_decision(second, 'recursive-only').active, isTrue);
    },
  );

  test('title edit resets sticky state', () {
    final original = _entry('a', keys: ['cake'], sticky: 3);
    final first = _evaluate([original], _context('cake', count: 1));
    final renamed = _entry('a', title: 'Renamed', keys: ['cake'], sticky: 3);
    expect(
      _evaluate(
        [renamed],
        _context('nothing', count: 2),
        state: first.nextState,
      ).activated,
      isEmpty,
    );
  });

  test('entry permutations and keyed RNG yield identical decisions', () {
    final entries = [
      _entry('z', keys: ['cake'], groups: ['g'], groupWeight: 2),
      _entry('a', keys: ['cake'], groups: ['g'], groupWeight: 8),
      _entry('constant', constant: true, probability: 50),
    ];
    final context = _context('cake');
    final forward = _evaluate(entries, context, sample: .6);
    final reverse = _evaluate(entries.reversed.toList(), context, sample: .6);
    expect(forward.activated, reverse.activated);
    expect(
      forward.trace.decisions.map(
        (d) =>
            '${d.identity}:${d.reason}:${d.groupSample}:${d.probabilitySample}',
      ),
      reverse.trace.decisions.map(
        (d) =>
            '${d.identity}:${d.reason}:${d.groupSample}:${d.probabilitySample}',
      ),
    );
    expect(_decision(forward, 'z').groupWeight, 2);
  });

  test('invalid random sample fails without mutating input state', () {
    final state = _state();
    expect(
      () => _evaluate(
        [_entry('chance', constant: true, probability: 50)],
        _context('x'),
        state: state,
        sample: 1,
      ),
      throwsStateError,
    );
    expect(state.timed, isEmpty);
    expect(state.observedMessageCount, 0);
  });

  test('100, 500, 1000 entries scan bounded depth with complete trace', () {
    for (final count in [100, 500, 1000]) {
      final entries = [
        for (var i = 0; i < count; i++)
          _entry('e$i', keys: ['token-$i'], content: 'lore-$i'),
      ];
      final messages = [
        for (var i = 0; i < 100; i++)
          WorldInfoScanMessage(
            turnId: 't$i',
            text: i == 99 ? 'token-7' : 'none',
          ),
      ];
      final context = WorldInfoActivationContext(
        sessionId: 's',
        storyLineId: 'main',
        generationType: WorldInfoGenerationType.normal,
        messages: messages,
        historyMarker: '100',
      );
      final watch = Stopwatch()..start();
      final plan = _evaluate(
        entries,
        context,
        settings: const WorldInfoSettings(scanDepth: 10),
      );
      watch.stop();
      expect(plan.trace.checked, count);
      expect(plan.activated, [('book', 'e7')]);
      expect(watch.elapsedMilliseconds, lessThan(2000));
      debugPrint(
        'World Info $count entries / 100 messages: '
        '${watch.elapsedMicroseconds}us',
      );
    }
  });
}
