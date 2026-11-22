import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/tavern/prompt/prompt_compiler.dart';
import 'package:ibukihome/application/tavern/prompt/prompt_history_assembler.dart';
import 'package:ibukihome/application/tavern/prompt/prompt_models.dart';
import 'package:ibukihome/data/memory/in_memory_tavern_repository.dart';
import 'package:ibukihome/domain/tavern/tavern_models.dart';

final _now = DateTime.utc(2026, 10, 14);

class _Counter implements PromptTokenCounter {
  int calls = 0;
  @override
  int countText(String text) {
    calls++;
    return text.runes.length;
  }

  @override
  int get segmentOverhead => 0;
}

class _FailingCounter implements PromptTokenCounter {
  @override
  int countText(String text) => -1;
  @override
  int get segmentOverhead => 0;
}

class _ThrowingCounter implements PromptTokenCounter {
  @override
  int countText(String text) => throw StateError('estimator unavailable');
  @override
  int get segmentOverhead => 0;
}

class _ZeroCounter implements PromptTokenCounter {
  @override
  int countText(String text) => 0;
  @override
  int get segmentOverhead => 0;
}

PromptSource _source(
  String id,
  String text, {
  PromptSourceType type = PromptSourceType.worldInfo,
  PromptPlacementKind placement = PromptPlacementKind.beforeHistory,
  PromptRoleIntent role = PromptRoleIntent.context,
  PromptBudgetClass budgetClass = PromptBudgetClass.supplemental,
  int priority = 0,
  int order = 0,
  int depth = 0,
  bool required = false,
  List<PromptAtom>? atoms,
}) => PromptSource(
  id: id,
  type: type,
  origin: PromptOrigin(type.name, id),
  role: role,
  placement: PromptPlacement(placement, depth: depth),
  atoms:
      atoms ??
      [PromptAtom(id: '$id:text', kind: PromptAtomKind.text, text: text)],
  priority: priority,
  order: order,
  required: required,
  budgetClass: budgetClass,
);

PromptCompileInput _input(
  List<PromptSource> sources,
  int max, {
  int output = 0,
  int control = 0,
  PromptCompileMode mode = PromptCompileMode.normal,
  ReasoningPromptPolicy reasoning = ReasoningPromptPolicy.exclude,
  ToolPromptPolicy tools = ToolPromptPolicy.exclude,
  AttachmentPromptPolicy attachments = AttachmentPromptPolicy.exclude,
}) => PromptCompileInput(
  sources: sources,
  mode: mode,
  constraints: PromptCompileConstraints(
    maxContextTokens: max,
    reservedOutputTokens: output,
    reservedControlTokens: control,
    reasoningPolicy: reasoning,
    toolPolicy: tools,
    attachmentPolicy: attachments,
  ),
);

List<String> _ids(CompiledPrompt result) =>
    result.segments.map((segment) => segment.sourceId).toList();

