import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../app/routing/app_routes.dart';
import '../../../application/memory/chat_memory_service.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../domain/chat/chat_memory_state.dart';

class ChatMemoryControls extends ConsumerStatefulWidget {
  const ChatMemoryControls({required this.sessionId, super.key});
  final String sessionId;
  @override
  ConsumerState<ChatMemoryControls> createState() => _ChatMemoryControlsState();
}

class _ChatMemoryControlsState extends ConsumerState<ChatMemoryControls> {
  bool _busy = false;
  String? _error;
  @override
  Widget build(BuildContext context) => ref
      .watch(chatMemoryStateProvider(widget.sessionId))
      .when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => TextButton(
          onPressed: () =>
              ref.invalidate(chatMemoryStateProvider(widget.sessionId)),
          child: const Text('无法读取记忆设置，点击重试'),
        ),
        data: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              key: Key('session-use-memory-${widget.sessionId}'),
              contentPadding: EdgeInsets.zero,
              title: const Text('引用已保存记忆'),
              subtitle: const Text('关闭后也会关闭历史引用；不会删除已保存内容。'),
              value: state.savedEnabled,
              onChanged: _busy
                  ? null
                  : (v) => _run(
                      () => ref
                          .read(chatMemoryServiceProvider)
                          .updateSettings(widget.sessionId, savedEnabled: v),
                    ),
            ),
            SwitchListTile(
              key: Key('session-history-memory-${widget.sessionId}'),
              contentPadding: EdgeInsets.zero,
              title: const Text('引用本会话历史'),
              subtitle: const Text('按当前问题检索较早消息和摘要。'),
              value: state.historyEnabled,
              onChanged: _busy || !state.savedEnabled
                  ? null
                  : (v) => _run(
                      () => ref
                          .read(chatMemoryServiceProvider)
                          .updateSettings(widget.sessionId, historyEnabled: v),
                    ),
            ),
            SwitchListTile(
              key: Key('session-auto-memory-${widget.sessionId}'),
              contentPadding: EdgeInsets.zero,
              title: const Text('自动保存长期记忆'),
              subtitle: const Text('摘要由历史引用开关控制。整理会产生额外 API 请求。'),
              value: state.autoSave,
              onChanged: _busy
                  ? null
                  : (v) => _run(
                      () => ref
                          .read(chatMemoryServiceProvider)
                          .updateSettings(widget.sessionId, autoSave: v),
                    ),
            ),
            SwitchListTile(
              key: Key('session-pause-memory-${widget.sessionId}'),
              contentPadding: EdgeInsets.zero,
              title: const Text('暂停本会话记忆'),
              subtitle: const Text('暂停引用和整理，仍保留聊天记录与最近上下文。'),
              value: state.paused,
              onChanged: _busy
                  ? null
                  : (v) => _run(
                      () => ref
                          .read(chatMemoryServiceProvider)
                          .updateSettings(widget.sessionId, paused: v),
                    ),
            ),
            ListTile(
              key: Key('memory-compression-rounds-${widget.sessionId}'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('自动压缩轮数')),
              subtitle: Text(
                context.tr('每 {rounds} 个完整轮次整理一次', {
                  'rounds': state.compressionRounds,
                }),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              enabled: !_busy,
              onTap: _busy ? null : () => _editCompressionRounds(state),
            ),
            ListTile(
              key: Key('compress-memory-now-${widget.sessionId}'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.compress_rounded),
              title: Text(context.tr('立即压缩会话')),
              subtitle: Text(
                context.tr(
                  state.historyEnabled && state.canRead
                      ? '生成当前会话摘要，原始消息保留。'
                      : '先开启历史引用并取消暂停。',
                ),
              ),
              enabled: !_busy && state.canRead && state.historyEnabled,
              onTap: _busy || !state.canRead || !state.historyEnabled
                  ? null
                  : _compressNow,
            ),
            if (_error != null)
              Text(
                context.tr(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      );
  Future<void> _editCompressionRounds(ChatMemoryState state) async {
    var input = state.compressionRounds.toString();
    var invalid = false;
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (dialog, setDialogState) => AlertDialog(
          title: Text(dialog.tr('自动压缩轮数')),
          content: TextFormField(
            key: const Key('memory-compression-rounds-input'),
            initialValue: input,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: dialog.tr('轮数'),
              helperText: dialog.tr('默认 50 轮'),
              errorText: invalid ? dialog.tr('压缩轮数须在 1 到 1000 之间。') : null,
            ),
            onChanged: (value) {
              input = value;
              if (invalid) setDialogState(() => invalid = false);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(dialog.tr('取消')),
            ),
            FilledButton(
              key: const Key('save-memory-compression-rounds'),
              onPressed: () {
                final value = int.tryParse(input);
                if (value == null ||
                    value < 1 ||
                    value > ChatMemoryState.maximumCompressionRounds) {
                  setDialogState(() => invalid = true);
                  return;
                }
                Navigator.pop(dialog, value);
              },
              child: Text(dialog.tr('保存')),
            ),
          ],
        ),
      ),
    );
    if (!mounted || chosen == null || chosen == state.compressionRounds) return;
    await _run(
      () => ref
          .read(chatMemoryServiceProvider)
          .updateSettings(widget.sessionId, compressionRounds: chosen),
    );
  }

  Future<void> _compressNow() => _run(() async {
    final result = await ref
        .read(chatMemoryServiceProvider)
        .organize(widget.sessionId, force: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr(chatMemoryOrganizationMessage(result))),
      ),
    );
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) {
        notifyRepositoryChanged(
          ref,
          areas: const [RepositoryDataArea.chatMemory],
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

String chatMemoryOrganizationMessage(ChatMemoryOrganizationResult result) =>
    switch (result) {
      ChatMemoryOrganizationResult.completed => '本会话已压缩。',
      ChatMemoryOrganizationResult.summarySaved => '摘要已保存，长期记忆提取失败，下次可重试。',
      ChatMemoryOrganizationResult.insufficient => '没有可压缩的新完整轮次。',
      ChatMemoryOrganizationResult.disabled => '先开启历史引用并取消暂停。',
      ChatMemoryOrganizationResult.changed => '压缩期间会话已变化，请重试。',
      ChatMemoryOrganizationResult.failed => '压缩失败，请检查模型配置后重试。',
    };

class ChatReplyMemoryBadge extends ConsumerWidget {
  const ChatReplyMemoryBadge({
    required this.sessionId,
    required this.messageId,
    super.key,
  });
  final String sessionId;
  final String messageId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(chatReplyMemorySourcesProvider((sessionId, messageId)))
      .when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (sources) => sources.isEmpty
            ? const SizedBox.shrink()
            : TextButton.icon(
                key: Key('reply-memory-sources-$messageId'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                onPressed: () =>
                    showChatMemorySources(context, ref, sessionId, sources),
                icon: const Icon(Icons.manage_search_rounded, size: 16),
                label: Text(
                  '提供了 ${sources.length} 条本地记忆参考',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
      );
}

Future<void> showChatMemorySources(
  BuildContext context,
  WidgetRef ref,
  String sessionId,
  List<ChatMemorySource> sources,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheetContext) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * .72,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('本会话的本地来源', style: Theme.of(sheetContext).textTheme.titleLarge),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('这些内容曾提供给模型作为参考，不代表回答的每个结论都来自记忆。已删除或更改的来源可能不再显示。'),
          ),
          for (final source in sources)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.label,
                      style: Theme.of(sheetContext).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(source.content),
                    if (source.kind == ChatMemorySourceKind.saved ||
                        source.kind == ChatMemorySourceKind.summary)
                      TextButton.icon(
                        onPressed: () async {
                          final originals = await ref
                              .read(chatMemoryServiceProvider)
                              .sourceMessages(source);
                          if (!sheetContext.mounted) return;
                          if (originals.isEmpty) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(content: Text('原始消息已不可用。')),
                            );
                            return;
                          }
                          await showChatMemorySources(
                            sheetContext,
                            ref,
                            sessionId,
                            originals,
                          );
                        },
                        icon: const Icon(Icons.subject, size: 18),
                        label: const Text('查看原始消息'),
                      ),
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          await ref
                              .read(chatMemoryServiceProvider)
                              .forget(sessionId, source);
                          notifyRepositoryChanged(
                            ref,
                            areas: const [RepositoryDataArea.chatMemory],
                          );
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        } catch (_) {
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(content: Text('保存失败，请重试。')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.visibility_off_outlined, size: 18),
                      label: const Text('不再引用此来源'),
                    ),
                  ],
                ),
              ),
            ),
          TextButton(
            onPressed: () async {
              final session = await ref
                  .read(chatRepositoryProvider)
                  .getSession(sessionId);
              if (!context.mounted || session.personaId == null) return;
              if (sheetContext.mounted) Navigator.pop(sheetContext);
              context.push(AppRoutes.chatSessionMemory(sessionId));
            },
            child: const Text('管理本会话记忆'),
          ),
        ],
      ),
    ),
  ),
);
