import '../../domain/ai/ai_generation.dart';
import '../../domain/characters/character_card.dart';
import '../../domain/projects/project.dart';
import '../../domain/segments/segment.dart';
import '../../domain/world/world_card.dart';
import 'novel_outline_context.dart';
import '../memory/novel_memory_context.dart';

enum NovelAiOperation {
  continueStory,
  rewrite,
  modify,
  selectionModify,
  insert,
}

class NovelPromptBuilder {
  const NovelPromptBuilder({this.contextSegmentCount = 5});

  final int contextSegmentCount;

  AiPrompt buildContinue({
    required Project project,
    required List<Segment> segments,
    required List<CharacterCard> characters,
    required List<WorldCard> worldCards,
    required String instruction,
    NovelOutlineContext outline = const NovelOutlineContext(),
    NovelMemoryContext memory = const NovelMemoryContext(),
    bool structured = false,
  }) {
    final defaultStart = (segments.length - _count).clamp(0, segments.length);
    final start =
        memory.rawSegmentStartOrder?.clamp(0, segments.length) ?? defaultStart;
    final recent = segments.sublist(start);
    return AiPrompt(
      systemPrompt: _system(
        operation: NovelAiOperation.continueStory,
        project: project,
        outline: outline,
        memory: memory,
        characters: characters,
        worldCards: worldCards,
      ),
      userPrompt:
          '''${structured ? '' : '''【最近正文】
${_segments(recent)}

'''}【本次建议】
${instruction.trim().isEmpty ? '（无额外建议，请自然续写）' : instruction.trim()}

【任务】
紧接现有正文生成下一个段落。保持人物、视角、文风与叙事状态连贯，以当前大纲节点为主要推进目标，但不要一次完成所有后续节点。

${_outputRules('下一段正文')}''',
    );
  }

  AiPrompt buildRewrite({
    required Project project,
    required List<Segment> segments,
    required Segment target,
    required List<CharacterCard> characters,
    required List<WorldCard> worldCards,
    required String instruction,
    NovelOutlineContext outline = const NovelOutlineContext(),
    NovelMemoryContext memory = const NovelMemoryContext(),
    bool structured = false,
  }) {
    final index = segments.indexWhere((item) => item.id == target.id);
    if (index < 0) {
      throw ArgumentError('目标段落不属于当前正文。');
    }
    final beforeStart = (index - _count).clamp(0, index);
    final afterEnd = (index + 1 + _count).clamp(0, segments.length);
    return AiPrompt(
      systemPrompt: _system(
        operation: NovelAiOperation.rewrite,
        project: project,
        outline: outline,
        memory: memory,
        characters: characters,
        worldCards: worldCards,
      ),
      userPrompt:
          '''${structured ? '' : '''【前文上下文】
${_segments(segments.sublist(beforeStart, index))}

'''}【需要重写的段落】
${target.content}

${structured ? '' : '''【后文上下文】
${_segments(segments.sublist(index + 1, afterEnd))}

'''}【本次重写要求】
${instruction.trim().isEmpty ? '保留情节作用，在不改变核心事实的前提下优化表达。' : instruction.trim()}

【任务】
只重写目标段落，使其与系统提示词、大纲目标和前后文自然衔接。不要改写或复述相邻段落。

${_outputRules('重写后的这一段正文')}''',
    );
  }

