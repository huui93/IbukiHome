import 'dart:io';
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/theme/bubble_theme.dart';
import '../../../app/theme/ibuki_theme_colors.dart';
import '../../../app/widgets/bubble_background.dart';
import '../../../app/widgets/follow_bottom_controller.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../application/ai/ai_draft_update.dart';
import '../../../application/plugins/plugin_contributions.dart';
import '../../../application/plugins/plugin_providers.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../core/errors/data_exceptions.dart';
import '../../../domain/chat/chat_message.dart';
import '../../../domain/chat/chat_message_role.dart';
import '../../../domain/chat/chat_persona.dart';
import '../../../domain/chat/chat_preset_message.dart';
import '../../../application/profile/profile_avatar_picker.dart';
import '../../../application/chat/chat_avatar_store.dart';
import '../../../domain/chat/chat_session.dart';
import '../../../domain/ai/ai_generation.dart';
import '../../ai/presentation/ai_ui_helpers.dart';
import '../../ai/presentation/ai_model_binding_sheet.dart';
import '../../plugins/presentation/plugin_web_panel_page.dart';
import 'chat_memory_widgets.dart';
import 'chat_session_tools.dart';
import 'chat_image_widgets.dart';
import '../../../application/chat/chat_image_picker.dart';
import '../../../domain/chat/chat_image.dart';
import '../../../app/widgets/ibuki_action_menu.dart';
import '../../../app/widgets/ibuki_motion_widgets.dart';
import '../../../app/localization/app_localizations.dart';

enum _ChatCreationAction { persona, session, edit }

Future<void> showChatCreationMenu(BuildContext context) async {
  final action = await showIbukiActionMenu<_ChatCreationAction>(
    context: context,
    menuKey: const Key('chat-creation-menu'),
    width: 220,
    builder: (dialogContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in const [
          (_ChatCreationAction.persona, '添加人格', Icons.person_add_alt_1_rounded),
          (_ChatCreationAction.session, '添加会话', Icons.add_comment_outlined),
          (_ChatCreationAction.edit, '修改人格', Icons.manage_accounts_outlined),
        ])
          IbukiEntrance(
            order: entry.$1.index,
            offset: const Offset(12, 0),
            child: ListTile(
              key: Key('chat-menu-${entry.$1.name}'),
              leading: Icon(entry.$3),
              title: Text(dialogContext.tr(entry.$2)),
              onTap: () => Navigator.pop(dialogContext, entry.$1),
            ),
          ),
      ],
    ),
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case _ChatCreationAction.persona:
      context.push(AppRoutes.newChatPersona);
    case _ChatCreationAction.session:
      context.push(AppRoutes.selectChatPersona());
    case _ChatCreationAction.edit:
      context.push(AppRoutes.selectChatPersona(edit: true));
  }
}

class SimpleChatHomePage extends StatelessWidget {
  const SimpleChatHomePage({super.key});
  @override
  Widget build(BuildContext context) =>
      const KeyedSubtree(key: Key('chat-home-page'), child: _ChatMessagesTab());
}

