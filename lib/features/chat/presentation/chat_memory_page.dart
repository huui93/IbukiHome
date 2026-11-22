import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../app/widgets/bubble_background.dart';
import '../../../app/widgets/ibuki_buttons.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../domain/chat/chat_memory_entry.dart';
import '../../../domain/chat/chat_memory_state.dart';
import '../../../application/memory/chat_memory_service.dart';
import 'chat_memory_overview.dart';
import 'chat_memory_widgets.dart';

class ChatMemoryPage extends ConsumerStatefulWidget {
  const ChatMemoryPage({
    required this.personaId,
    this.sessionId,
    this.summaryView = false,
    super.key,
  });

  final String personaId;
  final String? sessionId;
  final bool summaryView;

  @override
  ConsumerState<ChatMemoryPage> createState() => _ChatMemoryPageState();
}

class _ChatMemoryPageState extends ConsumerState<ChatMemoryPage> {
  bool _showDeleted = false;
  bool _organizing = false;

  @override
  Widget build(BuildContext context) {
    final sessionId = widget.sessionId;
    final excluded = sessionId == null
        ? const <String>[]
        : ref
                  .watch(chatMemoryStateProvider(sessionId))
                  .asData
                  ?.value
                  .excludedSources ??
              const <String>[];
    final entries = sessionId == null
        ? ref.watch(legacyChatMemoryEntryListProvider(widget.personaId))
        : ref.watch(
            _showDeleted
                ? deletedChatMemoryEntryListForSessionProvider(sessionId)
                : chatMemoryEntryListForSessionProvider(sessionId),
          );
    return BubbleBackground(
      child: Scaffold(
        key: const Key('chat-memory-page'),
        appBar: AppBar(
          leading: const BackButton(),
          title: Text(widget.summaryView ? '会话摘要' : '长期记忆'),
          actions: [
            if (sessionId != null)
              IconButton(
                key: const Key('toggle-deleted-memory'),
                tooltip: _showDeleted ? '查看有效记忆' : '已删除记忆',
                onPressed: () => setState(() => _showDeleted = !_showDeleted),
                icon: Icon(
                  _showDeleted
                      ? Icons.memory_rounded
                      : Icons.delete_outline_rounded,
                ),
              ),
          ],
        ),
        body: entries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(child: Text('无法读取长期记忆。')),
          data: (items) => ListView(
            padding: const EdgeInsets.all(AppTokens.spacingM),
            children: [
              if (!_showDeleted && sessionId != null) ...[
                Text(
                  '这些内容只用于当前聊天，不会进入同一角色的其他会话。原始聊天记录不会被删除。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppTokens.spacingM),
                Row(
                  children: [
                    Expanded(
                      child: IbukiSecondaryButton(
                        key: const Key('organize-chat-memory'),
                        label: _organizing ? '正在整理' : '整理会话',
                        icon: Icons.auto_awesome_outlined,
                        onPressed: _organizing ? null : _organize,
                      ),
                    ),
                    const SizedBox(width: AppTokens.spacingS),
                    IbukiPrimaryButton(
                      key: const Key('add-chat-memory'),
                      label: '添加',
                      icon: Icons.add_rounded,
                      onPressed: () => _edit(null),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.spacingL),
                ChatMemoryOverview(sessionId: sessionId),
              ] else if (sessionId == null) ...[
                Text(
                  '这些旧记忆无法安全判断所属会话，因此只保留查看，不会自动注入新聊天。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppTokens.spacingM),
              ],
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spacingXl),
                  child: Center(
                    child: Text(_showDeleted ? '没有已删除记忆。' : '还没有长期记忆。'),
                  ),
                )
              else
                for (final group in _groups(items)) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppTokens.spacingS,
                      bottom: AppTokens.spacingS,
                      top: AppTokens.spacingS,
                    ),
                    child: Text(
                      group.$1,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IbukiGlassSurface(
                    key: Key('memory-section-${group.$1}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.spacingM,
                    ),
                    child: Column(
                      children: [
                        for (var index = 0; index < group.$2.length; index += 1)
                          _MemoryRow(
                            entry: group.$2[index],
                            showDivider: index < group.$2.length - 1,
                            onEdit: () => _edit(group.$2[index]),
                            onPin: () => _togglePin(group.$2[index]),
                            onDelete: () => _delete(group.$2[index]),
                            onRestore: () => _restore(group.$2[index]),
                            onSource: () => _showSource(group.$2[index]),
                            readOnly: sessionId == null,
                            suppressed: excluded.contains(
                              'saved:${group.$2[index].id}',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }

  List<(String, List<ChatMemoryEntry>)> _groups(List<ChatMemoryEntry> items) {
    final result = <(String, List<ChatMemoryEntry>)>[];
    final pinned = items.where((item) => item.isPinned).toList();
    if (pinned.isNotEmpty) result.add(('固定', pinned));
    for (final category in ChatMemoryCategory.values) {
      final group = items
          .where((item) => !item.isPinned && item.category == category)
          .toList();
      if (group.isNotEmpty) result.add((_categoryLabel(category), group));
    }
    return result;
  }

  Future<void> _organize() async {
    setState(() => _organizing = true);
    try {
      final sessionId = widget.sessionId;
      if (sessionId == null) return;
      final result = await ref
          .read(chatMemoryServiceProvider)
          .organize(sessionId, force: true);
      _refresh();
      _message(switch (result) {
        ChatMemoryOrganizationResult.completed => '本会话记忆已整理。',
        ChatMemoryOrganizationResult.insufficient => '没有需要整理的新消息。',
        ChatMemoryOrganizationResult.disabled => '记忆已暂停或关闭，请先调整本会话设置。',
        ChatMemoryOrganizationResult.changed => '整理期间内容已改变，本次结果未写入，请重试。',
        ChatMemoryOrganizationResult.failed => '整理失败，请检查模型配置后重试。聊天记录已保留。',
      });
    } catch (_) {
      _message('整理失败，聊天记录不受影响，可以稍后重试。');
    } finally {
      if (mounted) setState(() => _organizing = false);
    }
  }

  Future<void> _edit(ChatMemoryEntry? entry) async {
    var content = entry?.content ?? '';
    var category = entry?.category ?? ChatMemoryCategory.other;
    var pinned = entry?.isPinned ?? false;
    var saving = false;
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppTokens.spacingM,
            0,
            AppTokens.spacingM,
            MediaQuery.viewInsetsOf(context).bottom + AppTokens.spacingM,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<ChatMemoryCategory>(
                key: const Key('chat-memory-category'),
                initialValue: category,
                items: [
                  for (final item in ChatMemoryCategory.values)
                    DropdownMenuItem(
                      value: item,
                      child: Text(_categoryLabel(item)),
                    ),
                ],
                onChanged: (value) =>
                    setSheetState(() => category = value ?? category),
                decoration: const InputDecoration(labelText: '类别'),
              ),
              const SizedBox(height: AppTokens.spacingS),
              TextFormField(
                key: const Key('chat-memory-content'),
                initialValue: content,
                minLines: 4,
                maxLines: 8,
                maxLength: 4000,
                onChanged: (value) => content = value,
                decoration: const InputDecoration(labelText: '记忆内容'),
              ),
              SwitchListTile(
                title: const Text('固定记忆'),
                subtitle: const Text('自动整理不会覆盖或删除。'),
                value: pinned,
                onChanged: (value) => setSheetState(() => pinned = value),
              ),
              IbukiPrimaryButton(
                key: const Key('save-chat-memory'),
                label: saving ? '保存中' : '保存',
                icon: Icons.save_outlined,
                expand: true,
                onPressed: saving
                    ? null
                    : () async {
                        if (content.trim().isEmpty) return;
                        setSheetState(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await ref
                              .read(chatMemoryServiceProvider)
                              .saveManual(
                                personaId: widget.personaId,
                                sessionId: widget.sessionId,
                                category: category,
                                content: content,
                                pinned: pinned,
                                nowUtc: ref.read(utcClockProvider).now(),
                                entryId: entry?.id,
                              );
                          _refresh();
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        } catch (_) {
                          if (sheetContext.mounted) {
                            setSheetState(() {
                              saving = false;
                              error = '保存失败，请重试。';
                            });
                          }
                        }
                      },
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _togglePin(ChatMemoryEntry entry) async {
    await ref
        .read(chatMemoryServiceProvider)
        .saveManual(
          personaId: widget.personaId,
          sessionId: widget.sessionId,
          category: entry.category,
          content: entry.content,
          pinned: !entry.isPinned,
          nowUtc: ref.read(utcClockProvider).now(),
          entryId: entry.id,
        );
    _refresh();
  }

  Future<void> _delete(ChatMemoryEntry entry) async {
    await ref
        .read(chatMemoryServiceProvider)
        .forget(
          widget.sessionId!,
          ChatMemorySource(
            kind: ChatMemorySourceKind.saved,
            id: entry.id,
            sessionId: widget.sessionId!,
            content: entry.content,
            updatedAt: entry.updatedAt,
          ),
          deleteSaved: true,
        );
    _refresh();
  }

  Future<void> _restore(ChatMemoryEntry entry) async {
    await ref
        .read(chatMemoryServiceProvider)
        .restore(widget.sessionId!, entry.id);
    _refresh();
  }

  void _refresh() => notifyRepositoryChanged(
    ref,
    areas: const [RepositoryDataArea.chatMemory],
  );

  Future<void> _showSource(ChatMemoryEntry entry) async {
    final sources = await ref
        .read(chatMemoryServiceProvider)
        .entrySources(entry);
    if (!mounted) return;
    if (sources.isEmpty) {
      _message('手动记忆或原始来源已不可用。');
      return;
    }
    await showChatMemorySources(context, ref, widget.sessionId!, sources);
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

class _MemoryRow extends StatelessWidget {
  const _MemoryRow({
    required this.entry,
    required this.showDivider,
    required this.onEdit,
    required this.onPin,
    required this.onDelete,
    required this.onRestore,
    required this.onSource,
    this.readOnly = false,
    this.suppressed = false,
  });

  final ChatMemoryEntry entry;
  final bool showDivider;
  final VoidCallback onEdit;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final VoidCallback onRestore;
  final VoidCallback onSource;
  final bool readOnly;
  final bool suppressed;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        key: Key('chat-memory-${entry.id}'),
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          entry.isPinned ? Icons.push_pin_rounded : Icons.memory_rounded,
        ),
        title: Text(entry.content),
        subtitle: Text(
          '${entry.origin == ChatMemoryOrigin.manual ? '手动' : '自动整理'}${suppressed ? ' · 已停止引用' : ''}',
        ),
        trailing: readOnly
            ? null
            : PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'pin') onPin();
                  if (value == 'delete') onDelete();
                  if (value == 'restore') onRestore();
                  if (value == 'source') onSource();
                },
                itemBuilder: (_) => entry.deletedAt != null
                    ? const [PopupMenuItem(value: 'restore', child: Text('恢复'))]
                    : [
                        const PopupMenuItem(value: 'edit', child: Text('编辑')),
                        PopupMenuItem(
                          value: 'pin',
                          child: Text(entry.isPinned ? '取消固定' : '固定'),
                        ),
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                        const PopupMenuItem(
                          value: 'source',
                          child: Text('查看原始来源'),
                        ),
                        if (suppressed)
                          const PopupMenuItem(
                            value: 'restore',
                            child: Text('允许引用'),
                          ),
                      ],
              ),
      ),
      if (showDivider) const Divider(height: 1),
    ],
  );
}

String _categoryLabel(ChatMemoryCategory category) => switch (category) {
  ChatMemoryCategory.userFact => '关于用户',
  ChatMemoryCategory.preference => '偏好',
  ChatMemoryCategory.relationship => '关系',
  ChatMemoryCategory.sharedEvent => '共同经历',
  ChatMemoryCategory.ongoingMatter => '持续事项',
  ChatMemoryCategory.other => '其他',
};