  AiPrompt buildModify({
    required Project project,
    required List<Segment> segments,
    required Segment target,
    required List<CharacterCard> characters,
    required List<WorldCard> worldCards,
    required String instruction,
    NovelOutlineContext outline = const NovelOutlineContext(),
    NovelMemoryContext memory = const NovelMemoryContext(),
    bool structured = false,
  }) {
    if (instruction.trim().isEmpty) {
      throw ArgumentError('修改要求不能为空。');
    }
    final rewrite = buildRewrite(
      project: project,
      segments: segments,
      target: target,
      characters: characters,
      worldCards: worldCards,
      instruction: instruction,
      outline: outline,
      memory: memory,
      structured: structured,
    );
    return AiPrompt(
      systemPrompt: _system(
        operation: NovelAiOperation.modify,
        project: project,
        outline: outline,
        memory: memory,
        characters: characters,
        worldCards: worldCards,
      ),
      userPrompt: rewrite.userPrompt
          .replaceFirst('【本次重写要求】', '【本次定点修改要求】')
          .replaceFirst(
            '只重写目标段落，使其与系统提示词、大纲目标和前后文自然衔接。不要改写或复述相邻段落。',
            '保持目标段落的情节作用和未被要求改变的事实，只按要求修改，并与系统提示词、大纲目标和前后文自然衔接。',
          ),
    );
  }

  AiPrompt buildSelectionModify({
    required Project project,
    required List<Segment> segments,
    required Segment target,
    required int selectionStart,
    required int selectionEnd,
    required List<CharacterCard> characters,
    required List<WorldCard> worldCards,
    required String instruction,
    NovelOutlineContext outline = const NovelOutlineContext(),
    NovelMemoryContext memory = const NovelMemoryContext(),
    bool structured = false,
  }) {
    final start = selectionStart.clamp(0, target.content.length);
    final end = selectionEnd.clamp(start, target.content.length);
    if (end <= start) {
      throw ArgumentError('请选择需要修改的文字。');
    }
    final index = segments.indexWhere((item) => item.id == target.id);
    if (index < 0) {
      throw ArgumentError('目标段落不属于当前正文。');
    }
    final beforeStart = (index - _count).clamp(0, index);
    final afterEnd = (index + 1 + _count).clamp(0, segments.length);
    return AiPrompt(
      systemPrompt: _system(
        operation: NovelAiOperation.selectionModify,
        project: project,
        outline: outline,
        memory: memory,
        characters: characters,
        worldCards: worldCards,
      ),
      userPrompt:
          '''${structured ? '' : '''【当前段落前面的正文】
${_segments(segments.sublist(beforeStart, index))}

'''}【选中内容之前】
${target.content.substring(0, start).isEmpty ? '（选区位于段落开头）' : target.content.substring(0, start)}

【需要修改的内容】
${target.content.substring(start, end)}

【选中内容之后】
${target.content.substring(end).isEmpty ? '（选区位于段落结尾）' : target.content.substring(end)}

${structured ? '' : '''【当前段落后面的正文】
${_segments(segments.sublist(index + 1, afterEnd))}

'''}【本次局部修改要求】
${instruction.trim().isEmpty ? '在保留原意和上下文衔接的前提下优化选中内容。' : instruction.trim()}

【严格任务】
只返回用于替换【需要修改的内容】的新文本。不要返回完整段落，不要返回选区外的前后文。不要解释、分析或添加 Markdown。不要输出段号。''',
    );
  }

  int get _count => contextSegmentCount.clamp(1, 20);

  String structuredSystem({
    required Project project,
    required NovelOutlineContext outline,
  }) =>
      '''
你是伊吹之家的小说创作助手。遵守作者设定、已发生事实与本轮明确要求。

【项目系统提示词】
${project.systemPrompt}

【相关大纲】
${_outline(outline)}
'''
          .trim();

  String _system({
    required NovelAiOperation operation,
    required Project project,
    required NovelOutlineContext outline,
    required NovelMemoryContext memory,
    required List<CharacterCard> characters,
    required List<WorldCard> worldCards,
  }) {
    return '''你是伊吹之家中的小说创作助手，擅长角色一致性、精确改稿与叙事节奏。

【项目系统提示词】
${project.systemPrompt.trim().isEmpty ? '（未设置，请遵循伊吹之家的固定创作规则）' : project.systemPrompt.trim()}

【相关大纲】
${_outline(outline)}

【长期故事记忆】
${_memory(memory)}

【本次参考角色卡】
${_characters(characters)}

【本次参考世界观】
${_worldCards(worldCards)}

必须优先遵守项目系统提示词，并围绕当前剧情目标创作。后续剧情方向只用于自然铺垫，不得在一次生成中全部完成。必须遵守提供的角色和世界设定，不得编造未提供的专有事实。当前操作：${_operationLabel(operation)}。''';
  }

