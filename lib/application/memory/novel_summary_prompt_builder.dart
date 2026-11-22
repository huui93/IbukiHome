import '../../domain/ai/ai_generation.dart';
import '../../domain/memory/novel_summary_chunk.dart';
import '../../domain/memory/story_memory_digest.dart';
import '../../domain/segments/segment.dart';

class NovelSummaryPromptBuilder {
  const NovelSummaryPromptBuilder();

  AiGenerationRequest buildChunk({
    required String requestId,
    required List<Segment> segments,
  }) {
    return AiGenerationRequest(
      requestId: requestId,
      systemPrompt:
          '''你负责整理小说的长期事实记忆。只提取原文明确发生、且可能影响后续写作的事实：重要事件、人物关系变化、已揭示信息、未解决伏笔、关键地点或物件、状态变化与因果关系。不要续写，不要模仿文风，不要添加推测，不要把可能性写成确定事实。''',
      messages: [
        AiGenerationMessage(
          role: AiMessageRole.user,
          content: '''请将以下正文整理为紧凑的长期事实摘要。保留段落范围内对未来写作仍有用的信息。

${segments.map((item) => '[第 ${item.orderIndex + 1} 段]\n${item.content}').join('\n\n')}''',
        ),
      ],
      temperature: 0.1,
      maxTokens: 1200,
    );
  }
}

class StoryDigestPromptBuilder {
  const StoryDigestPromptBuilder();

  AiGenerationRequest build({
    required String requestId,
    required StoryMemoryDigest? previous,
    required List<NovelSummaryChunk> chunks,
  }) {
    return AiGenerationRequest(
      requestId: requestId,
      systemPrompt:
          '''你负责维护小说的高层长期记忆。合并已有记忆与新的分块摘要，保留重要事件、关系变化、揭示信息、未解决伏笔、地点物件和持续状态。忠于输入，不得创造剧情，不得把猜测改成事实。输出紧凑的事实列表。''',
      messages: [
        AiGenerationMessage(
          role: AiMessageRole.user,
          content:
              '''【已有长期记忆】
${previous?.content.trim().isNotEmpty == true ? previous!.content : '（无）'}

【分块摘要】
${chunks.map((item) => '第 ${item.sourceStartOrder + 1}-${item.sourceEndOrder + 1} 段：\n${item.summary}').join('\n\n')}''',
        ),
      ],
      temperature: 0.1,
      maxTokens: 1600,
    );
  }
}
