import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/ai/chat_prompt_builder.dart';
import 'package:ibukihome/application/ai/novel_prompt_builder.dart';
import 'package:ibukihome/application/ai/novel_outline_context.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/chat/chat_message.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/outline/outline_node.dart';
import 'package:ibukihome/domain/segments/segment.dart';
import 'package:ibukihome/domain/world/world_card.dart';

void main() {
  group('NovelPromptBuilder', () {
    test('continue includes project system prompt', () {
      final prompt = _novel().buildContinue(
        project: _project(systemPrompt: '保持安静克制的悬疑感'),
        segments: _segments(2),
        characters: const [],
        worldCards: const [],
        instruction: '继续到第二天',
      );
      expect(prompt.systemPrompt, contains('保持安静克制的悬疑感'));
    });

    test('rewrite includes project system prompt', () {
      final segments = _segments(2);
      final prompt = _novel().buildRewrite(
        project: _project(systemPrompt: '始终使用第三人称。'),
        segments: segments,
        target: segments.first,
        characters: const [],
        worldCards: const [],
        instruction: '',
      );
      expect(prompt.systemPrompt, contains('始终使用第三人称。'));
    });

    test('modify includes project system prompt', () {
      final segments = _segments(2);
      final prompt = _novel().buildModify(
        project: _project(systemPrompt: '对白保持自然。'),
        segments: segments,
        target: segments.first,
        characters: const [],
        worldCards: const [],
        instruction: '减少解释',
      );
      expect(prompt.systemPrompt, contains('对白保持自然。'));
    });

    test('selection modify includes project system prompt', () {
      final target = _segment(0, '少女站在门外等待');
      final prompt = _novel().buildSelectionModify(
        project: _project(systemPrompt: '通过动作表现心理。'),
        segments: [target],
        target: target,
        selectionStart: 2,
        selectionEnd: 6,
        characters: const [],
        worldCards: const [],
        instruction: '更紧张',
      );
      expect(prompt.systemPrompt, contains('通过动作表现心理。'));
    });

    test('outline injects recent completed current and next only', () {
      final nodes = [
        _outline('old', 0, OutlineNodeStatus.completed),
        _outline('recent', 1, OutlineNodeStatus.completed),
        _outline('current', 2, OutlineNodeStatus.current),
        _outline('next', 3, OutlineNodeStatus.planned),
        _outline('later', 4, OutlineNodeStatus.planned),
      ];
      final prompt = _continue(outline: NovelOutlineContext.select(nodes));
      expect(prompt.systemPrompt, contains('recent'));
      expect(prompt.systemPrompt, contains('current'));
      expect(prompt.systemPrompt, contains('next'));
      expect(prompt.systemPrompt, isNot(contains('old')));
      expect(prompt.systemPrompt, isNot(contains('later')));
    });

    test('outline uses first planned when no current exists', () {
      final prompt = _continue(
        outline: NovelOutlineContext.select([
          _outline('first planned', 0, OutlineNodeStatus.planned),
          _outline('second planned', 1, OutlineNodeStatus.planned),
        ]),
      );
      expect(prompt.systemPrompt, contains('【当前剧情目标】'));
      expect(prompt.systemPrompt, contains('first planned'));
      expect(prompt.systemPrompt, contains('second planned'));
    });

    test('all completed outline has no future direction', () {
      final prompt = _continue(
        outline: NovelOutlineContext.select([
          _outline('completed one', 0, OutlineNodeStatus.completed),
          _outline('completed two', 1, OutlineNodeStatus.completed),
        ]),
      );
      expect(prompt.systemPrompt, contains('completed two'));
      expect(prompt.systemPrompt, isNot(contains('completed one')));
      expect(prompt.systemPrompt, isNot(contains('【后续剧情方向】')));
    });

    test('outline technical metadata is excluded', () {
      final node = _outline(
        'Visible title',
        0,
        OutlineNodeStatus.current,
        id: 'secret-outline-id',
      );
      final prompt = _continue(outline: NovelOutlineContext.select([node]));
      expect(prompt.systemPrompt, contains('Visible title'));
      expect(prompt.systemPrompt, isNot(contains('secret-outline-id')));
      expect(prompt.systemPrompt, isNot(contains('revision')));
      expect(prompt.systemPrompt, isNot(contains('order_index')));
    });

    test('continue includes selected character cards', () {
      final prompt = _continue(characters: [_character('伊吹', '谨慎而温柔')]);
      expect(prompt.systemPrompt, contains('伊吹'));
      expect(prompt.systemPrompt, contains('谨慎而温柔'));
    });

    test('continue includes selected world cards', () {
      final prompt = _continue(worldCards: [_world('旧公寓', '发生过失踪事件')]);
      expect(prompt.systemPrompt, contains('旧公寓'));
      expect(prompt.systemPrompt, contains('发生过失踪事件'));
    });

    test('continue uses only the latest context segments', () {
      final prompt = const NovelPromptBuilder(contextSegmentCount: 3)
          .buildContinue(
            project: _project(),
            segments: _segments(6),
            characters: const [],
            worldCards: const [],
            instruction: '',
          );
      expect(prompt.userPrompt, isNot(contains('正文-0')));
      expect(prompt.userPrompt, contains('正文-3'));
      expect(prompt.userPrompt, contains('正文-5'));
    });

    test('continue keeps segment order stable', () {
      final prompt = _continue(segments: _segments(3));
      expect(
        prompt.userPrompt.indexOf('正文-0'),
        lessThan(prompt.userPrompt.indexOf('正文-1')),
      );
      expect(
        prompt.userPrompt.indexOf('正文-1'),
        lessThan(prompt.userPrompt.indexOf('正文-2')),
      );
    });

    test('continue allows an empty direction', () {
      final prompt = _continue(instruction: '   ');
      expect(prompt.userPrompt, isNotEmpty);
      expect(prompt.userPrompt, contains('下一段'));
    });

    test('continue asks for one segment without markdown', () {
      final prompt = _continue();
      expect(prompt.userPrompt, contains('一个段落'));
      expect(prompt.userPrompt, contains('Markdown'));
    });

    test('rewrite includes the target and nearby context', () {
      final segments = _segments(7);
      final prompt = const NovelPromptBuilder(contextSegmentCount: 2)
          .buildRewrite(
            project: _project(),
            segments: segments,
            target: segments[3],
            characters: const [],
            worldCards: const [],
            instruction: '增加环境描写',
          );
      expect(prompt.userPrompt, contains('正文-3'));
      expect(prompt.userPrompt, contains('正文-1'));
      expect(prompt.userPrompt, contains('正文-5'));
    });

    test('rewrite excludes distant context', () {
      final segments = _segments(8);
      final prompt = const NovelPromptBuilder(contextSegmentCount: 1)
          .buildRewrite(
            project: _project(),
            segments: segments,
            target: segments[4],
            characters: const [],
            worldCards: const [],
            instruction: '',
          );
      expect(prompt.userPrompt, isNot(contains('正文-0')));
      expect(prompt.userPrompt, isNot(contains('正文-7')));
    });

    test('rewrite preserves the user requirement', () {
      final segments = _segments(2);
      final prompt = _novel().buildRewrite(
        project: _project(),
        segments: segments,
        target: segments.first,
        characters: const [],
        worldCards: const [],
        instruction: '减少对白',
      );
      expect(prompt.userPrompt, contains('减少对白'));
    });

    test('modify rejects an empty requirement', () {
      final segments = _segments(2);
      expect(
        () => _novel().buildModify(
          project: _project(),
          segments: segments,
          target: segments.first,
          characters: const [],
          worldCards: const [],
          instruction: ' ',
        ),
        throwsArgumentError,
      );
    });

    test('modify includes its focused requirement', () {
      final segments = _segments(2);
      final prompt = _novel().buildModify(
        project: _project(),
        segments: segments,
        target: segments.first,
        characters: const [],
        worldCards: const [],
        instruction: '把语气改得更压抑',
      );
      expect(prompt.userPrompt, contains('把语气改得更压抑'));
    });

    test('selection modify rejects an empty range', () {
      final segments = [_segment(0, '门外有人')];
      expect(
        () => _novel().buildSelectionModify(
          project: _project(),
          segments: segments,
          target: segments.first,
          selectionStart: 2,
          selectionEnd: 2,
          characters: const [],
          worldCards: const [],
          instruction: '更含蓄',
        ),
        throwsArgumentError,
      );
    });

    test('selection modify includes only the selected fragment as target', () {
      final target = _segment(0, '少女站在门外等待');
      final prompt = _novel().buildSelectionModify(
        project: _project(),
        segments: [target],
        target: target,
        selectionStart: 2,
        selectionEnd: 6,
        characters: const [],
        worldCards: const [],
        instruction: '更紧张',
      );
      expect(prompt.userPrompt, contains('站在门外'));
      expect(prompt.userPrompt, contains('更紧张'));
    });

    test('selection modify exposes prefix and suffix for continuity', () {
      final target = _segment(0, '前文选中内容后文');
      final prompt = _novel().buildSelectionModify(
        project: _project(),
        segments: [target],
        target: target,
        selectionStart: 2,
        selectionEnd: 6,
        characters: const [],
        worldCards: const [],
        instruction: '',
      );
      expect(prompt.userPrompt, contains('前文'));
      expect(prompt.userPrompt, contains('后文'));
    });

    test('context count is clamped to at least one', () {
      final prompt = const NovelPromptBuilder(contextSegmentCount: 0)
          .buildContinue(
            project: _project(),
            segments: _segments(3),
            characters: const [],
            worldCards: const [],
            instruction: '',
          );
      expect(prompt.userPrompt, isNot(contains('正文-1')));
      expect(prompt.userPrompt, contains('正文-2'));
    });

    test('context count is clamped to twenty', () {
      final prompt = const NovelPromptBuilder(contextSegmentCount: 99)
          .buildContinue(
            project: _project(),
            segments: _segments(25),
            characters: const [],
            worldCards: const [],
            instruction: '',
          );
      expect(prompt.userPrompt, isNot(contains('正文-4')));
      expect(prompt.userPrompt, contains('正文-5'));
    });
  });

  group('ChatPromptBuilder', () {
    test(
      'context budgeting keeps the newest message and complete examples',
      () {
        const builder = ChatPromptBuilder();
        final current = AiGenerationRequest(
          requestId: 'budget-test',
          systemPrompt: 'persona rules',
          maxTokens: 8192,
          messages: [
            const AiGenerationMessage(
              role: AiMessageRole.user,
              content: 'example input',
            ),
            const AiGenerationMessage(
              role: AiMessageRole.assistant,
              content: 'example output',
            ),
            AiGenerationMessage(
              role: AiMessageRole.user,
              content: 'oversize text ' * 300,
            ),
            const AiGenerationMessage(
              role: AiMessageRole.assistant,
              content: 'recent reply',
            ),
            const AiGenerationMessage(
              role: AiMessageRole.user,
              content: 'latest input',
            ),
          ],
        );
        final bounded = builder.fitToModel(
          current,
          presetMessageCount: 2,
          continuation: false,
          limits: (context: 2048, output: 512),
        );
        expect(bounded.maxTokens, 512);
        expect(bounded.messages.map((m) => m.content), [
          'example input',
          'example output',
          'recent reply',
          'latest input',
        ]);
      },
    );

    test('chat prompt never receives project system prompt', () {
      final project = _project(systemPrompt: 'NOVEL_ONLY_SYSTEM_PROMPT');
      final request = _chat().build(
        requestId: 'request',
        persona: _persona('铃语', '谨慎'),
        messages: [_message(0, ChatMessageRole.user)],
      );
      expect(project.systemPrompt, isNotEmpty);
      expect(request.systemPrompt, isNot(contains(project.systemPrompt)));
    });
    test('simple persona identity is always in the system prompt', () {
      final request = _chat().build(
        requestId: 'request',
        persona: _persona('铃语', '谨慎', speakingStyle: '说话简短'),
        messages: [_message(0, ChatMessageRole.user)],
      );
      expect(request.systemPrompt, contains('铃语'));
      expect(request.systemPrompt, contains('说话简短'));
    });

    test('simple persona omits detailed-only fields', () {
      final request = _chat().build(
        requestId: 'request',
        persona: _persona('铃语', '谨慎', background: '不应注入'),
        messages: [_message(0, ChatMessageRole.user)],
      );
      expect(request.messages, hasLength(1));
      expect(request.systemPrompt, isNot(contains('不应注入')));
    });

    test('detailed persona includes advanced context', () {
      final request = _chat().build(
        requestId: 'request',
        persona: _persona(
          '铃语',
          '谨慎',
          mode: ChatPersonaDescriptionMode.detailed,
          background: '住在旧公寓',
          relationship: '用户的老朋友',
        ),
        messages: [_message(0, ChatMessageRole.user)],
      );
      expect(request.systemPrompt, contains('住在旧公寓'));
      expect(request.systemPrompt, contains('用户的老朋友'));
    });

    test('prompt excludes technical metadata', () {
      final request = _chat().build(
        requestId: 'request',
        persona: _persona('铃语', '谨慎'),
        messages: [_message(0, ChatMessageRole.user)],
      );
      expect(request.systemPrompt, isNot(contains('persona-1')));
      expect(request.systemPrompt, isNot(contains('revision')));
    });

    test('system messages are excluded from history', () {
      final request = _chat().build(
        requestId: 'request',
        persona: _persona('铃语', '谨慎'),
        messages: [
          _message(0, ChatMessageRole.system),
          _message(1, ChatMessageRole.user),
        ],
      );
      expect(request.messages, hasLength(1));
      expect(request.messages.single.role.name, 'user');
    });

    test('chat history uses only the most recent configured window', () {
      final request = const ChatPromptBuilder(recentMessageLimit: 4).build(
        requestId: 'request',
        persona: _persona('铃语', '谨慎'),
        messages: List.generate(
          8,
          (index) => _message(index, ChatMessageRole.user),
        ),
      );
      expect(request.messages, hasLength(4));
      expect(request.messages.first.content, '消息-4');
    });

    test('assistant and user roles are preserved', () {
      final request = _chat().build(
        requestId: 'request',
        persona: _persona('铃语', '谨慎'),
        messages: [
          _message(0, ChatMessageRole.user),
          _message(1, ChatMessageRole.assistant),
        ],
      );
      expect(request.messages.map((item) => item.role.name), [
        'user',
        'assistant',
      ]);
    });

    test('deleted messages are excluded from the prompt', () {
      final request = _chat().build(
        requestId: 'request',
        persona: _persona('铃语', '谨慎'),
        messages: [
          _message(0, ChatMessageRole.user, deleted: true),
          _message(1, ChatMessageRole.user),
        ],
      );
      expect(request.messages, hasLength(1));
      expect(request.messages.single.content, '消息-1');
    });
  });
}