  String _memory(NovelMemoryContext memory) {
    if (memory.isEmpty) return '（当前没有可用的长期故事记忆）';
    final parts = <String>[];
    final digest = memory.digest;
    if (digest != null && digest.content.trim().isNotEmpty) {
      parts.add('【高层长期事实】\n${digest.content.trim()}');
    }
    for (final chunk in memory.recentChunks) {
      parts.add('【往事摘要】\n${chunk.summary.trim()}');
    }
    return parts.join('\n\n');
  }

  String _outline(NovelOutlineContext outline) {
    if (outline.isEmpty) return '（当前没有相关大纲节点）';
    final sections = <String>[];
    final completed = outline.recentCompleted;
    if (completed != null) {
      sections.add(
        '【已发生剧情目标】\n${completed.title}\n${_summary(completed.summary)}',
      );
    }
    final current = outline.current;
    if (current != null) {
      sections.add('【当前剧情目标】\n${current.title}\n${_summary(current.summary)}');
    }
    final next = outline.nextPlanned;
    if (next != null) {
      sections.add('【后续剧情方向】\n${next.title}\n${_summary(next.summary)}');
    }
    return sections.join('\n\n');
  }

  String _summary(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? '（未填写简要描述）' : normalized;
  }

  String _characters(List<CharacterCard> items) {
    if (items.isEmpty) return '（当前项目没有角色卡）';
    return items.map(_characterContext).join('\n\n');
  }

  String _characterContext(CharacterCard item) {
    final name = item.name.trim().isEmpty ? '未命名角色' : item.name.trim();
    final content = item.content.trim().isEmpty
        ? '（未填写详细设定）'
        : item.content.trim();
    if (item.mode != CharacterCardMode.fanfic) {
      return '- $name（${item.mode == CharacterCardMode.original ? '原创' : '旧角色卡'}）：$content';
    }
    final source = [
      item.sourceWorkTitle.trim(),
      item.sourceCharacterName.trim(),
      item.sourceVersionHint.trim(),
    ].where((value) => value.isNotEmpty).join(' / ');
    final adaptation = item.fanficAdaptationNotes.trim();
    return '''- $name（同人；来源：${source.isEmpty ? '未填写' : source}）
【作者当前角色卡，最高优先级】
$content
【二创设定 / 与原作不同之处，高于原作参考】
${adaptation.isEmpty ? '（未填写）' : adaptation}
不得用模型对原作的记忆覆盖上述作者设定。''';
  }

  String _worldCards(List<WorldCard> items) {
    if (items.isEmpty) return '（当前项目没有世界观卡）';
    return items
        .map(
          (item) =>
              '- ${item.title.trim().isEmpty ? '未命名设定' : item.title.trim()}：${item.content.trim().isEmpty ? '（未填写详细设定）' : item.content.trim()}',
        )
        .join('\n');
  }

  String _segments(List<Segment> items) {
    if (items.isEmpty) return '（暂无正文）';
    return items.map((item) => item.content).join('\n\n');
  }

  String _outputRules(String target) {
    return '''【严格输出规则】
- 只输出$target，单次只写一个段落。
- 不要解释、分析、标题、总结或创作说明。不要在正文中输出段号或声称自己正在写第几段。
- 不要说“好的”“以下是”等开场白。
- 不要使用 Markdown 代码块。
- 保持人物、文风、视角和叙事状态一致。''';
  }

  String _operationLabel(NovelAiOperation operation) {
    return switch (operation) {
      NovelAiOperation.continueStory => '生成下一段',
      NovelAiOperation.rewrite => '重写段落',
      NovelAiOperation.modify => '按要求修改段落',
      NovelAiOperation.selectionModify => '选择性修改',
      NovelAiOperation.insert => '插入段落',
    };
  }
}