Future<InMemoryTavernRepository> _transcriptFixture() async {
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
  Future<void> addTurn(
    String id,
    int position,
    TavernTurnRole role,
    String text,
    String participant,
  ) async {
    await repo.appendTurn(
      TavernTurn(
        id: id,
        sessionId: 's',
        storyLineId: 'main',
        position: position,
        participantId: participant,
        role: role,
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

  await addTurn('user-1', 0, TavernTurnRole.player, 'Question 1', 'player');
  await addTurn(
    'reply-1',
    1,
    TavernTurnRole.character,
    'Frozen answer',
    'character',
  );
  await repo.addAlternative(
    TavernAlternative(
      id: 'reply-1-b',
      turnId: 'reply-1',
      position: 1,
      origin: TavernAlternativeOrigin.generated,
      createdAt: _now,
    ),
  );
  await repo.appendContentPart(
    TavernContentPart(
      id: 'reply-1-b-text',
      alternativeId: 'reply-1-b',
      position: 0,
      kind: TavernContentKind.text,
      text: 'Later main answer',
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
      originTurnId: 'reply-1',
      originAlternativeId: 'reply-1-a',
      createdAt: _now,
    ),
  );
  await repo.selectAlternative('reply-1', 'reply-1-b');
  await addTurn('user-2', 2, TavernTurnRole.player, 'Question 2', 'player');
  await addTurn(
    'reply-between',
    3,
    TavernTurnRole.character,
    'First speaker in this turn',
    'character',
  );
  await addTurn(
    'reply-2',
    4,
    TavernTurnRole.character,
    'Old target answer',
    'character',
  );
  await addTurn('user-3', 5, TavernTurnRole.player, 'Question 3', 'player');
  return repo;
}

void main() {
  test('reserves output and control, then accounts exact fit', () {
    final compiler = PromptCompiler(_Counter());
    final sources = [
      _source(
        'core',
        '1234',
        type: PromptSourceType.system,
        placement: PromptPlacementKind.beforeCharacter,
        required: true,
      ),
      _source(
        'user',
        '123',
        type: PromptSourceType.userInput,
        placement: PromptPlacementKind.tail,
        required: true,
      ),
      _source('optional', '12'),
    ];
    final exact = compiler.compile(_input(sources, 12, output: 2, control: 1));
    expect(exact.trace.usableInputTokens, 9);
    expect(exact.trace.usedInputTokens, 9);
    expect(_ids(exact), ['core', 'optional', 'user']);
    final short = compiler.compile(_input(sources, 11, output: 2, control: 1));
    expect(_ids(short), ['core', 'user']);
    expect(
      short.trace.decisions.singleWhere((d) => d.sourceId == 'optional').reason,
      PromptCompileReason.budgetExhausted,
    );
    final extra = compiler.compile(_input(sources, 13, output: 2, control: 1));
    expect(extra.trace.usedInputTokens, 9);
  });

  test('required sources never disappear, including zero optional budget', () {
    final compiler = PromptCompiler(_Counter());
    final required = _source('required', '1234', required: true);
    final optional = _source('optional', '1');
    expect(_ids(compiler.compile(_input([required, optional], 4))), [
      'required',
    ]);
    expect(
      () => compiler.compile(_input([required], 3)),
      throwsA(
        isA<PromptCompileFailure>().having(
          (e) => e.kind,
          'kind',
          PromptCompileFailureKind.requiredOverflow,
        ),
      ),
    );
  });

  test(
    'required overflow is typed and optional never consumes reservation',
    () {
      final compiler = PromptCompiler(_Counter());
      final required = [
        _source('a', 'a' * 70, required: true),
        _source('b', 'b' * 50, required: true),
      ];
      expect(
        () => compiler.compile(_input(required, 100)),
        throwsA(
          isA<PromptCompileFailure>()
              .having(
                (e) => e.kind,
                'kind',
                PromptCompileFailureKind.requiredOverflow,
              )
              .having((e) => e.sourceId, 'source', 'b'),
        ),
      );
      final result = compiler.compile(
        _input([
          _source('core', 'c' * 90, required: true),
          _source('optional', 'o' * 20),
        ], 100),
      );
      expect(_ids(result), ['core']);
      expect(result.trace.usedInputTokens, 90);
      expect(
        result.trace.decisions
            .singleWhere((d) => d.sourceId == 'optional')
            .reason,
        PromptCompileReason.budgetExhausted,
      );
    },
  );

  test('empty and whitespace sources drop; zero-token source is explicit', () {
    final compiler = PromptCompiler(_Counter());
    final result = compiler.compile(
      _input([_source('empty', ''), _source('spaces', ' \n\t ')], 10),
    );
    expect(result.segments, isEmpty);
    expect(
      result.trace.decisions.map((d) => d.reason),
      everyElement(PromptCompileReason.empty),
    );
    final zero = PromptCompiler(
      _ZeroCounter(),
    ).compile(_input([_source('zero', 'meaningful')], 1));
    expect(_ids(zero), ['zero']);
    expect(zero.trace.usedInputTokens, 0);
    expect(
      () => compiler.compile(
        _input([_source('required-space', '  ', required: true)], 10),
      ),
      throwsA(
        isA<PromptCompileFailure>().having(
          (e) => e.kind,
          'kind',
          PromptCompileFailureKind.invalidSource,
        ),
      ),
    );
  });

  test('counter exception never returns a partial compiled prompt', () {
    expect(
      () => PromptCompiler(
        _ThrowingCounter(),
      ).compile(_input([_source('safe', 'text')], 10)),
      throwsA(
        isA<PromptCompileFailure>().having(
          (e) => e.kind,
          'kind',
          PromptCompileFailureKind.tokenCounterFailure,
        ),
      ),
    );
  });

  test(
    'giant optional source has distinct reason; excluded required fails',
    () {
      final compiler = PromptCompiler(_Counter());
      final result = compiler.compile(
        _input([_source('giant', '12345678901')], 10),
      );
      expect(
        result.trace.decisions.single.reason,
        PromptCompileReason.sourceTooLarge,
      );
      final hidden = _source(
        'hidden',
        '',
        required: true,
        atoms: const [
          PromptAtom(
            id: 'private',
            kind: PromptAtomKind.reasoning,
            text: 'do not forward',
          ),
        ],
      );
      expect(
        () => compiler.compile(_input([hidden], 100)),
        throwsA(
          isA<PromptCompileFailure>().having(
            (e) => e.kind,
            'kind',
            PromptCompileFailureKind.invalidSource,
          ),
        ),
      );
    },
  );

  test('Character, Persona, examples, World Info and RAG stay distinct', () {
    final compiler = PromptCompiler(_Counter());
    final sources = [
      _source(
        'character',
        'C',
        type: PromptSourceType.character,
        placement: PromptPlacementKind.afterCharacter,
        budgetClass: PromptBudgetClass.grounding,
      ),
      _source(
        'persona',
        'P',
        type: PromptSourceType.persona,
        placement: PromptPlacementKind.beforeHistory,
        budgetClass: PromptBudgetClass.grounding,
      ),
      _source(
        'example',
        'E',
        type: PromptSourceType.exampleDialogue,
        placement: PromptPlacementKind.beforeHistory,
      ),
      _source(
        'lore',
        'W',
        type: PromptSourceType.worldInfo,
        placement: PromptPlacementKind.beforeHistory,
        budgetClass: PromptBudgetClass.grounding,
        priority: 5,
      ),
      _source(
        'rag',
        'R',
        type: PromptSourceType.rag,
        placement: PromptPlacementKind.afterHistory,
      ),
    ];
    final result = compiler.compile(_input(sources, 4));
    expect(_ids(result), ['character', 'lore', 'example', 'persona']);
    expect(
      result.trace.decisions.singleWhere((d) => d.sourceId == 'rag').reason,
      PromptCompileReason.budgetExhausted,
    );
    expect(
      result.trace.decisions.map((d) => d.sourceType).toSet(),
      containsAll([
        PromptSourceType.character,
        PromptSourceType.persona,
        PromptSourceType.exampleDialogue,
        PromptSourceType.worldInfo,
        PromptSourceType.rag,
      ]),
    );
  });

  test('history is trimmed from oldest whole Turn and never re-tokenized', () {
    final counter = _Counter();
    final compiler = PromptCompiler(counter);
    final history = [
      for (var i = 0; i < 10; i++)
        _source(
          'h$i',
          '123',
          type: PromptSourceType.history,
          placement: PromptPlacementKind.history,
          budgetClass: PromptBudgetClass.history,
          order: i,
        ),
    ];
    final result = compiler.compile(
      _input([
        _source(
          'user',
          'X',
          type: PromptSourceType.userInput,
          placement: PromptPlacementKind.tail,
          required: true,
        ),
        ...history,
      ], 10),
    );
    expect(_ids(result), ['h7', 'h8', 'h9', 'user']);
    expect(counter.calls, 11);
    expect(
      result.trace.decisions.where(
        (d) => d.outcome == PromptCompileOutcome.trimmed,
      ),
      hasLength(7),
    );
  });

  test('depth insertion counts retained history from newest', () {
    final compiler = PromptCompiler(_Counter());
    final sources = [
      _source(
        'system',
        'S',
        type: PromptSourceType.system,
        placement: PromptPlacementKind.beforeCharacter,
        required: true,
      ),
      _source(
        'character',
        'C',
        type: PromptSourceType.character,
        placement: PromptPlacementKind.afterCharacter,
        budgetClass: PromptBudgetClass.grounding,
      ),
      for (var i = 0; i < 3; i++)
        _source(
          'h$i',
          'H',
          type: PromptSourceType.history,
          placement: PromptPlacementKind.history,
          budgetClass: PromptBudgetClass.history,
          order: i,
        ),
      _source(
        'note',
        'N',
        type: PromptSourceType.authorNote,
        placement: PromptPlacementKind.atHistoryDepth,
        depth: 1,
        budgetClass: PromptBudgetClass.grounding,
      ),
      _source(
        'user',
        'U',
        type: PromptSourceType.userInput,
        placement: PromptPlacementKind.tail,
        required: true,
      ),
    ];
    expect(_ids(compiler.compile(_input(sources, 100))), [
      'system',
      'character',
      'h0',
      'h1',
      'note',
      'h2',
      'user',
    ]);
    expect(_ids(compiler.compile(_input(sources, 6))), [
      'system',
      'character',
      'h1',
      'note',
      'h2',
      'user',
    ]);
  });

  test('history depth 0, N and beyond retained history clamp predictably', () {
    final sources = [
      for (var i = 0; i < 3; i++)
        _source(
          'h$i',
          'H',
          type: PromptSourceType.history,
          placement: PromptPlacementKind.history,
          budgetClass: PromptBudgetClass.history,
          order: i,
        ),
      _source(
        'after-latest',
        'A',
        placement: PromptPlacementKind.atHistoryDepth,
        depth: 0,
        budgetClass: PromptBudgetClass.grounding,
      ),
      _source(
        'at-oldest',
        'O',
        placement: PromptPlacementKind.atHistoryDepth,
        depth: 3,
        budgetClass: PromptBudgetClass.grounding,
      ),
      _source(
        'beyond',
        'B',
        placement: PromptPlacementKind.atHistoryDepth,
        depth: 100,
        budgetClass: PromptBudgetClass.grounding,
      ),
    ];
    final compiler = PromptCompiler(_Counter());
    expect(_ids(compiler.compile(_input(sources, 10))), [
      'at-oldest',
      'beyond',
      'h0',
      'h1',
      'h2',
      'after-latest',
    ]);
    expect(_ids(compiler.compile(_input(sources, 4))), [
      'at-oldest',
      'beyond',
      'h2',
      'after-latest',
    ]);
  });

  test('same-slot ties and candidate versus final order are explicit', () {
    final compiler = PromptCompiler(_Counter());
    final sources = [
      _source('z', 'Z', priority: 0),
      _source('b', 'B', priority: 1, order: 2),
      _source('a', 'A', priority: 1, order: 2),
    ];
    final result = compiler.compile(_input(sources, 3));
    expect(_ids(result), ['a', 'b', 'z']);
    expect(result.trace.decisions.map((d) => d.sourceId), ['a', 'b', 'z']);
    expect(result.trace.decisions.map((d) => d.inputIndex), [2, 1, 0]);
    expect(result.trace.decisions.map((d) => d.finalIndex), [0, 1, 2]);
    for (var i = 0; i < 1000; i++) {
      final again = compiler.compile(_input(sources, 3));
      expect(_ids(again), _ids(result));
      expect(
        again.trace.decisions.map(
          (d) =>
              '${d.sourceId}:${d.inputIndex}:${d.finalIndex}:${d.reason.name}',
        ),
        result.trace.decisions.map(
          (d) =>
              '${d.sourceId}:${d.inputIndex}:${d.finalIndex}:${d.reason.name}',
        ),
      );
    }
  });

  test('multi-part history Turn is included or trimmed as one unit', () {
    final compiler = PromptCompiler(_Counter());
    final turn = _source(
      'turn',
      '',
      type: PromptSourceType.history,
      placement: PromptPlacementKind.history,
      budgetClass: PromptBudgetClass.history,
      atoms: const [
        PromptAtom(id: 'first', kind: PromptAtomKind.text, text: 'one'),
        PromptAtom(id: 'middle', kind: PromptAtomKind.text, text: 'two'),
        PromptAtom(id: 'last', kind: PromptAtomKind.text, text: 'three'),
      ],
    );
    final newer = _source(
      'newer',
      'new',
      type: PromptSourceType.history,
      placement: PromptPlacementKind.history,
      budgetClass: PromptBudgetClass.history,
      order: 1,
    );
    expect(_ids(compiler.compile(_input([turn, newer], 14))), [
      'turn',
      'newer',
    ]);
    final trimmed = compiler.compile(_input([turn, newer], 13));
    expect(_ids(trimmed), ['newer']);
    expect(
      trimmed.trace.decisions.singleWhere((d) => d.sourceId == 'turn').outcome,
      PromptCompileOutcome.trimmed,
    );
  });

  test('history must be one atomic source per Turn and use history budget', () {
    final compiler = PromptCompiler(_Counter());
    PromptSource fragment(String id, PromptBudgetClass budget) => PromptSource(
      id: id,
      type: PromptSourceType.history,
      origin: const PromptOrigin('turn', 'same-turn'),
      role: PromptRoleIntent.assistantLike,
      placement: const PromptPlacement(PromptPlacementKind.history),
      atoms: [PromptAtom(id: '$id:text', kind: PromptAtomKind.text, text: id)],
      budgetClass: budget,
    );
    expect(
      () => compiler.compile(
        _input([
          fragment('part-a', PromptBudgetClass.history),
          fragment('part-b', PromptBudgetClass.history),
        ], 100),
      ),
      throwsA(
        isA<PromptCompileFailure>().having(
          (e) => e.kind,
          'kind',
          PromptCompileFailureKind.invalidSource,
        ),
      ),
    );
    expect(
      () => compiler.compile(
        _input([fragment('wrong-budget', PromptBudgetClass.supplemental)], 100),
      ),
      throwsA(
        isA<PromptCompileFailure>().having(
          (e) => e.kind,
          'kind',
          PromptCompileFailureKind.invalidInsertion,
        ),
      ),
    );
  });

  test(
    'tie breaking and trace are deterministic across source permutations',
    () {
      final compiler = PromptCompiler(_Counter());
      final sources = [_source('z', 'Z'), _source('a', 'A'), _source('b', 'B')];
      final first = compiler.compile(_input(sources, 2));
      final second = compiler.compile(_input(sources.reversed.toList(), 2));
      expect(_ids(first), ['a', 'b']);
      expect(_ids(second), _ids(first));
      expect(
        first.trace.decisions.map(
          (d) => '${d.sourceId}:${d.reason.name}:${d.finalIndex}',
        ),
        second.trace.decisions.map(
          (d) => '${d.sourceId}:${d.reason.name}:${d.finalIndex}',
        ),
      );
    },
  );

  test('reasoning and tool parts follow explicit policies with provenance', () {
    final source = _source(
      'turn',
      '',
      type: PromptSourceType.history,
      placement: PromptPlacementKind.history,
      budgetClass: PromptBudgetClass.history,
      atoms: const [
        PromptAtom(id: 'visible', kind: PromptAtomKind.text, text: 'Hello'),
        PromptAtom(
          id: 'reasoning',
          kind: PromptAtomKind.reasoning,
          text: 'private',
        ),
        PromptAtom(
          id: 'summary',
          kind: PromptAtomKind.reasoningSummary,
          text: 'summary',
        ),
        PromptAtom(
          id: 'call',
          kind: PromptAtomKind.toolCall,
          toolName: 'lookup',
          toolCallId: 'inv-1',
          arguments: {'q': 'x'},
        ),
        PromptAtom(
          id: 'result',
          kind: PromptAtomKind.toolResult,
          toolCallId: 'inv-1',
          result: {'ok': true},
        ),
        PromptAtom(id: 'event', kind: PromptAtomKind.event, text: 'status'),
      ],
    );
    final compiler = PromptCompiler(_Counter());
    final defaultResult = compiler.compile(_input([source], 100));
    expect(defaultResult.segments.single.atoms.map((a) => a.id), ['visible']);
    expect(defaultResult.trace.decisions.single.excludedAtomIds, [
      'reasoning',
      'summary',
      'call',
      'result',
      'event',
    ]);
    final enabled = compiler.compile(
      _input(
        [source],
        100,
        reasoning: ReasoningPromptPolicy.summaryOnly,
        tools: ToolPromptPolicy.structured,
      ),
    );
    expect(enabled.segments.single.atoms.map((a) => a.id), [
      'visible',
      'summary',
      'call',
      'result',
    ]);
    expect(enabled.segments.single.atoms[2].toolCallId, 'inv-1');
    expect(enabled.segments.single.atoms[3].toolCallId, 'inv-1');
    expect(enabled.trace.decisions.single.sourceType, PromptSourceType.history);
    expect(
      enabled.trace.decisions.single.placement.kind,
      PromptPlacementKind.history,
    );
    expect(enabled.trace.decisions.single.role, PromptRoleIntent.context);
  });

  test('full reasoning and attachments require separate opt-in policies', () {
    final source = _source(
      'rich',
      '',
      atoms: const [
        PromptAtom(id: 'speech', kind: PromptAtomKind.text, text: 'Hello'),
        PromptAtom(
          id: 'thought',
          kind: PromptAtomKind.reasoning,
          text: 'hidden',
        ),
        PromptAtom(
          id: 'picture',
          kind: PromptAtomKind.attachment,
          assetReference: 'asset-1',
          mimeType: 'image/png',
        ),
      ],
    );
    final compiler = PromptCompiler(_Counter());
    expect(
      compiler
          .compile(_input([source], 100))
          .segments
          .single
          .atoms
          .map((a) => a.id),
      ['speech'],
    );
    final included = compiler.compile(
      _input(
        [source],
        100,
        reasoning: ReasoningPromptPolicy.include,
        attachments: AttachmentPromptPolicy.reference,
      ),
    );
    expect(included.segments.single.atoms.map((a) => a.id), [
      'speech',
      'thought',
      'picture',
    ]);
    expect(included.segments.single.atoms.last.assetReference, 'asset-1');
    expect(included.trace.decisions.single.excludedAtomIds, isEmpty);
  });

  test('bounded successful compilations retain all required sources', () {
    final compiler = PromptCompiler(_Counter());
    for (var budget = 1; budget <= 120; budget++) {
      final sources = [
        _source('required', 'R', required: true),
        for (var i = 0; i < 12; i++)
          _source('optional-$i', 'x' * (i + 1), priority: i % 4),
      ];
      final result = compiler.compile(_input(sources, budget));
      expect(result.trace.usedInputTokens, lessThanOrEqualTo(budget));
      expect(_ids(result), contains('required'));
      expect(result.trace.decisions, hasLength(sources.length));
      expect(_ids(result).toSet().length, result.segments.length);
    }
  });

  test('invalid structured Tool Part is rejected before budget selection', () {
    final source = _source(
      'bad-tool',
      '',
      atoms: const [
        PromptAtom(
          id: 'call',
          kind: PromptAtomKind.toolCall,
          toolName: 'lookup',
          arguments: {'q': 'x'},
        ),
      ],
    );
    expect(
      () => PromptCompiler(
        _Counter(),
      ).compile(_input([source], 100, tools: ToolPromptPolicy.structured)),
      throwsA(
        isA<PromptCompileFailure>().having(
          (e) => e.kind,
          'kind',
          PromptCompileFailureKind.invalidSource,
        ),
      ),
    );
  });

  test(
    'invalid identity, insertion and token counter fail with typed errors',
    () {
      final compiler = PromptCompiler(_Counter());
      final source = _source('x', 'X');
      expect(
        () => compiler.compile(_input([source, source], 10)),
        throwsA(
          isA<PromptCompileFailure>().having(
            (e) => e.kind,
            'kind',
            PromptCompileFailureKind.invalidSource,
          ),
        ),
      );
      expect(
        () => compiler.compile(
          _input([
            _source(
              'bad',
              'X',
              placement: PromptPlacementKind.atHistoryDepth,
              depth: -1,
            ),
          ], 10),
        ),
        throwsA(
          isA<PromptCompileFailure>().having(
            (e) => e.kind,
            'kind',
            PromptCompileFailureKind.invalidInsertion,
          ),
        ),
      );
      expect(
        () => compiler.compile(_input([source], 0)),
        throwsA(
          isA<PromptCompileFailure>().having(
            (e) => e.kind,
            'kind',
            PromptCompileFailureKind.invalidConstraints,
          ),
        ),
      );
      expect(
        () => PromptCompiler(_FailingCounter()).compile(_input([source], 10)),
        throwsA(
          isA<PromptCompileFailure>().having(
            (e) => e.kind,
            'kind',
            PromptCompileFailureKind.tokenCounterFailure,
          ),
        ),
      );
    },
  );

  test('30, 50 and 100 candidates each receive one explained decision', () {
    final compiler = PromptCompiler(_Counter());
    for (final count in [30, 50, 100]) {
      final sources = [
        for (var i = 0; i < count; i++)
          _source('entry-$i', '1234', priority: i % 3),
      ];
      final result = compiler.compile(_input(sources, 80));
      expect(result.trace.decisions, hasLength(count));
      expect(result.trace.usedInputTokens, lessThanOrEqualTo(80));
      expect(_ids(result).toSet().length, result.segments.length);
      expect(
        result.trace.decisions.every((d) => d.reason.name.isNotEmpty),
        isTrue,
      );
    }
  });

  test('100, 500 and 1000 Turn budgets remain linear and bounded', () {
    for (final count in [100, 500, 1000]) {
      final counter = _Counter();
      final compiler = PromptCompiler(counter);
      final history = [
        for (var i = 0; i < count; i++)
          _source(
            'turn-$i',
            '1234567890',
            type: PromptSourceType.history,
            placement: PromptPlacementKind.history,
            budgetClass: PromptBudgetClass.history,
            order: i,
          ),
      ];
      final watch = Stopwatch()..start();
      final result = compiler.compile(_input(history, 100));
      watch.stop();
      expect(result.segments, hasLength(10));
      expect(result.segments.first.sourceId, 'turn-${count - 10}');
      expect(result.trace.decisions, hasLength(count));
      expect(counter.calls, count);
      expect(watch.elapsedMilliseconds, lessThan(2000));
    }
  });

  test('1000 Turns plus 50 sources build a complete trace in one pass', () {
    final counter = _Counter();
    final history = [
      for (var i = 0; i < 1000; i++)
        _source(
          'turn-$i',
          '1234567890',
          type: PromptSourceType.history,
          placement: PromptPlacementKind.history,
          budgetClass: PromptBudgetClass.history,
          order: i,
        ),
    ];
    final extras = [
      for (var i = 0; i < 50; i++) _source('lore-$i', '12345', priority: i),
    ];
    final profile = PromptCompiler(
      counter,
    ).profile(_input([...history, ...extras], 300));
    final result = profile.prompt;
    expect(result.trace.decisions, hasLength(1050));
    expect(counter.calls, 1050);
    expect(result.trace.usedInputTokens, lessThanOrEqualTo(300));
    expect(profile.total.inMilliseconds, lessThan(2000));
    debugPrint(
      'Prompt 1000+50: total=${profile.total.inMicroseconds}us '
      'estimate=${profile.tokenEstimation.inMicroseconds}us '
      'trace=${profile.traceConstruction.inMicroseconds}us',
    );
  });

  test(
    'normal, regenerate and Continue consume projected alternatives',
    () async {
      final repo = await _transcriptFixture();
      final assembler = PromptHistoryAssembler();
      final compiler = PromptCompiler(_Counter());
      final main = await repo.loadTranscript('s', storyLineId: 'main');
      final normal = assembler.assemble(
        main,
        mode: PromptCompileMode.normal,
        targetTurnId: 'user-3',
      );
      expect(normal.sources.last.type, PromptSourceType.userInput);
      expect(normal.sources.last.atoms.single.text, 'Question 3');
      final normalPrompt = compiler.compile(_input(normal.sources, 1000));
      expect(
        normalPrompt.segments
            .expand((segment) => segment.atoms)
            .map((atom) => atom.text),
        contains('Later main answer'),
      );
      expect(
        normalPrompt.segments
            .expand((segment) => segment.atoms)
            .map((atom) => atom.text),
        isNot(contains('Frozen answer')),
      );
      final regen = assembler.assemble(
        main,
        mode: PromptCompileMode.regenerate,
        targetTurnId: 'reply-2',
      );
      expect(regen.sources.last.atoms.single.text, 'Question 2');
      expect(regen.sources.any((s) => s.origin.id == 'reply-2'), isFalse);
      final regenPrompt = compiler.compile(
        _input(regen.sources, 1000, mode: PromptCompileMode.regenerate),
      );
      expect(
        regenPrompt.segments.any(
          (s) => s.atoms.any((a) => a.text == 'Old target answer'),
        ),
        isFalse,
      );
      final regenTexts = regenPrompt.segments
          .expand((segment) => segment.atoms)
          .map((atom) => atom.text)
          .toList();
      expect(
        regenTexts.indexOf('Question 2'),
        lessThan(regenTexts.indexOf('First speaker in this turn')),
      );
      final continuation = assembler.assemble(
        main,
        mode: PromptCompileMode.continueTurn,
        targetTurnId: 'reply-2',
      );
      final continuePrompt = compiler.compile(
        _input(
          continuation.sources,
          1000,
          mode: PromptCompileMode.continueTurn,
        ),
      );
      expect(continuePrompt.segments.last.continuation, isTrue);
      expect(continuePrompt.segments.last.role, PromptRoleIntent.assistantLike);
      expect(
        continuePrompt.segments.last.atoms.single.text,
        'Old target answer',
      );
      expect(
        continuePrompt.segments.where(
          (s) => s.atoms.any((a) => a.text == 'Old target answer'),
        ),
        hasLength(1),
      );
    },
  );

  test(
    'child Story Line compiles frozen Alternative, not current Main choice',
    () async {
      final repo = await _transcriptFixture();
      final child = await repo.loadTranscript('s', storyLineId: 'child');
      expect(child.turns.last.selectedAlternative.id, 'reply-1-a');
      final assembly = const PromptHistoryAssembler().assemble(
        child,
        mode: PromptCompileMode.continueTurn,
        targetTurnId: 'reply-1',
      );
      final compiled = PromptCompiler(_Counter()).compile(
        _input(assembly.sources, 100, mode: PromptCompileMode.continueTurn),
      );
      expect(compiled.segments.last.atoms.single.text, 'Frozen answer');
      expect(
        compiled.segments.last.atoms.single.text,
        isNot('Later main answer'),
      );
    },
  );

  test('nested Story Line compiles both frozen ancestors in order', () async {
    final repo = await _transcriptFixture();
    await repo.appendTurn(
      TavernTurn(
        id: 'child-reply',
        sessionId: 's',
        storyLineId: 'child',
        position: 0,
        participantId: 'character',
        role: TavernTurnRole.character,
        createdAt: _now,
        updatedAt: _now,
      ),
      TavernAlternative(
        id: 'child-a',
        turnId: 'child-reply',
        position: 0,
        origin: TavernAlternativeOrigin.manual,
        createdAt: _now,
      ),
    );
    await repo.appendContentPart(
      TavernContentPart(
        id: 'child-a-text',
        alternativeId: 'child-a',
        position: 0,
        kind: TavernContentKind.text,
        text: 'Frozen child answer',
        createdAt: _now,
      ),
    );
    await repo.addAlternative(
      TavernAlternative(
        id: 'child-b',
        turnId: 'child-reply',
        position: 1,
        origin: TavernAlternativeOrigin.manual,
        createdAt: _now,
      ),
    );
    await repo.appendContentPart(
      TavernContentPart(
        id: 'child-b-text',
        alternativeId: 'child-b',
        position: 0,
        kind: TavernContentKind.text,
        text: 'Later child answer',
        createdAt: _now,
      ),
    );
    await repo.createStoryLine(
      TavernStoryLine(
        id: 'grandchild',
        sessionId: 's',
        name: 'Grandchild',
        position: 2,
        parentId: 'child',
        originTurnId: 'child-reply',
        originAlternativeId: 'child-a',
        createdAt: _now,
      ),
    );
    await repo.selectAlternative('child-reply', 'child-b');
    final transcript = await repo.loadTranscript(
      's',
      storyLineId: 'grandchild',
    );
    expect(transcript.turns.map((t) => t.turn.id), [
      'user-1',
      'reply-1',
      'child-reply',
    ]);
    final assembled = const PromptHistoryAssembler().assemble(
      transcript,
      mode: PromptCompileMode.continueTurn,
      targetTurnId: 'child-reply',
    );
    final compiled = PromptCompiler(_Counter()).compile(
      _input(assembled.sources, 1000, mode: PromptCompileMode.continueTurn),
    );
    expect(compiled.segments.expand((s) => s.atoms).map((a) => a.text), [
      'Question 1',
      'Frozen answer',
      'Frozen child answer',
    ]);
    expect(compiled.segments.last.continuation, isTrue);
  });

  test(
    'Foundation projection hides failed partial from Continue prompt',
    () async {
      final repo = await _transcriptFixture();
      await repo.recordAttempt(
        TavernGenerationAttempt(
          id: 'failed',
          sessionId: 's',
          storyLineId: 'main',
          turnId: 'reply-2',
          alternativeId: 'reply-2-a',
          position: 0,
          status: TavernGenerationStatus.queued,
          type: TavernGenerationType.continueTurn,
          createdAt: _now,
        ),
      );
      await repo.appendContentPart(
        TavernContentPart(
          id: 'failed-part',
          alternativeId: 'reply-2-a',
          position: 1,
          kind: TavernContentKind.text,
          text: 'failed partial',
          generationAttemptId: 'failed',
          createdAt: _now,
        ),
      );
      await repo.appendContentPart(
        TavernContentPart(
          id: 'failed-reasoning',
          alternativeId: 'reply-2-a',
          position: 2,
          kind: TavernContentKind.reasoning,
          text: 'failed private reasoning',
          generationAttemptId: 'failed',
          createdAt: _now,
        ),
      );
      await repo.updateAttempt(
        'failed',
        TavernGenerationStatus.failed,
        hasPartialContent: true,
      );
      final transcript = await repo.loadTranscript('s', storyLineId: 'main');
      final assembled = const PromptHistoryAssembler().assemble(
        transcript,
        mode: PromptCompileMode.continueTurn,
        targetTurnId: 'reply-2',
      );
      final compiled = PromptCompiler(_Counter()).compile(
        _input(assembled.sources, 1000, mode: PromptCompileMode.continueTurn),
      );
      expect(compiled.segments.last.atoms.map((atom) => atom.text), [
        'Old target answer',
      ]);
      expect(
        compiled.segments
            .expand((segment) => segment.atoms)
            .any((atom) => atom.text == 'failed partial'),
        isFalse,
      );
      final evenWithReasoning = PromptCompiler(_Counter()).compile(
        _input(
          assembled.sources,
          1000,
          mode: PromptCompileMode.continueTurn,
          reasoning: ReasoningPromptPolicy.include,
        ),
      );
      expect(
        evenWithReasoning.segments
            .expand((segment) => segment.atoms)
            .any((atom) => atom.text == 'failed private reasoning'),
        isFalse,
      );
    },
  );
}