NovelPromptBuilder _novel() => const NovelPromptBuilder();
ChatPromptBuilder _chat() => const ChatPromptBuilder();

AiPrompt _continue({
  List<Segment>? segments,
  List<CharacterCard> characters = const [],
  List<WorldCard> worldCards = const [],
  String instruction = '继续写',
  NovelOutlineContext outline = const NovelOutlineContext(),
}) {
  return _novel().buildContinue(
    project: _project(),
    segments: segments ?? _segments(2),
    characters: characters,
    worldCards: worldCards,
    instruction: instruction,
    outline: outline,
  );
}

Project _project({String systemPrompt = '系统提示词'}) => Project(
  metadata: _metadata('project-1'),
  title: '测试作品',
  description: '项目简介',
  systemPrompt: systemPrompt,
);

OutlineNode _outline(
  String title,
  int order,
  OutlineNodeStatus status, {
  String? id,
}) => OutlineNode(
  metadata: _metadata(id ?? 'outline-$order'),
  projectId: 'project-1',
  title: title,
  summary: '$title summary',
  orderIndex: order,
  status: status,
);

List<Segment> _segments(int count) => [
  for (var index = 0; index < count; index += 1) _segment(index, '正文-$index'),
];

Segment _segment(int index, String content) => Segment(
  metadata: _metadata('segment-$index'),
  projectId: 'project-1',
  orderIndex: index,
  content: content,
);