class _ChatMessagesTab extends ConsumerWidget {
  const _ChatMessagesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(chatSessionListProvider);
    return sessions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _ChatErrorView(
        message: context.tr("消息列表暂时无法读取。"),
        onRetry: () => ref.invalidate(chatSessionListProvider),
      ),
      data: (items) {
        final visible = items;
        if (visible.isEmpty) {
          return _ChatEmptyView(
            key: Key('empty-chat-sessions-state'),
            icon: Icons.forum_outlined,
            title: context.tr("还没有消息"),
            message: context.tr("点击右上角 +，添加人格或会话。"),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(chatSessionListProvider);
            await ref.read(chatSessionListProvider.future);
          },
          child: ListView.separated(
            key: const Key('chat-message-list'),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, index) => IbukiEntrance(
              key: ValueKey('conversation-arrival-${visible[index].id}'),
              order: index,
              animate: index < 6,
              child: _ConversationTile(session: visible[index]),
            ),
          ),
        );
      },
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.session});

  final ChatSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(chatMessageListProvider(session.id));
    final persona = session.personaId == null
        ? null
        : ref.watch(chatPersonaByIdProvider(session.personaId!)).value;
    final displayName = session.title;
    final lastMessage = messages.value?.lastOrNull;
    return IbukiGlassSurface(
      key: Key('conversation-${session.id}'),
      radius: AppTokens.radiusL,
      onTap: () => context.push(AppRoutes.chatSession(session.id)),
      child: ListTile(
        key: Key('chat-session-tile-${session.id}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
        leading: _PersonaAvatar(persona: persona, fallbackName: displayName),
        title: Row(
          children: [
            Expanded(
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              _compactTime(lastMessage?.createdAt ?? session.updatedAt),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.ibukiColors.textMuted,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (session.title != displayName)
              Text(
                session.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.ibukiColors.textMuted,
                ),
              ),
            Text(
              lastMessage?.content ??
                  (persona == null ? context.tr("旧会话") : context.tr("还没有消息")),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

enum ChatPersonaPickerPurpose { newSession, edit }

class ChatPersonaPickerPage extends ConsumerStatefulWidget {
  const ChatPersonaPickerPage({
    this.purpose = ChatPersonaPickerPurpose.newSession,
    super.key,
  });
  final ChatPersonaPickerPurpose purpose;

  @override
  ConsumerState<ChatPersonaPickerPage> createState() =>
      _ChatPersonaPickerPageState();
}

class _ChatPersonaPickerPageState extends ConsumerState<ChatPersonaPickerPage> {
  bool _creating = false;
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(chatPersonaListProvider);
    return PopScope(
      canPop: !_creating,
      child: BubbleBackground(
        child: Scaffold(
          key: const Key('chat-persona-picker'),
          appBar: AppBar(
            title: Text(
              widget.purpose == ChatPersonaPickerPurpose.edit
                  ? context.tr("修改人格")
                  : context.tr("选择聊天对象"),
            ),
            leading: BackButton(
              onPressed: _creating
                  ? null
                  : () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(AppRoutes.chat);
                      }
                    },
            ),
          ),
          body: contacts.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => _ChatErrorView(
              message: context.tr("联系人暂时无法读取。"),
              onRetry: () => ref.invalidate(chatPersonaListProvider),
            ),
            data: (items) {
              final query = _query.trim().toLowerCase();
              final filtered = items.where((item) {
                return query.isEmpty ||
                    item.name.toLowerCase().contains(query) ||
                    item.unifiedPrompt.toLowerCase().contains(query);
              }).toList();
              return Column(
                key: const Key('chat-contacts-page'),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('contact-search-field'),
                            onChanged: (value) =>
                                setState(() => _query = value),
                            decoration: InputDecoration(
                              hintText: context.tr("搜索聊天角色"),
                              prefixIcon: Icon(Icons.search_rounded),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          key: const Key('add-chat-persona'),
                          tooltip: context.tr("添加聊天角色"),
                          onPressed: _creating ? null : _showCreateOptions,
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? _ChatEmptyView(
                            key: const Key('empty-chat-contacts'),
                            icon: Icons.people_outline_rounded,
                            title: context.tr("还没有可以聊天的角色"),
                            message: context.tr("快速写几句话，就可以创建一个新的聊天角色。"),
                            actionLabel: context.tr("创建聊天角色"),
                            onAction: _showCreateOptions,
                          )
                        : ListView.separated(
                            key: const Key('chat-persona-list'),
                            padding: const EdgeInsets.fromLTRB(12, 2, 12, 20),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, index) => KeyedSubtree(
                              key: Key('contact-${filtered[index].id}'),
                              child: _PersonaTile(
                                persona: filtered[index],
                                onTap: _creating
                                    ? null
                                    : () => _select(filtered[index]),
                              ),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _select(ChatPersona persona) async {
    if (_creating) return;
    if (widget.purpose == ChatPersonaPickerPurpose.edit) {
      context.pushReplacement(AppRoutes.editChatPersona(persona.id));
      return;
    }
    setState(() => _creating = true);
    try {
      final session = await ref
          .read(openPersonaChatProvider)
          .createNew(
            personaId: persona.id,
            newSessionId: ref.read(entityIdGeneratorProvider).nextId('chat'),
            nowUtc: ref.read(utcClockProvider).now(),
          );
      if (!mounted) return;
      notifyRepositoryChanged(
        ref,
        areas: const [RepositoryDataArea.chatSessions],
      );
      context.pushReplacement(AppRoutes.chatSession(session.id));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyChatError(error))));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _showCreateOptions() async {
    await showModalBottomSheet<void>(
      useRootNavigator: true,
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('create-new-chat-persona'),
                leading: const Icon(Icons.person_add_alt_1_rounded),
                title: Text(sheetContext.tr("新建聊天角色")),
                subtitle: Text(sheetContext.tr("填写名字和人格提示词")),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push(AppRoutes.newChatPersona);
                },
              ),
              ListTile(
                key: const Key('deleted-chat-personas'),
                leading: const Icon(Icons.restore_from_trash_outlined),
                title: Text(sheetContext.tr("已删除聊天角色")),
                subtitle: Text(sheetContext.tr("恢复保留的角色与历史会话")),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push(AppRoutes.deletedChatPersonas);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonaTile extends StatelessWidget {
  const _PersonaTile({required this.persona, required this.onTap});

  final ChatPersona persona;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IbukiGlassSurface(
      key: Key('persona-${persona.id}'),
      radius: AppTokens.radiusL,
      onTap: onTap,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
        leading: _PersonaAvatar(persona: persona),
        title: Row(
          children: [
            Expanded(
              child: Text(
                persona.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        subtitle: Text(
          persona.unifiedPrompt.trim().isEmpty
              ? context.tr("还没有填写人格提示词")
              : persona.unifiedPrompt,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class ChatPersonaProfilePage extends ConsumerStatefulWidget {
  const ChatPersonaProfilePage({required this.personaId, super.key});

  final String personaId;

  @override
  ConsumerState<ChatPersonaProfilePage> createState() =>
      _ChatPersonaProfilePageState();
}

class _ChatPersonaProfilePageState
    extends ConsumerState<ChatPersonaProfilePage> {
  var _opening = false;

  @override
  Widget build(BuildContext context) {
    final persona = ref.watch(chatPersonaByIdProvider(widget.personaId));
    return BubbleBackground(
      child: Scaffold(
        key: const Key('chat-persona-profile'),
        appBar: AppBar(
          leading: KeyedSubtree(
            key: const Key('character-profile-back-button'),
            child: BackButton(
              key: const Key('persona-profile-back-button'),
              onPressed: _backToChat,
            ),
          ),
          title: Text(context.tr("人格资料")),
          actions: [
            IconButton(
              key: const Key('edit-chat-persona'),
              tooltip: context.tr("修改人格"),
              onPressed: () =>
                  context.push(AppRoutes.editChatPersona(widget.personaId)),
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<String>(
              key: const Key('chat-persona-more'),
              tooltip: context.tr("更多"),
              onSelected: (value) {
                if (value == 'delete') _confirmDelete();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'delete', child: Text(context.tr("删除角色"))),
              ],
            ),
          ],
        ),
        body: persona.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _ChatErrorView(message: context.tr("没有找到这个聊天角色。")),
          data: (persona) => ListView(
            key: const Key('character-chat-profile'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Center(child: _PersonaAvatar(persona: persona, radius: 44)),
              const SizedBox(height: 14),
              Text(
                persona.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const SizedBox(height: 20),
              IbukiGlassSurface(
                strong: true,
                padding: const EdgeInsets.all(16),
                child: _PersonaProfileSections(persona: persona),
              ),
              const SizedBox(height: 12),
              _PersonaRecentSessions(persona: persona),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('new-persona-chat-button'),
                      onPressed: persona.deletedAt != null || _opening
                          ? null
                          : () => _openChat(persona, createNew: true),
                      icon: const Icon(Icons.add_comment_outlined),
                      label: Text(context.tr("新聊天")),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: KeyedSubtree(
                      key: const Key('message-character-button'),
                      child: FilledButton.icon(
                        key: const Key('message-persona-button'),
                        onPressed: persona.deletedAt != null || _opening
                            ? null
                            : () => _openChat(persona),
                        icon: _opening
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chat_bubble_outline_rounded),
                        label: Text(context.tr("继续聊天")),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () =>
                    context.push(AppRoutes.editChatPersona(persona.id)),
                icon: const Icon(Icons.edit_outlined),
                label: Text(context.tr("编辑角色")),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openChat(ChatPersona persona, {bool createNew = false}) async {
    setState(() => _opening = true);
    try {
      final opener = ref.read(openPersonaChatProvider);
      final session = createNew
          ? await opener.createNew(
              personaId: persona.id,
              newSessionId: ref.read(entityIdGeneratorProvider).nextId('chat'),
              nowUtc: ref.read(utcClockProvider).now(),
            )
          : await opener.continueLatest(
              personaId: persona.id,
              newSessionId: ref.read(entityIdGeneratorProvider).nextId('chat'),
              nowUtc: ref.read(utcClockProvider).now(),
            );
      if (!mounted) return;
      notifyRepositoryChanged(
        ref,
        areas: const [RepositoryDataArea.chatSessions],
      );
      context.go(AppRoutes.chatSession(session.id));
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _backToChat() async {
    if (await Navigator.of(context).maybePop() || !mounted) return;
    context.go(AppRoutes.chat);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr("删除聊天角色？")),
        content: Text(dialogContext.tr("角色会移到已删除列表，已有会话和消息仍会保留。")),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.tr("取消")),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.tr("删除")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(softDeleteChatPersonaProvider)(
        personaId: widget.personaId,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      notifyRepositoryChanged(
        ref,
        areas: const [RepositoryDataArea.chatPersonas],
      );
      if (mounted) context.go(AppRoutes.chat);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_friendlyChatError(error))));
  }
}

class ChatPersonaSessionsPage extends ConsumerStatefulWidget {
  const ChatPersonaSessionsPage({required this.personaId, super.key});

  final String personaId;

  @override
  ConsumerState<ChatPersonaSessionsPage> createState() =>
      _ChatPersonaSessionsPageState();
}

class _ChatPersonaSessionsPageState
    extends ConsumerState<ChatPersonaSessionsPage> {
  var _showDeleted = false;

  @override
  Widget build(BuildContext context) {
    final persona = ref.watch(chatPersonaByIdProvider(widget.personaId));
    final sessions = ref.watch(
      _showDeleted
          ? deletedChatSessionsByPersonaProvider(widget.personaId)
          : chatSessionsByPersonaProvider(widget.personaId),
    );
    return BubbleBackground(
      child: Scaffold(
        key: const Key('persona-session-list-page'),
        appBar: AppBar(
          leading: const BackButton(),
          title: Text('${persona.value?.name ?? '角色'}的聊天'),
          actions: [
            IconButton(
              key: const Key('toggle-deleted-persona-sessions'),
              tooltip: _showDeleted ? context.tr("有效聊天") : context.tr("已删除聊天"),
              onPressed: () => setState(() => _showDeleted = !_showDeleted),
              icon: Icon(
                _showDeleted
                    ? Icons.forum_outlined
                    : Icons.delete_outline_rounded,
              ),
            ),
            IconButton(
              key: const Key('new-persona-session'),
              tooltip: context.tr("新聊天"),
              onPressed: _showDeleted || persona.value == null
                  ? null
                  : () => _create(persona.value!),
              icon: const Icon(Icons.add_comment_outlined),
            ),
          ],
        ),
        body: sessions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _ChatErrorView(message: context.tr("聊天列表暂时无法读取。")),
          data: (items) => items.isEmpty
              ? _ChatEmptyView(
                  icon: Icons.forum_outlined,
                  title: _showDeleted
                      ? context.tr("没有已删除聊天")
                      : context.tr("还没有聊天"),
                  message: _showDeleted
                      ? context.tr("删除的聊天会出现在这里。")
                      : context.tr("创建一条独立的新聊天吧。"),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final session = items[index];
                    return IbukiGlassSurface(
                      key: Key('persona-session-${session.id}'),
                      onTap: _showDeleted
                          ? null
                          : () =>
                                context.push(AppRoutes.chatSession(session.id)),
                      child: ListTile(
                        title: Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(_compactTime(session.updatedAt)),
                        trailing: _showDeleted
                            ? TextButton(
                                onPressed: () => _restore(session),
                                child: Text(context.tr("恢复")),
                              )
                            : PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'rename') _rename(session);
                                  if (value == 'delete') _delete(session);
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text(context.tr("重命名")),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(context.tr("删除")),
                                  ),
                                ],
                              ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _create(ChatPersona persona) async {
    final session = await ref
        .read(openPersonaChatProvider)
        .createNew(
          personaId: persona.id,
          newSessionId: ref.read(entityIdGeneratorProvider).nextId('chat'),
          nowUtc: ref.read(utcClockProvider).now(),
        );
    _refresh();
    if (mounted) context.push(AppRoutes.chatSession(session.id));
  }

  Future<void> _rename(ChatSession session) async {
    var title = session.title;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr("重命名聊天")),
        content: TextFormField(
          initialValue: title,
          autofocus: true,
          onChanged: (text) => title = text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.tr("取消")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, title),
            child: Text(dialogContext.tr("保存")),
          ),
        ],
      ),
    );
    if (value == null) return;
    await ref.read(renameChatSessionProvider)(
      sessionId: session.id,
      title: value,
      nowUtc: ref.read(utcClockProvider).now(),
    );
    _refresh();
  }

  Future<void> _delete(ChatSession session) async {
    await ref.read(softDeleteChatSessionProvider)(
      sessionId: session.id,
      nowUtc: ref.read(utcClockProvider).now(),
    );
    _refresh();
  }

  Future<void> _restore(ChatSession session) async {
    await ref.read(restoreChatSessionProvider)(
      sessionId: session.id,
      nowUtc: ref.read(utcClockProvider).now(),
    );
    _refresh();
  }

  void _refresh() => notifyRepositoryChanged(
    ref,
    areas: const [RepositoryDataArea.chatSessions],
  );
}

class DeletedChatPersonasPage extends ConsumerWidget {
  const DeletedChatPersonasPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personas = ref.watch(deletedChatPersonaListProvider);
    return BubbleBackground(
      child: Scaffold(
        key: const Key('deleted-chat-personas-page'),
        appBar: AppBar(
          leading: BackButton(
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.chat);
              }
            },
          ),
          title: Text(context.tr("已删除聊天角色")),
        ),
        body: personas.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _ChatErrorView(message: context.tr("暂时无法读取已删除角色。")),
          data: (items) {
            if (items.isEmpty) {
              return _ChatEmptyView(
                icon: Icons.person_off_outlined,
                title: context.tr("没有已删除角色"),
                message: context.tr("删除的聊天角色会保留在这里，并可随时恢复。"),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final persona = items[index];
                return IbukiGlassSurface(
                  key: Key('deleted-persona-${persona.id}'),
                  radius: AppTokens.radiusL,
                  child: ListTile(
                    leading: _PersonaAvatar(persona: persona),
                    title: Text(
                      persona.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(context.tr("已有会话和消息仍保留")),
                    trailing: TextButton(
                      key: Key('restore-persona-${persona.id}'),
                      onPressed: () => _restore(context, ref, persona.id),
                      child: Text(context.tr("恢复")),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    String personaId,
  ) async {
    try {
      await ref.read(restoreChatPersonaProvider)(
        personaId: personaId,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      notifyRepositoryChanged(
        ref,
        areas: const [RepositoryDataArea.chatPersonas],
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr("聊天角色已恢复"))));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyChatError(error))));
      }
    }
  }
}

class ChatPersonaEditorPage extends ConsumerStatefulWidget {
  const ChatPersonaEditorPage({this.personaId, super.key});

  final String? personaId;

  @override
  ConsumerState<ChatPersonaEditorPage> createState() =>
      _ChatPersonaEditorPageState();
}

class _PersonaExampleDraft {
  _PersonaExampleDraft(this.id, {String user = '', String assistant = ''})
    : user = TextEditingController(text: user),
      assistant = TextEditingController(text: assistant);
  final int id;
  final TextEditingController user, assistant;
  void dispose() {
    user.dispose();
    assistant.dispose();
  }
}

class _ChatPersonaEditorPageState extends ConsumerState<ChatPersonaEditorPage> {
  final _name = TextEditingController(), _prompt = TextEditingController();
  final _examples = <_PersonaExampleDraft>[];
  int _nextExample = 0;
  String _avatar = 'blue';
  Uint8List? _photo;
  bool _loaded = false,
      _saving = false,
      _picking = false,
      _dirty = false,
      _leaving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    for (final example in _examples) {
      example.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {
    _dirty = true;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final id = widget.personaId;
    if (id == null) return _editor();
    return ref
        .watch(chatPersonaByIdProvider(id))
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, _) => Scaffold(
            body: _ChatErrorView(message: context.tr("没有找到这个聊天人格。")),
          ),
          data: (persona) {
            if (!_loaded) {
              _loaded = true;
              _name.text = persona.name;
              _prompt.text = persona.unifiedPrompt;
              _avatar = persona.avatarReference ?? 'blue';
              for (final example in persona.presetMessages) {
                _examples.add(
                  _PersonaExampleDraft(
                    _nextExample++,
                    user: example.user,
                    assistant: example.assistant,
                  ),
                );
              }
            }
            return _editor();
          },
        );
  }

  Widget _editor() => PopScope(
    canPop: !_dirty && !_saving && !_picking,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop) await _leave();
    },
    child: BubbleBackground(
      child: Scaffold(
        key: const Key('chat-persona-editor'),
        appBar: AppBar(
          leading: BackButton(onPressed: _leave),
          title: Text(
            widget.personaId == null ? context.tr("添加人格") : context.tr("修改人格"),
          ),
          actions: [
            TextButton(
              key: const Key('save-chat-persona'),
              onPressed: _saving || _picking ? null : _save,
              child: Text(context.tr("保存")),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(
              child: _PersonaAvatar(
                fallbackName: _name.text.isEmpty ? '新' : _name.text,
                avatarReference: _avatar,
                photo: _photo,
                radius: 40,
              ),
            ),
            Center(
              child: TextButton.icon(
                key: const Key('pick-persona-avatar'),
                onPressed: _saving || _picking ? null : _pickAvatar,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(
                  _picking ? context.tr("正在处理图片") : context.tr("选择头像图片"),
                ),
              ),
            ),
            Center(
              child: Wrap(
                key: const Key('persona-avatar-picker'),
                spacing: 12,
                children: [
                  for (final value in const ['blue', 'pink', 'lilac', 'mint'])
                    InkWell(
                      key: Key('persona-avatar-$value'),
                      borderRadius: BorderRadius.circular(24),
                      onTap: _saving || _picking
                          ? null
                          : () {
                              setState(() {
                                _avatar = value;
                                _photo = null;
                              });
                              _changed();
                            },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _avatarColor(context, value),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _avatar == value && _photo == null
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            IbukiGlassSurface(
              strong: true,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    key: const Key('persona-name-field'),
                    controller: _name,
                    enabled: !_saving,
                    onChanged: (_) => _changed(),
                    decoration: InputDecoration(labelText: context.tr("名字")),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    key: const Key('persona-prompt-field'),
                    controller: _prompt,
                    minLines: 5,
                    maxLines: 12,
                    enabled: !_saving,
                    onChanged: (_) => _changed(),
                    decoration: InputDecoration(
                      labelText: context.tr("人格提示词"),
                      hintText: context.tr("写下它的人格、身份和回应习惯……"),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            IbukiGlassSurface(
              child: ExpansionTile(
                key: const Key('persona-examples-section'),
                shape: const Border(),
                collapsedShape: const Border(),
                maintainState: true,
                title: Text(context.tr("语料库（选填）")),
                subtitle: Text(
                  context.tr("预设消息 · {count} 组", {"count": _examples.length}),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Text(
                    context.tr("预设消息会作为生成时的对话示例。"),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  for (final example in _examples)
                    Padding(
                      key: ValueKey('preset-pair-${example.id}'),
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  context.tr("示例 {number}", {
                                    "number": _examples.indexOf(example) + 1,
                                  }),
                                ),
                              ),
                              IconButton(
                                key: Key(
                                  'remove-persona-example-${example.id}',
                                ),
                                tooltip: context.tr("删除这组预设消息"),
                                onPressed: _saving
                                    ? null
                                    : () {
                                        setState(() {
                                          _examples.remove(example);
                                          _dirty = true;
                                        });
                                        // Wait for the text fields to leave the tree before disposing.
                                        WidgetsBinding.instance
                                            .addPostFrameCallback(
                                              (_) => example.dispose(),
                                            );
                                      },
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          ),
                          TextField(
                            key: Key('persona-example-user-${example.id}'),
                            controller: example.user,
                            minLines: 2,
                            maxLines: 5,
                            enabled: !_saving,
                            onChanged: (_) => _changed(),
                            decoration: InputDecoration(
                              labelText: context.tr("用户消息"),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: Key('persona-example-ai-${example.id}'),
                            controller: example.assistant,
                            minLines: 2,
                            maxLines: 7,
                            enabled: !_saving,
                            onChanged: (_) => _changed(),
                            decoration: InputDecoration(
                              labelText: context.tr("AI 回答"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('add-persona-example'),
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _examples.add(_PersonaExampleDraft(_nextExample++));
                            _dirty = true;
                          }),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(context.tr("添加预设消息")),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('save-chat-persona-bottom'),
              onPressed: _saving || _picking ? null : _save,
              child: Text(_saving ? context.tr("保存中") : context.tr("保存人格")),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _pickAvatar() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final bytes = await ref.read(profileAvatarPickerProvider).pick();
      if (mounted && bytes != null) {
        setState(() {
          _photo = bytes;
          _dirty = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取这张图片，请选择有效的图片后重试。');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _picking) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    String? stagedAvatar;
    final assets = ref.read(chatAvatarStoreProvider);
    try {
      final examples = <ChatPresetMessage>[];
      for (final draft in _examples) {
        final user = draft.user.text.trim(),
            assistant = draft.assistant.text.trim();
        if (user.isEmpty && assistant.isEmpty) continue;
        if (user.isEmpty || assistant.isEmpty) {
          throw const DataFormatException('请完整填写每组预设消息的用户消息和 AI 回答。');
        }
        examples.add(ChatPresetMessage(user: user, assistant: assistant));
      }
      if (_name.text.trim().isEmpty) {
        throw const DataFormatException('人格名字不能为空。');
      }
      if (_photo != null) {
        stagedAvatar = await assets.saveAvatar(
          ref.read(entityIdGeneratorProvider).nextId('persona_avatar'),
          _photo!,
        );
      }
      final now = ref.read(utcClockProvider).now();
      final persona = widget.personaId == null
          ? await ref.read(createChatPersonaProvider)(
              id: ref.read(entityIdGeneratorProvider).nextId('persona'),
              name: _name.text,
              personaPrompt: _prompt.text,
              presetMessages: examples,
              avatarReference: stagedAvatar ?? _avatar,
              nowUtc: now,
            )
          : await ref.read(saveChatPersonaProvider)(
              personaId: widget.personaId!,
              name: _name.text,
              personaPrompt: _prompt.text,
              presetMessages: examples,
              avatarReference: stagedAvatar ?? _avatar,
              nowUtc: now,
            );
      stagedAvatar = null;
      if (!mounted) return;
      notifyRepositoryChanged(
        ref,
        areas: const [RepositoryDataArea.chatPersonas],
      );
      context.go(AppRoutes.chatPersona(persona.id));
    } catch (error) {
      if (stagedAvatar != null) {
        try {
          await assets.deleteAsset(stagedAvatar);
        } catch (_) {}
      }
      if (mounted) {
        setState(
          () => _error = error is DataFormatException
              ? error.message
              : _friendlyChatError(error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leave() async {
    if (_saving || _picking || _leaving) return;
    _leaving = true;
    try {
      if (_dirty) {
        final discard = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(dialogContext.tr("放弃未保存的修改？")),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(dialogContext.tr("继续编辑")),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(dialogContext.tr("放弃")),
              ),
            ],
          ),
        );
        if (discard != true || !mounted) return;
      }
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.chat);
      }
    } finally {
      _leaving = false;
    }
  }
}

class SimpleChatSessionPage extends ConsumerStatefulWidget {
  const SimpleChatSessionPage({required this.sessionId, super.key});

  final String sessionId;

  @override
  ConsumerState<SimpleChatSessionPage> createState() =>
      _SimpleChatSessionPageState();
}

class _SimpleChatSessionPageState extends ConsumerState<SimpleChatSessionPage> {
  late final TextEditingController _controller;
  late FollowBottomController _followBottom;
  var _sending = false;
  var _pickingImage = false;
  ChatImage? _pendingImage;
  var _generating = false;
  var _recovering = false;
  var _showRecoveryHint = false;
  Timer? _recoveryHintTimer;
  String? _activeRequestId;
  String? _lastUserMessageId;
  String? _lastRegenerateMessageId;
  String? _lastContinueMessageId;
  String? _activeTargetMessageId;
  String _assistantDraft = '';
  String? _aiError;
  var _pluginNoticeShown = false;
  int? _lastMessageCount;
  Set<String>? _knownMessageIds;
  final _messageArrivals = <String, DateTime>{};
  late final void Function(String requestId) _cancelGeneration;

  ScrollController get _scrollController => _followBottom.scrollController;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController()..addListener(_refreshInput);
    _followBottom = _createFollowBottom(widget.sessionId);
    _cancelGeneration = ref.read(generateChatReplyProvider).cancel;
  }

  @override
  void didUpdateWidget(covariant SimpleChatSessionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId == widget.sessionId) return;
    final requestId = _activeRequestId;
    if (requestId != null) _cancelGeneration(requestId);
    _followBottom.dispose();
    _followBottom = _createFollowBottom(widget.sessionId);
    _pendingImage = null;
    _controller.clear();
    _pickingImage = false;
    _lastMessageCount = null;
    _knownMessageIds = null;
    _messageArrivals.clear();
    _activeRequestId = null;
    _lastUserMessageId = null;
    _lastRegenerateMessageId = null;
    _lastContinueMessageId = null;
    _activeTargetMessageId = null;
    _assistantDraft = '';
    _aiError = null;
    _generating = false;
    _recovering = false;
    _showRecoveryHint = false;
  }

  @override
  void dispose() {
    final requestId = _activeRequestId;
    if (requestId != null) _cancelGeneration(requestId);
    _recoveryHintTimer?.cancel();
    _controller.dispose();
    _followBottom.dispose();
    super.dispose();
  }

  FollowBottomController _createFollowBottom(String sessionId) {
    final controller = FollowBottomController(
      storageId: 'chat-session-$sessionId',
    );
    return controller;
  }

  bool _consumeArrival(String id) {
    final time = _messageArrivals.remove(id);
    return time != null &&
        DateTime.now().difference(time) < const Duration(seconds: 2);
  }

  void _observeMessageList(List<ChatMessage> items) {
    final previousIds = _knownMessageIds;
    _knownMessageIds = items.map((m) => m.id).toSet();
    final now = DateTime.now();
    _messageArrivals.removeWhere(
      (id, time) =>
          now.difference(time) > const Duration(seconds: 2) ||
          !_knownMessageIds!.contains(id),
    );
    if (previousIds != null) {
      for (final item in items.where((m) => !previousIds.contains(m.id))) {
        if (item.role != ChatMessageRole.assistant ||
            (!_generating && _assistantDraft.isEmpty)) {
          _messageArrivals[item.id] = now;
        }
      }
    }
    final previousCount = _lastMessageCount;
    _lastMessageCount = items.length;
    if (previousCount == null) {
      _followBottom.restoreAfterFirstLayout();
    } else if (items.length > previousCount) {
      _followBottom.onContentAppended();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(chatSessionByIdProvider(widget.sessionId));
    return PopScope(
      canPop:
          (_controller.text.trim().isEmpty && _pendingImage == null) ||
          _sending,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _requestLeave();
      },
      child: session.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) =>
            Scaffold(body: _ChatErrorView(message: context.tr("没有找到这个聊天。"))),
        data: (session) {
          if (session.deletedAt != null) {
            return Scaffold(
              body: _ChatErrorView(message: context.tr("这个会话已删除。")),
            );
          }
          final persona = session.personaId == null
              ? null
              : ref.watch(chatPersonaByIdProvider(session.personaId!)).value;
          final displayName = session.title;
          final messages = ref.watch(chatMessageListProvider(session.id));
          final aiLabel = ref
              .watch(chatSessionAiLabelProvider(session.id))
              .value;
          final pluginPanels =
              ref.watch(pluginChatPanelsProvider).value ??
              const <PluginUiContribution>[];
          return BubbleBackground(
            child: Scaffold(
              key: const Key('chat-session-page'),
              resizeToAvoidBottomInset: true,
              appBar: AppBar(
                leading: BackButton(
                  key: const Key('chat-back-button'),
                  onPressed: _requestLeave,
                ),
                titleSpacing: 0,
                title: Row(
                  children: [
                    _PersonaAvatar(
                      persona: persona,
                      fallbackName: displayName,
                      radius: 17,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                actions: [
                  PopupMenuButton<Object>(
                    key: const Key('chat-session-detail-menu'),
                    tooltip: context.tr("更多"),
                    onSelected: (action) {
                      if (action is _ConversationAction) {
                        _handleConversationAction(session, action);
                      } else if (action is PluginUiContribution) {
                        _openPluginPanel(action);
                      }
                    },
                    itemBuilder: (_) => [
                      if (persona != null)
                        PopupMenuItem(
                          value: _ConversationAction.profile,
                          child: Text(context.tr("角色资料")),
                        ),
                      PopupMenuItem(
                        value: _ConversationAction.model,
                        child: Text(context.tr("AI 模型")),
                      ),
                      if (persona != null)
                        PopupMenuItem(
                          value: _ConversationAction.memory,
                          child: Text(context.tr("本聊天记忆")),
                        ),
                      if (persona != null)
                        PopupMenuItem(
                          value: _ConversationAction.newChat,
                          child: Text(context.tr("新聊天")),
                        ),
                      if (persona != null)
                        PopupMenuItem(
                          value: _ConversationAction.sessionList,
                          child: Text(context.tr("会话列表")),
                        ),
                      PopupMenuItem(
                        value: _ConversationAction.rename,
                        child: Text(context.tr("重命名")),
                      ),
                      PopupMenuItem(
                        value: _ConversationAction.delete,
                        child: Text(context.tr("删除")),
                      ),
                      for (final panel in pluginPanels)
                        PopupMenuItem<Object>(
                          key: Key(
                            'chat-plugin-entry-${panel.pluginId}-${panel.id}',
                          ),
                          value: panel,
                          child: Row(
                            children: [
                              const Icon(Icons.extension_rounded, size: 18),
                              const SizedBox(width: 10),
                              Expanded(child: Text(panel.label)),
                              const Icon(Icons.chevron_right_rounded, size: 18),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              body: Column(
                children: [
                  Expanded(
                    key: const Key('simple-chat-session-page'),
                    child: messages.when(
                      skipLoadingOnRefresh: true,
                      skipLoadingOnReload: true,
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, _) =>
                          _ChatErrorView(message: context.tr("消息暂时无法读取。")),
                      data: (items) {
                        _observeMessageList(items);
                        final showDraft =
                            _assistantDraft.isNotEmpty ||
                            _generating ||
                            _aiError != null;
                        if (items.isEmpty && !showDraft) {
                          return _ChatEmptyView(
                            key: const Key('empty-chat-messages-state'),
                            icon: Icons.chat_bubble_outline_rounded,
                            title: context.tr("和 {name} 聊点什么", {
                              "name": displayName,
                            }),
                            message: persona == null
                                ? context.tr("这是未绑定聊天角色的旧会话。")
                                : context.tr("消息会保存在这台手机中。"),
                          );
                        }
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: NotificationListener<ScrollNotification>(
                                onNotification:
                                    _followBottom.handleScrollNotification,
                                child: KeyedSubtree(
                                  key: const Key('instant-message-list'),
                                  child: ListView.builder(
                                    key: PageStorageKey<String>(
                                      'instant-message-list-${session.id}',
                                    ),
                                    controller: _scrollController,
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      16,
                                      12,
                                      12,
                                    ),
                                    itemCount:
                                        items.length + (showDraft ? 1 : 0),
                                    itemBuilder: (_, index) {
                                      if (index < items.length) {
                                        final message = items[index];
                                        if (_generating &&
                                            message.id ==
                                                _activeTargetMessageId) {
                                          return const SizedBox.shrink();
                                        }
                                        final latest =
                                            index == items.length - 1;
                                        final userMessage =
                                            message.role ==
                                                ChatMessageRole.assistant
                                            ? items
                                                  .take(index)
                                                  .where(
                                                    (item) =>
                                                        item.role ==
                                                        ChatMessageRole.user,
                                                  )
                                                  .lastOrNull
                                            : null;
                                        return IbukiEntrance(
                                          key: ValueKey(message.id),
                                          animate: _consumeArrival(message.id),
                                          offset: Offset(
                                            message.role == ChatMessageRole.user
                                                ? 12
                                                : -12,
                                            8,
                                          ),
                                          child: _MessageBubble(
                                            message: message,
                                            persona: persona,
                                            fallbackName: displayName,
                                            onRetryUser:
                                                latest &&
                                                    message.role ==
                                                        ChatMessageRole.user &&
                                                    (_aiError == null ||
                                                        _lastUserMessageId !=
                                                            message.id) &&
                                                    !_sending &&
                                                    !_generating &&
                                                    session.personaId != null
                                                ? () => _generateReply(
                                                    session,
                                                    message.id,
                                                  )
                                                : null,
                                            onContinue:
                                                userMessage == null ||
                                                    !latest ||
                                                    _sending ||
                                                    _generating
                                                ? null
                                                : () => _generateReply(
                                                    session,
                                                    userMessage.id,
                                                    continueMessageId:
                                                        message.id,
                                                  ),
                                            onRegenerate:
                                                userMessage == null ||
                                                    !latest ||
                                                    _sending ||
                                                    _generating
                                                ? null
                                                : () => _generateReply(
                                                    session,
                                                    userMessage.id,
                                                    regenerateMessageId:
                                                        message.id,
                                                  ),
                                            onDelete:
                                                _generating ||
                                                    _sending ||
                                                    !latest
                                                ? null
                                                : () => _deleteMessage(message),
                                          ),
                                        );
                                      }
                                      return IbukiEntrance(
                                        key: ValueKey(
                                          'streaming-${session.id}',
                                        ),
                                        offset: const Offset(-12, 8),
                                        child: _StreamingAssistantBubble(
                                          persona: persona,
                                          fallbackName: displayName,
                                          draft: _assistantDraft,
                                          generating: _generating,
                                          recovering: _showRecoveryHint,
                                          error: _aiError,
                                          onRetry:
                                              _lastUserMessageId == null ||
                                                  _generating
                                              ? null
                                              : () => _generateReply(
                                                  session,
                                                  _lastUserMessageId!,
                                                  regenerateMessageId:
                                                      _lastRegenerateMessageId,
                                                  continueMessageId:
                                                      _lastContinueMessageId,
                                                ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 12,
                              bottom: 8,
                              child: AnimatedBuilder(
                                animation: _followBottom,
                                builder: (context, _) =>
                                    _followBottom.showJumpToBottom
                                    ? JumpToBottomButton(
                                        buttonKey: const Key(
                                          'chat-scroll-to-bottom',
                                        ),
                                        onPressed: _followBottom.scrollToBottom,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: TextButton.icon(
                      key: const Key('chat-ai-provider'),
                      onPressed: _generating
                          ? () => _showMessage(context.tr("请先停止当前生成。"))
                          : () => showAiModelBindingSheet(
                              context: context,
                              ref: ref,
                              scope: AiModelBindingScope.chatSession,
                              entityId: session.id,
                            ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 15),
                      label: Text(
                        persona == null
                            ? context.tr("旧会话 · 未关联聊天角色")
                            : aiLabel ?? context.tr("尚未配置 AI"),
                      ),
                    ),
                  ),
                  if (_pendingImage != null)
                    ChatImageDraft(
                      image: _pendingImage!,
                      onRemove: _sending || _generating
                          ? null
                          : () => setState(() => _pendingImage = null),
                    ),
                  _MessageComposer(
                    hasImage: _pendingImage != null,
                    controller: _controller,
                    sending: _sending || _pickingImage,
                    generating: _generating,
                    onSend: () => _send(session),
                    onStop: _stopGeneration,
                    onTools: () => _openTools(session),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _refreshInput() {
    if (mounted) setState(() {});
  }

  Future<void> _send(ChatSession session) async {
    if (_sending ||
        _pickingImage ||
        _generating ||
        (_controller.text.trim().isEmpty && _pendingImage == null)) {
      return;
    }
    setState(() => _sending = true);
    try {
      final userMessage = await ref.read(sendChatMessageProvider)(
        sessionId: session.id,
        messageId: ref.read(entityIdGeneratorProvider).nextId('message'),
        role: ChatMessageRole.user,
        content: _controller.text,
        image: _pendingImage,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      if (!mounted) return;
      _controller.clear();
      _pendingImage = null;
      notifyRepositoryChanged(
        ref,
        areas: const [
          RepositoryDataArea.chatSessions,
          RepositoryDataArea.chatMessages,
        ],
      );
      _followBottom.onContentAppended();
      _lastUserMessageId = userMessage.id;
      setState(() => _sending = false);
      if (session.personaId != null) {
        await _generateReply(session, userMessage.id, freshUserMessage: true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyChatError(error))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _generateReply(
    ChatSession session,
    String userMessageId, {
    String? continueMessageId,
    String? regenerateMessageId,
    bool freshUserMessage = false,
  }) async {
    if (_generating || session.personaId == null) return;
    final requestId = ref.read(entityIdGeneratorProvider).nextId('ai_request');
    final assistantMessageId = ref
        .read(entityIdGeneratorProvider)
        .nextId('message');
    _syncRecoveryHint(false);
    setState(() {
      _activeRequestId = requestId;
      _lastUserMessageId = userMessageId;
      _lastRegenerateMessageId = regenerateMessageId;
      _lastContinueMessageId = continueMessageId;
      _activeTargetMessageId = regenerateMessageId ?? continueMessageId;
      _assistantDraft = '';
      _aiError = null;
      _generating = true;
      _recovering = false;
      _showRecoveryHint = false;
      _pluginNoticeShown = false;
    });
    try {
      await for (final update in ref.read(generateChatReplyProvider)(
        sessionId: session.id,
        userMessageId: userMessageId,
        requestId: requestId,
        assistantMessageId: assistantMessageId,
        nowUtc: ref.read(utcClockProvider).now(),
        continueMessageId: continueMessageId,
        regenerateMessageId: regenerateMessageId,
        freshUserMessage: freshUserMessage,
      )) {
        if (!mounted || update.requestId != _activeRequestId) continue;
        if (!_pluginNoticeShown && update.pluginNotice != null) {
          _pluginNoticeShown = true;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(update.pluginNotice!)));
        }
        final recovering = update.status == AiDraftStatus.autoRecovering;
        _syncRecoveryHint(recovering);
        setState(() {
          _assistantDraft = update.draft;
          _generating =
              update.status == AiDraftStatus.streaming ||
              update.status == AiDraftStatus.autoRecovering;
          _recovering = recovering;
          if (update.status == AiDraftStatus.cancelled) {
            _assistantDraft = '';
            _recovering = false;
            _aiError = update.savedMessage == null
                ? regenerateMessageId != null || continueMessageId != null
                      ? '生成已停止，原回答已保留。'
                      : '生成已停止，未保存未完成回复。'
                : '生成已停止，已保留中断前内容。';
          }
        });
        _followBottom.onContentAppended();
        if (update.status == AiDraftStatus.completed ||
            update.status == AiDraftStatus.limited ||
            update.status == AiDraftStatus.interrupted ||
            update.status == AiDraftStatus.cancelled ||
            update.status == AiDraftStatus.contentFiltered ||
            update.status == AiDraftStatus.providerError) {
          notifyRepositoryChanged(
            ref,
            areas: const [
              RepositoryDataArea.chatSessions,
              RepositoryDataArea.chatMessages,
            ],
          );
          setState(() {
            _assistantDraft = '';
            if (update.status != AiDraftStatus.cancelled) {
              _aiError = update.savedMessage == null
                  ? update.status == AiDraftStatus.interrupted
                        ? '回复意外中断，可以重试。'
                        : null
                  : null;
            }
            _activeRequestId = null;
            _recovering = false;
            _showRecoveryHint = false;
          });
          _followBottom.onContentAppended();
        }
      }
    } catch (error) {
      if (mounted && _activeRequestId == requestId) {
        _syncRecoveryHint(false);
        setState(() {
          _generating = false;
          _recovering = false;
          _showRecoveryHint = false;
          _assistantDraft = '';
          _aiError = context.tr(friendlyAiError(error));
        });
      }
    } finally {
      if (mounted && _activeRequestId == requestId) {
        _syncRecoveryHint(false);
        notifyRepositoryChanged(
          ref,
          areas: const [RepositoryDataArea.chatMessages],
        );
        setState(() {
          _generating = false;
          _recovering = false;
          _showRecoveryHint = false;
        });
      }
    }
  }

  void _stopGeneration() {
    final requestId = _activeRequestId;
    if (requestId != null) _cancelGeneration(requestId);
  }

  void _syncRecoveryHint(bool recovering) {
    if (!recovering) {
      _recoveryHintTimer?.cancel();
      _recoveryHintTimer = null;
      _showRecoveryHint = false;
      return;
    }
    if (_recovering || _recoveryHintTimer != null) return;
    _recoveryHintTimer = Timer(const Duration(milliseconds: 700), () {
      _recoveryHintTimer = null;
      if (mounted && _recovering) {
        setState(() => _showRecoveryHint = true);
      }
    });
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final preview = message.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr("删除上一条消息？")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.role == ChatMessageRole.user
                  ? dialogContext.tr("你的消息")
                  : dialogContext.tr("AI 回答"),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(preview, maxLines: 4, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            Text(dialogContext.tr("每次只删除一条；再次删除会继续向前。")),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.tr("取消")),
          ),
          FilledButton(
            key: const Key('confirm-delete-chat-message'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.tr("删除")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _generating || _sending) return;
    setState(() => _sending = true);
    try {
      final repository = ref.read(chatRepositoryProvider);
      final expected = message.hasImage
          ? await repository.getMessage(message.id)
          : message;
      if (!mounted || widget.sessionId != message.sessionId) return;
      if (expected.revision != message.revision) {
        throw const DataConflictException('最后一条消息已经变化，请重新操作。');
      }
      await repository.mutateLatestMessage(
        expected: expected,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      _lastUserMessageId = null;
      _lastRegenerateMessageId = null;
      _lastContinueMessageId = null;
      _aiError = null;
      if (!mounted) return;
      notifyRepositoryChanged(
        ref,
        areas: const [
          RepositoryDataArea.chatSessions,
          RepositoryDataArea.chatMessages,
        ],
      );
    } catch (error) {
      if (mounted) _showMessage(_friendlyChatError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage() async {
    if (_pickingImage || _sending || _generating) return;
    final sessionId = widget.sessionId;
    setState(() => _pickingImage = true);
    try {
      final image = await ref.read(chatImagePickerProvider).pick();
      if (!mounted || widget.sessionId != sessionId) return;
      if (image != null) setState(() => _pendingImage = image);
    } catch (_) {
      if (mounted) _showMessage(context.tr("无法处理这张图片，请尝试其他图片。"));
    } finally {
      if (mounted && widget.sessionId == sessionId) {
        setState(() => _pickingImage = false);
      }
    }
  }

  Future<void> _openTools(ChatSession session) async {
    final items =
        ref.read(chatMessageListProvider(session.id)).value ?? <ChatMessage>[];
    final latest = items.lastOrNull;
    final user = latest?.role == ChatMessageRole.assistant
        ? items.where((m) => m.role == ChatMessageRole.user).lastOrNull
        : null;
    final action = await showChatTools(
      context,
      busy: _sending || _pickingImage || _generating,
      canDelete: latest != null,
      canGenerate: user != null && session.personaId != null,
    );
    if (action == null || !mounted) return;
    try {
      switch (action) {
        case ChatTool.image:
          await _pickImage();
        case ChatTool.reasoning:
          await showChatReasoning(context, ref, session.id);
        case ChatTool.summary:
          await context.push(
            '${AppRoutes.chatSessionMemory(session.id)}?view=summary',
          );
        case ChatTool.usage:
          await context.push(AppRoutes.chatSessionUsage(session.id));
        case ChatTool.delete:
          if (latest != null) await _deleteMessage(latest);
        case ChatTool.regenerate:
          if (user != null && latest != null) {
            await _generateReply(
              session,
              user.id,
              regenerateMessageId: latest.id,
            );
          }
        case ChatTool.continueReply:
          if (user != null && latest != null) {
            await _generateReply(
              session,
              user.id,
              continueMessageId: latest.id,
            );
          }
      }
    } catch (error) {
      if (mounted) _showMessage(_friendlyChatError(error));
    }
  }

  Future<void> _handleConversationAction(
    ChatSession session,
    _ConversationAction action,
  ) async {
    switch (action) {
      case _ConversationAction.profile:
        if (session.personaId != null) {
          await context.push(AppRoutes.chatPersona(session.personaId!));
        }
      case _ConversationAction.model:
        if (_generating) {
          _showMessage(context.tr("请先停止当前生成。"));
        } else {
          await showAiModelBindingSheet(
            context: context,
            ref: ref,
            scope: AiModelBindingScope.chatSession,
            entityId: session.id,
          );
        }
      case _ConversationAction.memory:
        if (session.personaId != null) {
          await context.push(AppRoutes.chatSessionMemory(session.id));
        }
      case _ConversationAction.newChat:
        final personaId = session.personaId;
        if (personaId != null && await _confirmDiscardDraft()) {
          if (!mounted || widget.sessionId != session.id) return;
          final created = await ref
              .read(openPersonaChatProvider)
              .createNew(
                personaId: personaId,
                newSessionId: ref
                    .read(entityIdGeneratorProvider)
                    .nextId('chat'),
                nowUtc: ref.read(utcClockProvider).now(),
              );
          if (mounted && widget.sessionId == session.id) {
            context.go(AppRoutes.chatSession(created.id));
          }
        }
      case _ConversationAction.sessionList:
        if (session.personaId != null) {
          await context.push(AppRoutes.chatPersonaSessions(session.personaId!));
        }
      case _ConversationAction.rename:
        await _rename(session);
      case _ConversationAction.delete:
        await _delete(session);
    }
  }

  Future<void> _openPluginPanel(PluginUiContribution contribution) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PluginWebPanelPage(
          contribution: contribution,
          sessionId: widget.sessionId,
        ),
      ),
    );
  }

  Future<void> _rename(ChatSession session) async {
    var draft = session.title;
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('rename-chat-session-dialog'),
        title: Text(dialogContext.tr("重命名会话")),
        content: TextFormField(
          key: const Key('rename-chat-session-field'),
          initialValue: session.title,
          onChanged: (value) => draft = value,
          autofocus: true,
          decoration: InputDecoration(labelText: dialogContext.tr("名称")),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.tr("取消")),
          ),
          FilledButton(
            key: const Key('confirm-rename-chat-session-button'),
            onPressed: () => Navigator.pop(dialogContext, draft),
            child: Text(dialogContext.tr("保存")),
          ),
        ],
      ),
    );
    if (title == null || !mounted) return;
    try {
      await ref.read(renameChatSessionProvider)(
        sessionId: session.id,
        title: title,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      if (mounted) {
        notifyRepositoryChanged(
          ref,
          areas: const [RepositoryDataArea.chatSessions],
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyChatError(error))));
      }
    }
  }

  Future<void> _delete(ChatSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('delete-chat-session-dialog'),
        title: Text(dialogContext.tr("删除会话？")),
        content: Text(dialogContext.tr("聊天记录会保留在已删除会话中，可以恢复。")),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.tr("取消")),
          ),
          FilledButton(
            key: const Key('confirm-delete-chat-session-button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.tr("删除")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(softDeleteChatSessionProvider)(
      sessionId: session.id,
      nowUtc: ref.read(utcClockProvider).now(),
    );
    if (mounted) {
      notifyRepositoryChanged(
        ref,
        areas: const [RepositoryDataArea.chatSessions],
      );
      context.go(AppRoutes.chat);
    }
  }

  Future<bool> _confirmDiscardDraft() async {
    if ((_controller.text.trim().isEmpty && _pendingImage == null) ||
        _sending) {
      return true;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('discard-chat-draft-dialog'),
        title: Text(dialogContext.tr("放弃未发送内容？")),
        content: Text(dialogContext.tr("离开后，尚未发送的文字和图片将丢失。")),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.tr("继续编辑")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.tr("放弃")),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _requestLeave() async {
    if (!await _confirmDiscardDraft() || !mounted) return;
    _stopGeneration();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.chat);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.sending,
    required this.generating,
    required this.onSend,
    required this.onStop,
    required this.onTools,
    this.hasImage = false,
  });

  final TextEditingController controller;
  final bool sending;
  final bool hasImage;
  final bool generating;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onTools;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.bubbleComposerRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            key: const Key('chat-bubble-composer'),
            padding: const EdgeInsets.fromLTRB(8, 7, 7, 7),
            decoration: BoxDecoration(
              color: context.bubbleTheme.glassStrong,
              borderRadius: BorderRadius.circular(
                AppTokens.bubbleComposerRadius,
              ),
              border: Border.all(color: context.bubbleTheme.glassBorder),
              boxShadow: [
                BoxShadow(
                  color: context.bubbleTheme.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  key: const Key('chat-tools-button'),
                  tooltip: context.tr("会话工具"),
                  onPressed: onTools,
                  icon: const Icon(Icons.add_rounded),
                ),
                Expanded(
                  child: TextField(
                    key: const Key('chat-input-field'),
                    controller: controller,
                    enabled: !generating,
                    minLines: 1,
                    maxLines: 4,
                    textAlignVertical: TextAlignVertical.center,
                    strutStyle: const StrutStyle(
                      fontSize: 16,
                      height: 1.3,
                      forceStrutHeight: true,
                    ),
                    decoration: InputDecoration(
                      hintText: context.tr("说点什么……"),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  key: const Key('chat-send-button'),
                  tooltip: generating ? '停止生成' : '发送',
                  onPressed: generating
                      ? onStop
                      : sending || (!hasImage && controller.text.trim().isEmpty)
                      ? null
                      : onSend,
                  icon: generating
                      ? const Icon(Icons.stop_rounded)
                      : sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends ConsumerStatefulWidget {
  const _MessageBubble({
    required this.message,
    required this.persona,
    required this.fallbackName,
    this.onContinue,
    this.onRetryUser,
    this.onRegenerate,
    this.onDelete,
  });

  final ChatMessage message;
  final ChatPersona? persona;
  final String fallbackName;
  final VoidCallback? onContinue;
  final VoidCallback? onRetryUser;
  final VoidCallback? onRegenerate;
  final VoidCallback? onDelete;

  @override
  ConsumerState<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<_MessageBubble> {
  Future<ChatImage?>? _payload;

  ChatMessage get message => widget.message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != message.id ||
        oldWidget.message.revision != message.revision) {
      _load();
    }
  }

  void _load() {
    _payload = message.hasImage
        ? ref.read(chatRepositoryProvider).getMessageImage(message.id)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    if (payload == null) return _buildBubble(context);
    return FutureBuilder<ChatImage?>(
      future: payload,
      builder: (context, snapshot) => _buildBubble(
        context,
        image: snapshot.data,
        awaitingImage: snapshot.connectionState != ConnectionState.done,
      ),
    );
  }

  Widget _buildBubble(
    BuildContext context, {
    ChatImage? image,
    bool awaitingImage = false,
  }) {
    if (message.role == ChatMessageRole.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 28),
        child: Text(
          key: Key('system-message-${message.id}'),
          message.content,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.ibukiColors.textMuted),
        ),
      );
    }
    final user = message.role == ChatMessageRole.user;
    return Padding(
      key: Key('message-bubble-${message.id}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        key: Key('chat-message-${message.id}'),
        mainAxisAlignment: user
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!user) ...[
            _PersonaAvatar(
              persona: widget.persona,
              fallbackName: widget.fallbackName,
              radius: 17,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              key: Key('message-bubble-actions-${message.id}'),
              behavior: HitTestBehavior.opaque,
              onLongPressStart: (details) =>
                  _showMessageMenu(context, details.globalPosition, user: user),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 310),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: user ? null : context.bubbleTheme.messageIncoming,
                  gradient: user
                      ? LinearGradient(
                          colors: [
                            context.bubbleTheme.messageOutgoingStart,
                            context.bubbleTheme.messageOutgoingEnd,
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(user ? 16 : 5),
                    bottomRight: Radius.circular(user ? 5 : 16),
                  ),
                  border: user
                      ? null
                      : Border.all(color: context.bubbleTheme.glassBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (image != null)
                      ChatImageRecord(
                        key: ValueKey('chat-image-record-${message.id}'),
                        image: image,
                      ),
                    if (message.hasImage && image == null)
                      ChatImagePlaceholder(loading: awaitingImage),
                    if (!message.hasImage || image?.userText.isNotEmpty == true)
                      Text(
                        image?.userText ?? message.content,
                        strutStyle: const StrutStyle(
                          fontSize: 16,
                          height: 1.38,
                          forceStrutHeight: true,
                        ),
                        textHeightBehavior: const TextHeightBehavior(
                          applyHeightToFirstAscent: false,
                          applyHeightToLastDescent: false,
                        ),
                        style: TextStyle(
                          color: user
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                          height: 1.38,
                        ),
                      ),
                    if (widget.onRetryUser != null)
                      TextButton(
                        key: Key(
                          message.hasImage
                              ? 'chat-image-retry'
                              : 'chat-text-retry',
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        onPressed: widget.onRetryUser,
                        child: Text(
                          image?.needsRecognition == true
                              ? context.tr("识别并回复")
                              : context.tr("重试回复"),
                        ),
                      ),
                    if (!user && message.finishReason == AiFinishReason.length)
                      _ReplyFinishActions(
                        message: '达到长度限制',
                        onContinue: widget.onContinue,
                      ),
                    if (!user)
                      ChatReplyMemoryBadge(
                        sessionId: message.sessionId,
                        messageId: message.id,
                      ),
                    if (!user &&
                        message.finishReason == AiFinishReason.interrupted)
                      _ReplyFinishActions(
                        message: '回复中断',
                        onContinue: widget.onContinue,
                      ),
                    if (!user &&
                        message.finishReason == AiFinishReason.contentFiltered)
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(context.tr("内容因安全限制未能继续生成。")),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMessageMenu(
    BuildContext context,
    Offset globalPosition, {
    required bool user,
  }) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<_ChatMessageAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _ChatMessageAction.copy,
          child: Text(context.tr("复制")),
        ),
        if (!user)
          PopupMenuItem(
            value: _ChatMessageAction.continueReply,
            enabled: widget.onContinue != null,
            child: Text(context.tr("继续生成")),
          ),
        if (!user)
          PopupMenuItem(
            value: _ChatMessageAction.regenerate,
            enabled: widget.onRegenerate != null,
            child: Text(context.tr("重新生成")),
          ),
        PopupMenuItem(
          value: _ChatMessageAction.delete,
          enabled: widget.onDelete != null,
          child: Text(context.tr("删除")),
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _ChatMessageAction.copy:
        await Clipboard.setData(ClipboardData(text: message.content));
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(context.tr("已复制"))));
        }
      case _ChatMessageAction.continueReply:
        widget.onContinue?.call();
      case _ChatMessageAction.regenerate:
        widget.onRegenerate?.call();
      case _ChatMessageAction.delete:
        widget.onDelete?.call();
    }
  }
}

enum _ChatMessageAction { copy, continueReply, regenerate, delete }

class _ReplyFinishActions extends StatelessWidget {
  const _ReplyFinishActions({required this.message, this.onContinue});

  final String message;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        button: onContinue != null,
        child: InkWell(
          key: const Key('continue-chat-generation'),
          onTap: onContinue,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text.rich(
              TextSpan(
                text: message,
                children: [TextSpan(text: context.tr(" · 继续"))],
              ),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.ibukiColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StreamingAssistantBubble extends StatelessWidget {
  const _StreamingAssistantBubble({
    required this.persona,
    required this.fallbackName,
    required this.draft,
    required this.generating,
    required this.recovering,
    required this.error,
    required this.onRetry,
  });

  final ChatPersona? persona;
  final String fallbackName;
  final String draft;
  final bool generating;
  final bool recovering;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('chat-streaming-reply'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PersonaAvatar(
            persona: persona,
            fallbackName: fallbackName,
            radius: 17,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 310),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: context.bubbleTheme.messageIncoming,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(5),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(color: context.bubbleTheme.glassBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    draft.isNotEmpty
                        ? draft
                        : recovering
                        ? context.tr("连接中断，正在续接……")
                        : generating
                        ? context.tr("正在回复……")
                        : error ?? context.tr("回复失败"),
                    strutStyle: const StrutStyle(
                      fontSize: 16,
                      height: 1.38,
                      forceStrutHeight: true,
                    ),
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                  ),
                  if (generating) ...[
                    const SizedBox(height: 6),
                    const LinearProgressIndicator(minHeight: 2),
                    if (recovering) ...[
                      const SizedBox(height: 6),
                      Text(
                        context.tr("连接中断，正在续接…"),
                        key: const Key('chat-auto-recovering-status'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: context.ibukiColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                  if (error != null && !generating) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      key: const Key('chat-ai-retry-button'),
                      onPressed: onRetry,
                      child: Text(context.tr("重试")),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonaRecentSessions extends ConsumerWidget {
  const _PersonaRecentSessions({required this.persona});

  final ChatPersona persona;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(chatSessionsByPersonaProvider(persona.id));
    return IbukiGlassSurface(
      key: const Key('persona-recent-sessions'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: sessions.when(
        loading: () => ListTile(
          title: Text(context.tr("最近聊天")),
          subtitle: Text(context.tr("正在读取……")),
        ),
        error: (_, _) => ListTile(
          title: Text(context.tr("最近聊天")),
          subtitle: Text(context.tr("暂时无法读取")),
        ),
        data: (items) => Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: Text(context.tr("最近聊天")),
              trailing: items.isEmpty
                  ? null
                  : TextButton(
                      key: const Key('view-all-persona-sessions'),
                      onPressed: () => context.push(
                        AppRoutes.chatPersonaSessions(persona.id),
                      ),
                      child: Text(context.tr("查看全部")),
                    ),
            ),
            for (final session in items.take(3))
              ListTile(
                key: Key('recent-session-${session.id}'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                title: Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_compactTime(session.updatedAt)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.chatSession(session.id)),
              ),
            if (items.isEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(context.tr("还没有聊天。")),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PersonaProfileSections extends StatelessWidget {
  const _PersonaProfileSections({required this.persona});
  final ChatPersona persona;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(context.tr("人格提示词"), style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Text(
        persona.unifiedPrompt.trim().isEmpty
            ? context.tr("尚未填写人格提示词。")
            : persona.unifiedPrompt,
        style: const TextStyle(height: 1.55),
      ),
      if (persona.presetMessages.isNotEmpty)
        ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(
            context.tr("预设消息 · {count} 组", {
              "count": persona.presetMessages.length,
            }),
          ),
          children: [
            for (final pair in persona.presetMessages)
              ListTile(
                title: Text(
                  context.tr("用户消息：{message}", {"message": pair.user}),
                ),
                subtitle: Text(
                  context.tr("AI 回答：{message}", {"message": pair.assistant}),
                ),
              ),
          ],
        ),
    ],
  );
}

class _PersonaAvatar extends StatelessWidget {
  const _PersonaAvatar({
    this.persona,
    this.photo,
    this.fallbackName,
    this.avatarReference,
    this.radius = 23,
  });

  final ChatPersona? persona;
  final Uint8List? photo;
  final String? fallbackName;
  final String? avatarReference;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final name = persona?.name ?? fallbackName ?? '?';
    final reference = persona?.avatarReference ?? avatarReference ?? 'blue';
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _avatarColor(context, reference),
        border: Border.all(color: context.bubbleTheme.glassBorder, width: 2),
        boxShadow: [
          BoxShadow(
            color: context.bubbleTheme.shadow,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: ClipOval(
        child: photo != null
            ? Image.memory(
                photo!,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            : const ['blue', 'pink', 'lilac', 'mint'].contains(reference)
            ? _initial(context, name)
            : Image.file(
                File(reference),
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _initial(context, name),
              ),
      ),
    );
  }

  Widget _initial(BuildContext context, String name) => CircleAvatar(
    radius: radius - 2,
    backgroundColor: _avatarColor(
      context,
      persona?.avatarReference ?? avatarReference ?? 'blue',
    ),
    child: Text(
      name.trim().isEmpty ? '?' : name.trim().characters.first,
      style: TextStyle(
        color: Colors.white,
        fontSize: radius * 0.72,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

Color _avatarColor(BuildContext context, String reference) {
  return switch (reference) {
    'pink' => context.ibukiColors.accent,
    'lilac' => AppTokens.avatarLilac,
    'mint' => AppTokens.avatarMint,
    _ => Theme.of(context).colorScheme.primary,
  };
}

class _ChatEmptyView extends StatelessWidget {
  const _ChatEmptyView({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.ibukiColors.textMuted,
              ),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatErrorView extends StatelessWidget {
  const _ChatErrorView({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 10),
              TextButton(onPressed: onRetry, child: Text(context.tr("重试"))),
            ],
          ],
        ),
      ),
    );
  }
}

enum _ConversationAction {
  profile,
  model,
  memory,
  newChat,
  sessionList,
  rename,
  delete,
}

String _compactTime(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.month}/${local.day}';
}

String _friendlyChatError(Object error) {
  if (error is DataFormatException) return '请检查输入内容。';
  if (error is EntityNotFoundException) return '内容不存在或已经移除。';
  if (error is DataConflictException) return error.message;
  return '操作没有完成，请稍后重试。';
}
