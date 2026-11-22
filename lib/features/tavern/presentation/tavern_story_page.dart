import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/routing/app_routes.dart';
import '../../../app/widgets/bubble_background.dart';
import '../../../application/tavern/tavern_generation_orchestrator.dart';
import '../../../application/tavern/tavern_presentation_controller.dart';
import '../../../application/tavern/tavern_presentation_providers.dart';
import '../../../application/tavern/tavern_story_service.dart';
import '../../../domain/tavern/tavern_models.dart';
import 'tavern_widgets.dart';
import 'tavern_transcript.dart';
import 'tavern_detail_sheets.dart';

class TavernStoryPage extends ConsumerStatefulWidget {
  const TavernStoryPage({required this.sessionId, super.key});
  final String sessionId;
  @override
  ConsumerState<TavernStoryPage> createState() => _TavernStoryPageState();
}

class _TavernStoryPageState extends ConsumerState<TavernStoryPage> {
  final scaffold = GlobalKey<ScaffoldState>(),
      transcript = GlobalKey<TavernTranscriptState>();
  final input = TextEditingController();
  late final TavernSessionController controller;
  bool leaving = false;
  @override
  void initState() {
    super.initState();
    controller = ref.read(tavernSessionControllerProvider(widget.sessionId));
    if (controller.projection == null) unawaited(controller.load());
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (leaving) return;
    if (controller.busy) {
      final stop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('故事正在回应'),
          content: const Text('现在返回大厅将停止本轮生成。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续等待'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('停止并返回'),
            ),
          ],
        ),
      );
      if (stop != true) return;
    }
    leaving = true;
    await transcript.currentState?.savePosition();
    if (controller.busy) await controller.stop();
    ref.invalidate(tavernStoriesProvider);
    if (mounted) context.go(AppRoutes.tavern);
  }

  Future<void> _operation(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tavernFriendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the provider alive for the entire route, not just the initial read.
    ref.watch(tavernSessionControllerProvider(widget.sessionId));
    final assets = ref.watch(tavernAssetsProvider).value;
    String? avatar(TavernParticipant? p) =>
        p?.kind == TavernParticipantKind.character
        ? assets?.characters
              .where((c) => c.id == p?.entityId)
              .firstOrNull
              ?.avatarReference
        : assets?.personas
              .where((c) => c.id == p?.entityId)
              .firstOrNull
              ?.avatarReference;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final data = controller.projection;
        final scene = data?.session.metadata['tavernSceneV1'] as Map? ?? {};
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (scaffold.currentState?.isDrawerOpen == true) {
              scaffold.currentState!.closeDrawer();
              return;
            }
            if (MediaQuery.viewInsetsOf(context).bottom > 0) {
              FocusManager.instance.primaryFocus?.unfocus();
              return;
            }
            _leave();
          },
          child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            key: scaffold,
            appBar: AppBar(
              backgroundColor: Theme.of(context).colorScheme.surface,
              title: InkWell(
                onTap: () => _scene(scene),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scene['name'] as String? ??
                          data?.session.title ??
                          'Tavern',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${data?.session.title ?? ''}${scene['timeText'] is String && (scene['timeText'] as String).isNotEmpty ? ' · ${scene['timeText']}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  tooltip: '故事线',
                  icon: const Icon(Icons.fork_right),
                  onPressed: data == null
                      ? null
                      : () => showTavernLines(context, controller),
                ),
              ],
            ),
            drawer: Drawer(
              child: SafeArea(
                child: ListView(
                  children: [
                    ListTile(
                      title: Text(data?.session.title ?? 'Tavern'),
                      subtitle: Text(
                        tavernWorldName(
                          assets,
                          data?.session.worldAssetType,
                          data?.session.worldAssetId,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: data == null
                          ? null
                          : () {
                              scaffold.currentState?.closeDrawer();
                              _world(assets);
                            },
                    ),
                    ListTile(
                      key: const Key('tavern-return-home'),
                      leading: const Icon(Icons.arrow_back),
                      title: const Text('返回 Tavern 大厅'),
                      onTap: () {
                        scaffold.currentState?.closeDrawer();
                        _leave();
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.play_arrow),
                      title: const Text('继续故事'),
                      onTap: () => scaffold.currentState?.closeDrawer(),
                    ),
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: const Text('我的角色'),
                      onTap: () {
                        scaffold.currentState?.closeDrawer();
                        _participant(
                          controller.participants
                              .where(
                                (p) => p.kind == TavernParticipantKind.persona,
                              )
                              .firstOrNull,
                          assets,
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: const Text('登场角色'),
                      onTap: () {
                        scaffold.currentState?.closeDrawer();
                        _cast(assets);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: const Text('当前场景'),
                      onTap: () {
                        scaffold.currentState?.closeDrawer();
                        _scene(scene);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.library_books_outlined),
                      title: const Text('故事设定 · 世界书'),
                      onTap: data == null
                          ? null
                          : () {
                              scaffold.currentState?.closeDrawer();
                              tavernSheet(
                                context,
                                '世界书',
                                TavernLoreSheet(controller: controller),
                              );
                            },
                    ),
                    ListTile(
                      leading: const Icon(Icons.fork_right),
                      title: const Text('故事线'),
                      onTap: data == null
                          ? null
                          : () {
                              scaffold.currentState?.closeDrawer();
                              showTavernLines(context, controller);
                            },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.auto_awesome_outlined),
                      title: const Text('回应模型'),
                      onTap: data == null
                          ? null
                          : () {
                              scaffold.currentState?.closeDrawer();
                              _model();
                            },
                    ),
                    ListTile(
                      leading: const Icon(Icons.edit_note),
                      title: const Text('故事补充指令'),
                      onTap: data == null ? null : _instructions,
                    ),
                    ListTile(
                      leading: const Icon(Icons.refresh),
                      title: const Text('重试恢复'),
                      onTap: controller.busy
                          ? null
                          : () {
                              scaffold.currentState?.closeDrawer();
                              controller.retryRecovery();
                            },
                    ),
                    ListTile(
                      leading: const Icon(Icons.extension_outlined),
                      title: const Text('插件管理'),
                      onTap: () {
                        scaffold.currentState?.closeDrawer();
                        context.push(AppRoutes.plugins);
                      },
                    ),
                  ],
                ),
              ),
            ),
            body: BubbleBackground(
              child: SafeArea(
                child: controller.loading
                    ? const Center(child: CircularProgressIndicator())
                    : data == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('故事暂时无法打开'),
                            TextButton(
                              onPressed: () => controller.load(),
                              child: const Text('重试'),
                            ),
                            TextButton(
                              onPressed: _leave,
                              child: const Text('返回大厅'),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          SizedBox(
                            height: 64,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              children: [
                                for (final p in controller.participants)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: TextButton(
                                      key: Key('tavern-cast-${p.id}'),
                                      onPressed: () => _participant(p, assets),
                                      style: TextButton.styleFrom(
                                        backgroundColor:
                                            p.id == controller.speakerId
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .secondaryContainer
                                                  .withValues(alpha: .55)
                                            : null,
                                      ),
                                      child: Row(
                                        children: [
                                          TavernAvatar(
                                            p.displayName,
                                            path: avatar(p),
                                          ),
                                          const SizedBox(width: 6),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 140,
                                            ),
                                            child: Text(
                                              '${p.displayName}${p.kind == TavernParticipantKind.persona ? ' · 你' : ''}',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: TavernTranscript(
                              key: transcript,
                              controller: controller,
                              reading: ref.read(tavernReadingStoreProvider),
                              onTurnMenu: (r) => _operation(
                                () =>
                                    showTavernTurnMenu(context, controller, r),
                              ),
                              avatarPath: avatar,
                            ),
                          ),
                          if (controller.error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      controller.error!,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '回应模型',
                                    onPressed: _model,
                                    icon: const Icon(Icons.tune),
                                  ),
                                ],
                              ),
                            ),
                          ValueListenableBuilder(
                            valueListenable: controller.live,
                            builder: (context, live, _) => controller.busy
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(switch (live.phase) {
                                          TavernOrchestrationPhase.preparing ||
                                          TavernOrchestrationPhase.compiling =>
                                            '正在准备故事…',
                                          TavernOrchestrationPhase.connecting =>
                                            '正在连接模型…',
                                          TavernOrchestrationPhase.streaming =>
                                            '角色正在回应…',
                                          TavernOrchestrationPhase.finalizing =>
                                            '正在保存回应…',
                                          _ => '正在收束本轮…',
                                        }),
                                      ],
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                IconButton(
                                  tooltip: '回应角色与模型',
                                  onPressed: _composerMenu,
                                  icon: const Icon(Icons.more_horiz),
                                ),
                                Expanded(
                                  child: TextField(
                                    key: const Key('tavern-composer'),
                                    controller: input,
                                    minLines: 1,
                                    maxLines: 5,
                                    decoration: const InputDecoration(
                                      hintText: '输入行动或台词…',
                                      filled: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                if (controller.busy)
                                  IconButton.filledTonal(
                                    key: const Key('tavern-stop'),
                                    tooltip: '停止',
                                    onPressed: () =>
                                        _operation(controller.stop),
                                    icon: const Icon(Icons.stop),
                                  )
                                else
                                  IconButton.filled(
                                    key: const Key('tavern-send'),
                                    tooltip: '发送',
                                    onPressed: () => _send(),
                                    icon: const Icon(Icons.arrow_upward),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _send() {
    final sent = input.text;
    if (sent.trim().isEmpty) return;
    unawaited(
      controller.send(
        sent,
        onAccepted: () {
          if (mounted && input.text == sent) input.clear();
        },
      ),
    );
  }

  Future<void> _model() async {
    if (controller.busy) return;
    await tavernSheet(
      context,
      '回应模型',
      TavernModelPicker(
        onSelected: (v) => _operation(() async {
          await controller.service.saveSettings(widget.sessionId, {
            'tavernBindingV1': v,
          });
          await controller.load(initialize: false);
        }),
      ),
    );
  }

  void _composerMenu() => tavernSheet(
    context,
    '本轮回应',
    ListView(
      children: [
        for (final p in controller.participants.where(
          (p) => p.kind == TavernParticipantKind.character,
        ))
          ListTile(
            leading: Icon(
              p.id == controller.speakerId
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            title: Text(p.displayName),
            onTap: () {
              controller.selectSpeaker(p.id);
              Navigator.pop(context);
            },
          ),
        ListTile(
          title: const Text('回应模型'),
          leading: const Icon(Icons.auto_awesome_outlined),
          onTap: () {
            Navigator.pop(context);
            _model();
          },
        ),
      ],
    ),
  );
  Future<void> _scene(Map scene) => tavernSheet(
    context,
    scene['name'] as String? ?? '当前场景',
    ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(scene['timeText'] as String? ?? ''),
        const SizedBox(height: 12),
        SelectableText(scene['description'] as String? ?? '尚未填写场景描述'),
      ],
    ),
  );
  Future<void> _world(TavernAssetCatalog? assets) {
    final session = controller.projection!.session;
    final world = assets?.worlds
        .where(
          (w) =>
              w.type == session.worldAssetType && w.id == session.worldAssetId,
        )
        .firstOrNull;
    return tavernSheet(
      context,
      tavernWorldName(assets, session.worldAssetType, session.worldAssetId),
      ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SelectableText(
            world?.description ??
                (session.worldAssetId == null
                    ? '这个故事没有关联世界设定。'
                    : '关联世界暂不可用。故事记录仍然保留。'),
          ),
        ],
      ),
    );
  }

  Future<void> _instructions() async {
    scaffold.currentState?.closeDrawer();
    final text = TextEditingController(
      text:
          controller.projection?.session.metadata['tavernSessionInstructionsV1']
              as String? ??
          '',
    );
    await tavernSheet(
      context,
      '故事补充指令',
      Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: TextField(
                controller: text,
                expands: true,
                minLines: null,
                maxLines: null,
                decoration: const InputDecoration(labelText: '补充指令'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: controller.busy
                  ? null
                  : () async {
                      await controller.service.saveSettings(widget.sessionId, {
                        'tavernSessionInstructionsV1': text.text,
                      });
                      await controller.load(initialize: false);
                      if (mounted && context.mounted) Navigator.pop(context);
                    },
              child: const Text('保存'),
            ),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    text.dispose();
  }

  Future<void> _participant(
    TavernParticipant? p,
    TavernAssetCatalog? assets,
  ) async {
    if (p == null) return;
    final character = assets?.characters
        .where((c) => c.id == p.entityId)
        .firstOrNull;
    final persona = assets?.personas
        .where((c) => c.id == p.entityId)
        .firstOrNull;
    await tavernSheet(
      context,
      p.displayName,
      ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: TavernAvatar(
              p.displayName,
              path: character?.avatarReference ?? persona?.avatarReference,
              size: 80,
            ),
          ),
          const SizedBox(height: 16),
          if (p.kind == TavernParticipantKind.persona) const Text('这是你正在扮演的人。'),
          SelectableText(
            character?.content ?? persona?.description ?? '关联角色暂不可用',
          ),
          if (p.kind == TavernParticipantKind.character)
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('让这个角色回应'),
              onTap: () {
                controller.selectSpeaker(p.id);
                Navigator.pop(context);
              },
            ),
          if (character != null)
            ListTile(
              title: const Text('查看完整角色'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.projectCharacters(character.projectId));
              },
            ),
        ],
      ),
    );
  }

  Future<void> _cast(TavernAssetCatalog? assets) => tavernSheet(
    context,
    '登场角色',
    ListView(
      children: [
        for (final p in controller.participants)
          ListTile(
            title: Text(p.displayName),
            onTap: () => _participant(p, assets),
          ),
        ListTile(
          leading: const Icon(Icons.person_add_outlined),
          title: const Text('添加角色'),
          onTap: () async {
            final catalog = await ref.read(tavernAssetsProvider.future);
            if (!mounted) return;
            await tavernSheet(
              context,
              '选择角色',
              ListView(
                children: [
                  for (final c in catalog.characters)
                    if (!controller.participants.any((p) => p.entityId == c.id))
                      ListTile(
                        title: Text(c.name),
                        onTap: () async {
                          final navigator = Navigator.of(context);
                          await controller.service.repository.addParticipant(
                            TavernParticipant(
                              id: controller.service.ids.nextId(
                                'tavern_character',
                              ),
                              sessionId: widget.sessionId,
                              kind: TavernParticipantKind.character,
                              entityId: c.id,
                              displayName: c.name,
                              position:
                                  controller.participants
                                      .map((p) => p.position)
                                      .fold<int>(-1, (a, b) => a > b ? a : b) +
                                  1,
                            ),
                          );
                          await controller.load(initialize: false);
                          if (mounted && navigator.mounted) navigator.pop();
                        },
                      ),
                ],
              ),
            );
          },
        ),
      ],
    ),
  );
}
