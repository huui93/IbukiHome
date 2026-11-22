import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/tavern/prompt/prompt_compiler.dart';
import 'package:ibukihome/application/tavern/prompt/prompt_models.dart';
import 'package:ibukihome/application/tavern/world_info/world_info_attempt_ledger.dart';
import 'package:ibukihome/application/tavern/world_info/world_info_models.dart';
import 'package:ibukihome/application/tavern/world_info/world_info_runtime.dart';
import 'package:ibukihome/domain/tavern/tavern_models.dart';

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
  String content = 'lore',
  List<String> keys = const [],
  List<String> secondary = const [],
  WorldInfoSelectiveLogic logic = WorldInfoSelectiveLogic.andAny,
  bool constant = false,
  bool enabled = true,
  bool bookEnabled = true,
  int probability = 100,
  List<String> groups = const [],
  int sticky = 0,
  int cooldown = 0,
  int delay = 0,
  bool recursionOnly = false,
  bool preventRecursion = false,
  Set<String> worldIds = const {},
}) => WorldInfoEntry(
  bookId: book,
  entryId: id,
  title: id,
  content: content,
  primaryKeys: keys,
  secondaryKeys: secondary,
  selectiveLogic: logic,
  constant: constant,
  enabled: enabled,
  bookEnabled: bookEnabled,
  probabilityPercent: probability,
  groups: groups,
  stickyMessages: sticky,
  cooldownMessages: cooldown,
  delayMessages: delay,
  recursionOnly: recursionOnly,
  preventRecursion: preventRecursion,
  worldIds: worldIds,
);

WorldInfoActivationContext _context(
  String text, {
  String session = 'session',
  String line = 'main',
  int count = 1,
  String? world,
}) => WorldInfoActivationContext(
  sessionId: session,
  storyLineId: line,
  generationType: WorldInfoGenerationType.normal,
  messages: [
    for (var i = 0; i < count - 1; i++)
      WorldInfoScanMessage(turnId: 'old-$i', text: 'old'),
    WorldInfoScanMessage(turnId: 'new', text: text),
  ],
  historyMarker: '$line:$count:$text',
  worldId: world,
);

TavernGenerationAttempt _attempt(
  String id, {
  String session = 'session',
  String line = 'main',
  TavernGenerationStatus status = TavernGenerationStatus.preparing,
  TavernGenerationType type = TavernGenerationType.normal,
}) => TavernGenerationAttempt(
  id: id,
  sessionId: session,
  storyLineId: line,
  turnId: 'turn-$id',
  alternativeId: 'alternative-$id',
  position: 0,
  status: status,
  type: type,
  createdAt: DateTime.utc(2026),
);

CompiledPrompt _compile(WorldInfoActivationPlan plan, {int budget = 100}) =>
    const PromptCompiler(_Counter()).compile(
      PromptCompileInput(
        sources: plan.promptSources,
        constraints: PromptCompileConstraints(
          maxContextTokens: budget,
          reservedOutputTokens: 0,
        ),
      ),
    );

WorldInfoActivationReason _reason(WorldInfoActivationPlan plan, String id) =>
    plan.trace.decisions
        .singleWhere((decision) => decision.identity.$2 == id)
        .reason;

