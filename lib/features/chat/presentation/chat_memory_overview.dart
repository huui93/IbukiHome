import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../domain/chat/chat_memory_state.dart';
import 'chat_memory_widgets.dart';

class ChatMemoryOverview extends ConsumerStatefulWidget {
  const ChatMemoryOverview({required this.sessionId, super.key});
  final String sessionId;
  @override
  ConsumerState<ChatMemoryOverview> createState() => _ChatMemoryOverviewState();
}

class _ChatMemoryOverviewState extends ConsumerState<ChatMemoryOverview> {
  String _query = '';
  Future<List<ChatMemorySource>>? _results;
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    ref.listen(
      repositoryRevisionsProvider.select((value) => value.chatMemory),
      (_, _) {
        if (mounted && _results != null) setState(() => _results = null);
      },
    );
    final state = ref
        .watch(chatMemoryStateProvider(widget.sessionId))
        .asData
        ?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('记忆、摘要和检索都保存在本机。自动整理会把本会话的相关资料发给你配置的模型。最近对话上下文始终独立保留。'),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('本会话记忆设置'),
          children: [ChatMemoryControls(sessionId: widget.sessionId)],
        ),
        if (state != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '记忆概览${state.overviewEdited ? ' · 已手动修订' : ''}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TextButton(
                        key: const Key('edit-memory-overview'),
                        onPressed: _busy ? null : () => _editOverview(state),
                        child: const Text('编辑'),
                      ),
                    ],
                  ),
                  SelectableText(
                    state.overview.isEmpty
                        ? '还没有概览。可以整理对话，或手动填写希望本会话记住的内容。'
                        : state.overview,
                  ),
                  if (state.overviewEdited)
                    TextButton(
                      onPressed: () => _run(
                        () => ref
                            .read(chatMemoryServiceProvider)
                            .updateSettings(
                              widget.sessionId,
                              overview: '',
                              overviewEdited: false,
                            ),
                      ),
                      child: const Text('恢复自动概览'),
                    ),
                  if (state.excludedSources.isNotEmpty)
                    Text(
                      '已停止引用 ${state.excludedSources.length} 个来源。原始消息仍保留。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('search-session-memory'),
          onChanged: (v) => _query = v,
          onFieldSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: '搜索本会话记忆和历史',
            hintText: '例如：饮品偏好、上次的约定',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: '本地搜索',
              onPressed: _search,
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
        ),
        if (_results != null)
          FutureBuilder<List<ChatMemorySource>>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) return const Text('搜索失败，请重试。');
              final results = snapshot.data ?? const [];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    results.isEmpty
                        ? '没有相关结果。仅搜索当前会话。'
                        : '本地检索结果（${results.length}）',
                  ),
                  for (final result in results)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        result.content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(result.label),
                      onTap: () => showChatMemorySources(
                        context,
                        ref,
                        widget.sessionId,
                        [result],
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 8),
        ref
            .watch(conversationSummaryListProvider(widget.sessionId))
            .when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const Text('摘要读取失败。'),
              data: (summaries) => ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('对话摘要（${summaries.length}）'),
                subtitle: const Text('引用前会校验原始消息；失效摘要不会参与回答。'),
                children: [
                  for (final summary in summaries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        summary.summary.isEmpty ? '未完成的摘要' : summary.summary,
                      ),
                      subtitle: Text(
                        '状态：${switch (summary.status.name) {
                          'valid' => '已生成',
                          'stale' => '已失效',
                          'failed' => '生成失败',
                          _ => '生成中',
                        }}',
                      ),
                      onTap: () => showChatMemorySources(
                        context,
                        ref,
                        widget.sessionId,
                        [
                          ChatMemorySource(
                            kind: ChatMemorySourceKind.summary,
                            id: summary.id,
                            sessionId: widget.sessionId,
                            content: summary.summary,
                            updatedAt: summary.updatedAt,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        TextButton.icon(
          key: const Key('clear-session-memory'),
          onPressed: _busy ? null : _clear,
          icon: const Icon(Icons.delete_sweep_outlined),
          label: const Text('清空本会话记忆并关闭'),
        ),
        const Divider(),
      ],
    );
  }

  void _search() {
    final future = ref
        .read(chatMemoryServiceProvider)
        .search(widget.sessionId, _query);
    setState(() {
      _results = future;
    });
  }

  Future<void> _editOverview(ChatMemoryState state) async {
    var text = state.overview;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑本会话记忆概览'),
        content: SingleChildScrollView(
          child: TextFormField(
            key: const Key('memory-overview-content'),
            initialValue: text,
            minLines: 5,
            maxLines: 12,
            maxLength: 6000,
            onChanged: (v) => text = v,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (save == true && mounted) {
      await _run(
        () => ref
            .read(chatMemoryServiceProvider)
            .updateSettings(
              widget.sessionId,
              overview: text.trim(),
              overviewEdited: true,
            ),
      );
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空本会话记忆并关闭？'),
        content: const Text(
          '已保存记忆移入“已删除”，摘要停止引用，自动整理和记忆引用关闭。原始聊天记录保留。不会影响其他会话。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空并关闭'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(
        () => ref
            .read(chatMemoryServiceProvider)
            .clearAndDisable(widget.sessionId),
      );
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        setState(() => _results = null);
        notifyRepositoryChanged(
          ref,
          areas: const [RepositoryDataArea.chatMemory],
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请重试。')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
