import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/ibuki_theme_colors.dart';
import '../../../app/widgets/bubble_background.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../app/widgets/ibuki_motion_widgets.dart';
import '../../../application/chat/chat_controls_providers.dart';
import '../../../application/chat/chat_usage_tracker.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../domain/chat/chat_usage_record.dart';

class ChatUsagePage extends ConsumerWidget {
  const ChatUsagePage({required this.sessionId, super.key});
  final String sessionId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(chatSessionByIdProvider(sessionId));
    final usage = ref.watch(chatSessionUsageProvider(sessionId));
    final messages = ref.watch(chatMessageListProvider(sessionId)).value ?? [];
    final theme = Theme.of(context);
    final colors = context.ibukiColors;
    return BubbleBackground(
      child: Scaffold(
        key: const Key('chat-usage-page'),
        appBar: AppBar(
          leading: const BackButton(),
          title: const Text('Token 用量'),
        ),
        body: usage.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () =>
                  ref.invalidate(chatSessionUsageProvider(sessionId)),
              child: const Text('暂时无法读取，点击重试'),
            ),
          ),
          data: (records) {
            final actual = records.where((r) => r.hasCompleteReport).toList();
            final estimated = records
                .where((r) => !r.hasCompleteReport)
                .toList();
            final input = actual.fold<int>(
              0,
              (s, r) => s + r.usage!.inputTokens!,
            );
            final output = actual.fold<int>(
              0,
              (s, r) => s + r.usage!.outputTokens!,
            );
            final total = actual.fold<int>(
              0,
              (s, r) =>
                  s +
                  (r.usage!.totalTokens ??
                      r.usage!.inputTokens! + r.usage!.outputTokens!),
            );
            final cached = actual.fold<int>(
              0,
              (s, r) => s + (r.usage!.cachedInputTokens ?? 0),
            );
            final textEstimate = messages.fold<int>(
              0,
              (s, m) => s + estimateAiTextTokens(m.content) + 4,
            );
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
              children: [
                Text(
                  session.value?.title ?? '当前会话',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 14),
                IbukiEntrance(
                  child: Container(
                    key: const Key('chat-usage-total'),
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        colors: [colors.primarySoft, colors.accentSoft],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.data_usage_rounded,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(child: Text('服务返回用量')),
                            _Badge('${actual.length} 次请求'),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          actual.isEmpty ? '—' : _number(total),
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                        ),
                        Text(
                          actual.isEmpty ? '暂无完整的服务用量记录' : 'tokens · 本会话累计',
                          style: TextStyle(color: colors.textMuted),
                        ),
                        if (input + output > 0) ...[
                          const SizedBox(height: 20),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              children: [
                                if (input > 0)
                                  Expanded(
                                    flex: input,
                                    child: ColoredBox(
                                      color: theme.colorScheme.primary,
                                      child: const SizedBox(height: 7),
                                    ),
                                  ),
                                if (output > 0)
                                  Expanded(
                                    flex: output,
                                    child: ColoredBox(
                                      color: colors.accent,
                                      child: const SizedBox(height: 7),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: _Metric(
                                label: '输入',
                                value: actual.isEmpty ? '—' : _number(input),
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            Expanded(
                              child: _Metric(
                                label: '输出',
                                value: actual.isEmpty ? '—' : _number(output),
                                color: colors.accent,
                              ),
                            ),
                            Expanded(
                              child: _Metric(
                                label: '缓存命中',
                                value: actual.isEmpty ? '—' : _number(cached),
                                color: colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                IbukiEntrance(
                  order: 1,
                  child: IbukiGlassSurface(
                    strong: true,
                    child: ExpansionTile(
                      key: const Key('chat-usage-estimates'),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      leading: Icon(
                        Icons.calculate_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      title: const Text('本地估算'),
                      subtitle: Text(
                        '${messages.length} 条消息 · 当前文本约 ${_number(textEstimate)} tokens',
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      children: [
                        Text(
                          '服务未完整报告的 ${estimated.length} 次请求：输入约 ${_number(estimated.fold<int>(0, (s, r) => s + r.estimatedInputTokens))}，可见输出约 ${_number(estimated.fold<int>(0, (s, r) => s + r.estimatedOutputTokens))}。\n\n消息文本估算不含人格、系统提示词和记忆；请求估算含实际提交的提示词。不可见的推理消耗无法估算。',
                          style: TextStyle(color: colors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text('请求记录', style: theme.textTheme.titleMedium),
                    ),
                    Text(
                      '${records.length} 次',
                      style: TextStyle(color: colors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (records.isEmpty)
                  IbukiGlassSurface(
                    padding: const EdgeInsets.symmetric(
                      vertical: 32,
                      horizontal: 20,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 32,
                          color: colors.textMuted,
                        ),
                        const SizedBox(height: 12),
                        const Text('还没有请求记录。'),
                        const SizedBox(height: 6),
                        Text(
                          '开始聊天后，用量会记录在这里。',
                          style: TextStyle(color: colors.textMuted),
                        ),
                      ],
                    ),
                  )
                else
                  for (final record in records.take(30))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _UsageRow(record: record),
                    ),
                if (records.length > 30)
                  Text(
                    '显示最近 30 次请求，累计用量包含全部已记录请求。',
                    style: theme.textTheme.bodySmall,
                  ),
                if (ref
                    .watch(chatUsageTrackerProvider)
                    .failedSessions
                    .contains(sessionId))
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('部分用量保存失败，统计可能不完整。'),
                  ),
                const SizedBox(height: 14),
                ExpansionTile(
                  key: const Key('chat-usage-explanation'),
                  tilePadding: EdgeInsets.zero,
                  title: Text('统计说明', style: theme.textTheme.bodyMedium),
                  children: [
                    Text(
                      '从本版本开始记录；升级前的历史调用用量未知。包含重试、续写及记忆整理。删除消息不会扣减已发生的用量。输出可包含服务报告的推理 token，缓存命中包含在输入内。本地估算与服务返回值分别统计，此处不是账单。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: color, fontSize: 12)),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .65),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    ),
  );
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.record});
  final ChatUsageRecord record;
  @override
  Widget build(BuildContext context) {
    final date = record.startedAt.toLocal();
    final detail = record.hasCompleteReport
        ? '输入 ${_number(record.usage!.inputTokens!)} · 输出 ${_number(record.usage!.outputTokens!)}'
        : '估算输入约 ${_number(record.estimatedInputTokens)} · 输出约 ${_number(record.estimatedOutputTokens)}';
    return IbukiGlassSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _operation(record.operation),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              _Badge(record.hasCompleteReport ? '服务返回' : '本地估算'),
            ],
          ),
          const SizedBox(height: 8),
          Text(detail),
          if (record.operation == 'image-recognition' &&
              !record.hasCompleteReport)
            Text(
              '本地仅估算文字，不包含图片 token。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 5),
          Text(
            '${record.model.isEmpty ? '未知模型' : record.model} · ${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} · ${_status(record.status)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.ibukiColors.textMuted,
            ),
          ),
          if (record.usage?.reasoningTokens != null)
            Text(
              '其中推理 ${_number(record.usage!.reasoningTokens!)} tokens',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

String _number(int n) => n.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]},',
);
String _status(String value) => switch (value) {
  'stop' => '完成',
  'length' => '达到长度上限',
  'failed' => '未完成',
  'cancelled' => '已停止',
  _ => '未完成',
};
String _operation(String value) => switch (value) {
  'chat-regenerate' => '重新生成',
  'manual-continue' || 'automatic-continue' || 'continue-retry' => '续写',
  'memory-summary' => '会话摘要',
  'memory-extract' => '记忆整理',
  'image-recognition' => '图片识别',
  'chat-reply-retry' => '重试回复',
  _ => '聊天回复',
};