void main() {
  test(
    'completed attempt commits once; duplicate callback cannot advance state',
    () {
      final ledger = WorldInfoAttemptLedger();
      final entry = _entry('north', keys: ['north'], sticky: 2, cooldown: 2);
      final plan = ledger.prepare(
        attempt: _attempt('one'),
        entries: [entry],
        context: _context('north'),
        random: const SeededWorldInfoRandom(1),
      );
      final completed = _attempt(
        'one',
        status: TavernGenerationStatus.completed,
      );
      expect(
        ledger.settle(attempt: completed, compiledPrompt: _compile(plan)),
        WorldInfoSettlement.committed,
      );
      final firstState = ledger.stateFor('session', 'main');
      expect(firstState.timed[('book', 'north')]?.activatedAtMessage, 1);
      expect(
        ledger.settle(attempt: completed, compiledPrompt: _compile(plan)),
        WorldInfoSettlement.duplicate,
      );
      expect(identical(ledger.stateFor('session', 'main'), firstState), isTrue);
      final next = ledger.prepare(
        attempt: _attempt('two'),
        entries: [entry],
        context: _context('unrelated', count: 2),
        random: const SeededWorldInfoRandom(1),
      );
      expect(_reason(next, 'north'), WorldInfoActivationReason.activatedSticky);
    },
  );

  test(
    'failed and cancelled attempts discard plans and retry re-evaluates',
    () {
      final ledger = WorldInfoAttemptLedger();
      final entry = _entry('north', keys: ['north'], sticky: 2);
      for (final (id, status) in [
        ('fail', TavernGenerationStatus.failed),
        ('stop', TavernGenerationStatus.cancelled),
      ]) {
        ledger.prepare(
          attempt: _attempt(id),
          entries: [entry],
          context: _context('north'),
          random: const SeededWorldInfoRandom(1),
        );
        expect(
          ledger.settle(attempt: _attempt(id, status: status)),
          WorldInfoSettlement.discarded,
        );
        expect(ledger.stateFor('session', 'main').timed, isEmpty);
      }
      final retry = ledger.prepare(
        attempt: _attempt('retry'),
        entries: [entry],
        context: _context('north'),
        random: const SeededWorldInfoRandom(1),
      );
      expect(
        _reason(retry, 'north'),
        WorldInfoActivationReason.activatedPrimary,
      );
      expect(
        ledger.settle(
          attempt: _attempt('retry', status: TavernGenerationStatus.completed),
          compiledPrompt: _compile(retry),
        ),
        WorldInfoSettlement.committed,
      );
      expect(ledger.stateFor('session', 'main').timed, hasLength(1));
    },
  );

  test('stale plan cannot replace newer timer state', () {
    final ledger = WorldInfoAttemptLedger();
    final entry = _entry('north', constant: true, sticky: 2);
    final old = ledger.prepare(
      attempt: _attempt('old'),
      entries: [entry],
      context: _context('north', count: 1),
      random: const SeededWorldInfoRandom(1),
    );
    final fresh = ledger.prepare(
      attempt: _attempt('fresh'),
      entries: [entry],
      context: _context('north', count: 2),
      random: const SeededWorldInfoRandom(1),
    );
    expect(
      ledger.settle(
        attempt: _attempt('fresh', status: TavernGenerationStatus.completed),
        compiledPrompt: _compile(fresh),
      ),
      WorldInfoSettlement.committed,
    );
    expect(
      ledger.settle(
        attempt: _attempt('old', status: TavernGenerationStatus.completed),
        compiledPrompt: _compile(old),
      ),
      WorldInfoSettlement.stale,
    );
    expect(ledger.stateFor('session', 'main').observedMessageCount, 2);
    expect(
      ledger
          .stateFor('session', 'main')
          .timed[('book', 'north')]
          ?.activatedAtMessage,
      2,
    );
  });

  test('activation dropped by compiler budget does not start timer', () {
    final ledger = WorldInfoAttemptLedger();
    final entries = [
      _entry('a', constant: true, content: 'aa', sticky: 2),
      _entry('b', constant: true, content: 'bb', sticky: 2),
    ];
    final plan = ledger.prepare(
      attempt: _attempt('drop'),
      entries: entries,
      context: _context(''),
      random: const SeededWorldInfoRandom(1),
    );
    expect(plan.trace.active, 2);
    final compiled = _compile(plan, budget: 2);
    expect(compiled.trace.decisions.map((e) => e.outcome), [
      PromptCompileOutcome.included,
      PromptCompileOutcome.dropped,
    ]);
    expect(
      ledger.settle(
        attempt: _attempt('drop', status: TavernGenerationStatus.completed),
        compiledPrompt: compiled,
      ),
      WorldInfoSettlement.committed,
    );
    expect(ledger.stateFor('session', 'main').timed.keys, [('book', 'a')]);
  });

  test('ten-entry activation and compiler traces keep distinct outcomes', () {
    final entries = [
      _entry('group-a', keys: ['north'], groups: ['g'], content: 'xx'),
      _entry('group-b', keys: ['north'], groups: ['g'], content: 'xx'),
      _entry('group-c', keys: ['north'], groups: ['g'], content: 'xx'),
      _entry('solo-a', constant: true, content: 'xx'),
      _entry('solo-b', constant: true, content: 'xx'),
      _entry('solo-c', constant: true, content: 'xx'),
      _entry('probability', constant: true, probability: 0),
      _entry('secondary', keys: ['north'], secondary: ['south']),
      _entry('disabled', constant: true, enabled: false),
      _entry('wrong-world', constant: true, worldIds: {'other'}),
    ];
    final plan = const WorldInfoRuntime().evaluate(
      entries: entries,
      context: _context('north', world: 'current'),
      state: WorldInfoRuntimeState(sessionId: 'session', storyLineId: 'main'),
      random: const SeededWorldInfoRandom(7),
    );
    expect(plan.trace.checked, 10);
    expect(plan.trace.active, 4);
    final reasons = plan.trace.decisions.map((d) => d.reason).toList();
    expect(
      reasons.where((r) => r == WorldInfoActivationReason.groupLost),
      hasLength(2),
    );
    expect(reasons, contains(WorldInfoActivationReason.probabilityFailed));
    expect(reasons, contains(WorldInfoActivationReason.secondaryNotMatched));
    expect(reasons, contains(WorldInfoActivationReason.disabled));
    expect(reasons, contains(WorldInfoActivationReason.scopeMismatch));
    final compiled = _compile(plan, budget: 4);
    expect(compiled.trace.decisions, hasLength(4));
    expect(compiled.segments, hasLength(2));
    expect(
      compiled.trace.decisions.where(
        (d) => d.outcome == PromptCompileOutcome.dropped,
      ),
      hasLength(2),
    );
    for (final source in plan.promptSources) {
      final decision = compiled.trace.decisions.singleWhere(
        (d) => d.sourceId == source.id,
      );
      expect(decision.origin.parentId, source.origin.parentId);
      expect(decision.origin.id, source.origin.id);
    }
  });

  test('delay plus failure and retry does not consume a cycle', () {
    final ledger = WorldInfoAttemptLedger();
    final entry = _entry(
      'delayed',
      constant: true,
      delay: 2,
      probability: 100,
      sticky: 2,
    );
    final first = ledger.prepare(
      attempt: _attempt('before'),
      entries: [entry],
      context: _context('north', count: 1),
      random: const SeededWorldInfoRandom(1),
    );
    expect(_reason(first, 'delayed'), WorldInfoActivationReason.delayPending);
    ledger.settle(
      attempt: _attempt('before', status: TavernGenerationStatus.failed),
    );
    expect(ledger.stateFor('session', 'main').observedMessageCount, 0);
    final retry = ledger.prepare(
      attempt: _attempt('retry-delay'),
      entries: [entry],
      context: _context('north', count: 2),
      random: const SeededWorldInfoRandom(1),
    );
    expect(
      _reason(retry, 'delayed'),
      WorldInfoActivationReason.activatedConstant,
    );
    ledger.settle(
      attempt: _attempt(
        'retry-delay',
        status: TavernGenerationStatus.completed,
      ),
      compiledPrompt: _compile(retry),
    );
    expect(
      ledger
          .stateFor('session', 'main')
          .timed[('book', 'delayed')]
          ?.activatedAtMessage,
      2,
    );
  });

  test(
    'cooldown blocks recursive reactivation; delay precedes probability',
    () {
      final root = _entry('root', constant: true, content: 'north');
      final recursive = _entry(
        'recursive',
        keys: ['north'],
        recursionOnly: true,
        cooldown: 2,
      );
      final first = const WorldInfoRuntime().evaluate(
        entries: [root, recursive],
        context: _context('unrelated'),
        state: WorldInfoRuntimeState(sessionId: 'session', storyLineId: 'main'),
        random: const SeededWorldInfoRandom(1),
      );
      expect(
        _reason(first, 'recursive'),
        WorldInfoActivationReason.activatedRecursive,
      );
      final second = const WorldInfoRuntime().evaluate(
        entries: [root, recursive],
        context: _context('unrelated', count: 2),
        state: first.nextState,
        random: const SeededWorldInfoRandom(1),
      );
      expect(_reason(second, 'recursive'), WorldInfoActivationReason.cooldown);
      final delayed = _entry(
        'delayed',
        constant: true,
        delay: 3,
        probability: 0,
      );
      final pending = const WorldInfoRuntime().evaluate(
        entries: [delayed],
        context: _context('', count: 2),
        state: WorldInfoRuntimeState(sessionId: 'session', storyLineId: 'main'),
        random: const SeededWorldInfoRandom(1),
      );
      expect(
        _reason(pending, 'delayed'),
        WorldInfoActivationReason.delayPending,
      );
      final eligible = const WorldInfoRuntime().evaluate(
        entries: [delayed],
        context: _context('', count: 3),
        state: pending.nextState,
        random: const SeededWorldInfoRandom(1),
      );
      expect(
        _reason(eligible, 'delayed'),
        WorldInfoActivationReason.probabilityFailed,
      );
    },
  );

  test('same entry ID in another book cannot reuse prior timed effect', () {
    final oldBook = _entry('shared', book: 'old', constant: true, sticky: 3);
    final first = const WorldInfoRuntime().evaluate(
      entries: [oldBook],
      context: _context(''),
      state: WorldInfoRuntimeState(sessionId: 'session', storyLineId: 'main'),
      random: const SeededWorldInfoRandom(1),
    );
    final otherBook = _entry(
      'shared',
      book: 'new',
      keys: ['absent'],
      sticky: 3,
    );
    final next = const WorldInfoRuntime().evaluate(
      entries: [otherBook],
      context: _context('unrelated', count: 2),
      state: first.nextState,
      random: const SeededWorldInfoRandom(1),
    );
    expect(next.activated, isEmpty);
    expect(next.nextState.timed, isEmpty);
  });

  test(
    'completed attempt rejects mismatched compile trace and nonterminal status',
    () {
      final ledger = WorldInfoAttemptLedger();
      final plan = ledger.prepare(
        attempt: _attempt('one'),
        entries: [_entry('a', constant: true, sticky: 1)],
        context: _context(''),
        random: const SeededWorldInfoRandom(1),
      );
      expect(() => ledger.settle(attempt: _attempt('one')), throwsStateError);
      expect(
        () => ledger.settle(
          attempt: _attempt('one', status: TavernGenerationStatus.completed),
          compiledPrompt: _compile(
            const WorldInfoActivationPlan(
              activated: [],
              promptSources: [],
              trace: WorldInfoActivationTrace([]),
              nextState: WorldInfoRuntimeState(
                sessionId: 'session',
                storyLineId: 'main',
              ),
            ),
          ),
        ),
        throwsStateError,
      );
      expect(ledger.stateFor('session', 'main').timed, isEmpty);
      expect(
        ledger.settle(
          attempt: _attempt('one', status: TavernGenerationStatus.completed),
          compiledPrompt: _compile(plan),
        ),
        WorldInfoSettlement.committed,
      );
    },
  );

  test('attempt scan mode must match and branch snapshot is copied', () {
    final ledger = WorldInfoAttemptLedger();
    expect(
      () => ledger.prepare(
        attempt: _attempt('wrong', type: TavernGenerationType.regenerate),
        entries: const [],
        context: _context(''),
        random: const SeededWorldInfoRandom(1),
      ),
      throwsStateError,
    );
    final mutable = <WorldInfoEntryId, WorldInfoTimedState>{
      ('book', 'a'): const WorldInfoTimedState(
        activatedAtMessage: 1,
        definitionSignature: 1,
      ),
    };
    ledger.seedBranch(
      WorldInfoRuntimeState(
        sessionId: 'session',
        storyLineId: 'child',
        timed: mutable,
      ),
    );
    mutable.clear();
    expect(ledger.stateFor('session', 'child').timed, hasLength(1));
  });

  test('branch state is isolated and nested branch uses origin snapshot', () {
    final ledger = WorldInfoAttemptLedger();
    final entry = _entry('north', keys: ['north'], sticky: 3);
    final main = ledger.prepare(
      attempt: _attempt('main'),
      entries: [entry],
      context: _context('north'),
      random: const SeededWorldInfoRandom(1),
    );
    ledger.settle(
      attempt: _attempt('main', status: TavernGenerationStatus.completed),
      compiledPrompt: _compile(main),
    );
    final mainAtFork = ledger.stateFor('session', 'main');
    ledger.seedBranch(
      mainAtFork.forkAt(
        childStoryLineId: 'A',
        branchPointMessageCount: 1,
        childHistoryMarker: 'A:1:north',
      ),
    );
    expect(ledger.stateFor('session', 'B').timed, isEmpty);
    final a = ledger.prepare(
      attempt: _attempt('a', line: 'A'),
      entries: [entry],
      context: _context('other', line: 'A', count: 2),
      random: const SeededWorldInfoRandom(1),
    );
    expect(_reason(a, 'north'), WorldInfoActivationReason.activatedSticky);
    ledger.seedBranch(
      ledger
          .stateFor('session', 'A')
          .forkAt(
            childStoryLineId: 'A2',
            branchPointMessageCount: 1,
            childHistoryMarker: 'A2:1:north',
          ),
    );
    expect(ledger.stateFor('session', 'A2').timed, hasLength(1));
    expect(ledger.stateFor('session', 'main').timed, hasLength(1));
  });

  test('entry edit, disable, deletion and book disable prune active timer', () {
    final base = _entry('north', constant: true, sticky: 3);
    final activated = const WorldInfoRuntime().evaluate(
      entries: [base],
      context: _context('north'),
      state: WorldInfoRuntimeState(sessionId: 'session', storyLineId: 'main'),
      random: const SeededWorldInfoRandom(1),
    );
    for (final entries in [
      [_entry('north', constant: true, sticky: 4)],
      [_entry('north', constant: true, sticky: 3, enabled: false)],
      [_entry('north', constant: true, sticky: 3, bookEnabled: false)],
      <WorldInfoEntry>[],
    ]) {
      final result = const WorldInfoRuntime().evaluate(
        entries: entries,
        context: _context('other', count: 2),
        state: activated.nextState,
        random: const SeededWorldInfoRandom(1),
      );
      if (entries.isNotEmpty &&
          entries.single.enabled &&
          entries.single.bookEnabled) {
        expect(
          result.nextState.timed[('book', 'north')]?.activatedAtMessage,
          2,
        );
        expect(
          _reason(result, 'north'),
          WorldInfoActivationReason.activatedConstant,
        );
      } else {
        expect(result.nextState.timed, isEmpty);
      }
    }
  });

  test('same inputs repeat identical group/probability/trace/source order', () {
    final entries = [
      _entry('a', keys: ['north'], groups: ['g'], probability: 50),
      _entry('b', keys: ['north'], groups: ['g']),
      _entry('c', constant: true),
    ];
    WorldInfoActivationPlan run() => const WorldInfoRuntime().evaluate(
      entries: entries,
      context: _context('north'),
      state: WorldInfoRuntimeState(sessionId: 'session', storyLineId: 'main'),
      random: const SeededWorldInfoRandom(123),
    );
    final first = run();
    final second = run();
    expect(first.activated, second.activated);
    expect(
      first.promptSources.map((e) => e.id),
      second.promptSources.map((e) => e.id),
    );
    expect(
      first.trace.decisions.map(
        (e) => (e.reason, e.groupSample, e.probabilitySample),
      ),
      second.trace.decisions.map(
        (e) => (e.reason, e.groupSample, e.probabilitySample),
      ),
    );
    expect(first.nextState.timed.keys, second.nextState.timed.keys);
  });

  test(
    'PromptOrigin label is presentation-only for compiler identity and budget',
    () {
      PromptSource source(String? label) => PromptSource(
        id: 'same',
        type: PromptSourceType.worldInfo,
        origin: PromptOrigin(
          'worldInfoEntry',
          'entry',
          parentId: 'book',
          label: label,
        ),
        role: PromptRoleIntent.context,
        placement: const PromptPlacement(PromptPlacementKind.beforeHistory),
        atoms: const [
          PromptAtom(id: 'atom', kind: PromptAtomKind.text, text: 'lore'),
        ],
      );
      CompiledPrompt compile(String? label) =>
          const PromptCompiler(_Counter()).compile(
            PromptCompileInput(
              sources: [source(label)],
              constraints: const PromptCompileConstraints(
                maxContextTokens: 8,
                reservedOutputTokens: 0,
              ),
            ),
          );
      final old = compile(null);
      final labeled = compile('North Tower');
      expect(old.segments.single.sourceId, labeled.segments.single.sourceId);
      expect(old.trace.usedInputTokens, labeled.trace.usedInputTokens);
      expect(labeled.segments.single.atoms.single.text, 'lore');
      expect(labeled.trace.decisions.single.origin.label, 'North Tower');
    },
  );
}