CharacterCard _character(String name, String content) => CharacterCard(
  metadata: _metadata('character-$name'),
  projectId: 'project-1',
  name: name,
  content: content,
  sortOrder: 0,
);

ChatPersona _persona(
  String name,
  String description, {
  ChatPersonaDescriptionMode mode = ChatPersonaDescriptionMode.simple,
  String speakingStyle = '',
  String background = '',
  String relationship = '',
}) => ChatPersona(
  metadata: _metadata('persona-1'),
  name: name,
  descriptionMode: mode,
  shortDescription: description,
  speakingStyle: speakingStyle,
  background: background,
  relationshipToUser: relationship,
);

WorldCard _world(String title, String content) => WorldCard(
  metadata: _metadata('world-$title'),
  projectId: 'project-1',
  title: title,
  content: content,
  sortOrder: 0,
);

ChatMessage _message(int index, ChatMessageRole role, {bool deleted = false}) =>
    ChatMessage(
      metadata: _metadata(
        'message-$index',
        deletedAt: deleted ? DateTime.utc(2026, 8, 10, 1) : null,
      ),
      sessionId: 'session-1',
      projectId: 'project-1',
      role: role,
      content: '消息-$index',
    );

EntityMetadata _metadata(String id, {DateTime? deletedAt}) => EntityMetadata(
  id: id,
  createdAt: DateTime.utc(2026, 8, 10),
  updatedAt: DateTime.utc(2026, 8, 10),
  revision: 1,
  deletedAt: deletedAt,
);
