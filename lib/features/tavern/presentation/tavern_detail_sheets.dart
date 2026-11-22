import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/routing/app_routes.dart';
import '../../../application/tavern/tavern_presentation_controller.dart';
import '../../../application/tavern/tavern_generation_runtime.dart';
import '../../../application/tavern/tavern_source_resolver.dart';
import '../../../application/tavern/world_info/world_info_models.dart';
import '../../../domain/tavern/tavern_models.dart';
import 'tavern_widgets.dart';

Future<void> showTavernInspector(
  BuildContext context,
  TavernSessionController c,
  TavernTurnProjection row,
) async {
  await c.loadAttemptDetails(row.selectedAlternative.id);
  if (!context.mounted) return;
  await tavernSheet(
    context,
    '本轮详情',
    DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Prompt'),
              Tab(text: 'Runtime'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    for (final attempt
                        in c.attempts[row.selectedAlternative.id] ??
                            const <TavernGenerationAttempt>[]) ...[
                      Text(
                        '尝试 ${attempt.position + 1}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (c.traces[attempt.id] == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('原始 Prompt Trace 不可用。本轮未在当前应用进程中保留详细记录。'),
                        ),
                      if (c.traces[attempt.id] case final trace?) ...[
                        Text(
                          '上下文额度 ${trace.compilation.maxContextTokens} · 输入估算 ${trace.compilation.usedInputTokens} · 预留输出 ${trace.compilation.reservedOutputTokens}',
                        ),
                        Text(
                          '世界书候选 ${trace.activation.checked} · 激活 ${trace.activation.active}',
                        ),
                        for (final decision in trace.activation.decisions)
                          ListTile(
                            dense: true,
                            title: Text(decision.title),
                            subtitle: Text(
                              tavernActivationReason(decision.reason),
                            ),
                            leading: Icon(
                              decision.active
                                  ? Icons.check_circle_outline
                                  : Icons.circle_outlined,
                            ),
                          ),
                        ExpansionTile(
                          title: const Text('上下文组成'),
                          children: [
                            for (final d in trace.compilation.decisions)
                              ListTile(
                                title: Text(d.sourceId),
                                subtitle: Text(
                                  '${d.estimatedTokens} tokens · ${d.reason.name}',
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                    if ((c.attempts[row.selectedAlternative.id] ?? []).isEmpty)
                      const Text('这条内容没有生成记录。'),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    for (final attempt
                        in c.attempts[row.selectedAlternative.id] ??
                            const <TavernGenerationAttempt>[]) ...[
                      ListTile(
                        title: Text(
                          '尝试 ${attempt.position + 1} · ${attempt.status.name}',
                        ),
                        subtitle: Text(
                          '模型 ${attempt.modelReference ?? '未记录'} · ${attempt.type.name}',
                        ),
                      ),
                      if (attempt.failureReason != null)
                        const Text('本次生成失败；可在本轮选项中重试。'),
                      if (attempt.cancelReason != null) const Text('本次生成已停止。'),
                      if (c.traces[attempt.id] case final trace?)
                        Text(
                          '推理可用性 ${trace.provider.reasoning.name} · 协议 ${trace.provider.protocol.name}',
                        ),
                      ExpansionTile(
                        title: const Text('标识与持久化'),
                        children: [
                          SelectableText(
                            'Turn: ${row.turn.id}\nAlternative: ${row.selectedAlternative.id}\nAttempt: ${attempt.id}\nProvider: ${attempt.providerReference ?? '未记录'}',
                          ),
                          FutureBuilder(
                            future: c.owner.persistence.getWorldInfoJournal(
                              attempt.id,
                            ),
                            builder: (context, snapshot) => Text(
                              snapshot.data == null
                                  ? '世界书 Journal 不可用'
                                  : '世界书对账：${snapshot.data!.outcome.name}',
                            ),
                          ),
                        ],
                      ),
                    ],
                    Text(
                      '内容类型：${row.selectedParts.map((p) => p.kind.name).toSet().join(' / ')}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

String tavernActivationReason(WorldInfoActivationReason reason) =>
    switch (reason) {
      WorldInfoActivationReason.activatedConstant => '常驻设定已激活',
      WorldInfoActivationReason.activatedPrimary => '关键词匹配，已激活',
      WorldInfoActivationReason.activatedRecursive => '递归匹配，已激活',
      WorldInfoActivationReason.activatedSticky => '持续激活',
      WorldInfoActivationReason.disabled => '已禁用',
      WorldInfoActivationReason.scopeMismatch => '不符合当前参与者范围',
      WorldInfoActivationReason.generationMismatch => '不适用于当前操作',
      WorldInfoActivationReason.manualOnly => '需要手动引用',
      WorldInfoActivationReason.primaryNotMatched => '关键词尚未匹配',
      WorldInfoActivationReason.secondaryNotMatched => '附加关键词条件未满足',
      WorldInfoActivationReason.delayPending => '延迟条件尚未满足',
      WorldInfoActivationReason.cooldown => '冷却中',
      WorldInfoActivationReason.probabilityFailed => '本轮未通过概率条件',
      WorldInfoActivationReason.groupLost => '同组其他条目优先',
      _ => '递归条件未满足或已触及保护限制',
    };

class TavernLoreSheet extends ConsumerStatefulWidget {
  const TavernLoreSheet({required this.controller, super.key});
  final TavernSessionController controller;
  @override
  ConsumerState<TavernLoreSheet> createState() => _TavernLoreSheetState();
}

class _TavernLoreSheetState extends ConsumerState<TavernLoreSheet> {
  Future<TavernSourceBundle?>? source;
  @override
  void initState() {
    super.initState();
    _resolve();
  }

  void _resolve() {
    final c = widget.controller;
    source = c.speakerId == null
        ? Future.value(null)
        : c.owner.sources.resolve(c.projection!, c.speakerId!);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final refs = c.projection!.session.metadata['tavernBookReferencesV1'];
    final last = c.projection!.turns.lastOrNull;
    final attempt = last == null
        ? null
        : c.attempts[last.selectedAlternative.id]?.lastOrNull;
    final trace = attempt == null ? null : c.traces[attempt.id];
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        ListTile(
          leading: const Icon(Icons.library_books_outlined),
          title: const Text('引用世界书'),
          onTap: () => _chooseBooks(context),
        ),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('打开世界书库'),
          onTap: () {
            Navigator.pop(context);
            context.push(AppRoutes.worldBookLibrary);
          },
        ),
        if (refs is Map)
          for (final e in refs.entries)
            FutureBuilder(
              future: c.service.worlds.getWorldBook(e.key as String),
              builder: (context, snapshot) => SwitchListTile(
                title: Text(snapshot.data?.name ?? '世界书暂不可用'),
                subtitle: const Text('当前故事引用'),
                value: (e.value as Map)['enabled'] == true,
                onChanged: c.busy
                    ? null
                    : (value) async {
                        await c.service.saveSettings(c.sessionId, {
                          'tavernBookReferencesV1': {
                            ...refs,
                            e.key: {...(e.value as Map), 'enabled': value},
                          },
                          'worldInfoBookOverridesV1': {
                            ...?c
                                    .projection!
                                    .session
                                    .metadata['worldInfoBookOverridesV1']
                                as Map?,
                            e.key: value ? 'enabled' : 'disabled',
                          },
                        });
                        await c.load(initialize: false);
                        if (mounted) setState(_resolve);
                      },
              ),
            ),
        const Divider(),
        Text('当前可用条目', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (trace == null) const Text('尚无本轮原始激活记录；这里展示可用条目，不代表本轮已发送。'),
        FutureBuilder(
          future: source,
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('无法解析关联世界书，请检查资源是否仍存在。');
            if (!snapshot.hasData) return const Text('选择回应角色后可查看可用条目。');
            final entries = snapshot.data!.entries;
            return Column(
              children: [
                for (final e in entries)
                  ListTile(
                    title: Text(e.title),
                    subtitle: Text(
                      _entryReason(
                        trace?.activation.decisions
                            .where((d) => d.identity == e.identity)
                            .firstOrNull,
                        e,
                      ),
                    ),
                    onTap: () => tavernSheet(
                      context,
                      e.title,
                      ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          Text('关键词：${e.primaryKeys.join('、')}'),
                          Text('优先级：${e.priority}'),
                          const SizedBox(height: 16),
                          SelectableText(e.content),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _chooseBooks(BuildContext context) async {
    final c = widget.controller;
    final books = await c.service.worlds.listWorldBookLibrary();
    if (!context.mounted) return;
    final current =
        c.projection!.session.metadata['tavernBookReferencesV1'] as Map? ?? {};
    final available = books.map((book) => book.id).toSet();
    final selected = current.keys.cast<String>().toSet().intersection(
      available,
    );
    await tavernSheet(
      context,
      '引用世界书',
      StatefulBuilder(
        builder: (context, set) => Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  for (final b in books)
                    CheckboxListTile(
                      title: Text(b.name),
                      value: selected.contains(b.id),
                      onChanged: (v) => set(
                        () => v == true
                            ? selected.add(b.id)
                            : selected.remove(b.id),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: c.busy
                    ? null
                    : () async {
                        await c.service.saveSettings(c.sessionId, {
                          'tavernBookReferencesV1': {
                            for (final id in selected)
                              id:
                                  current[id] ??
                                  {'enabled': true, 'priority': 0},
                          },
                        });
                        await c.load(initialize: false);
                        if (context.mounted) Navigator.pop(context);
                      },
                child: const Text('保存引用'),
              ),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(_resolve);
  }
}

String _entryReason(WorldInfoActivationDecision? d, WorldInfoEntry e) =>
    d == null
    ? '${e.enabled ? '启用' : '禁用'} · ${e.constant
          ? '常驻'
          : e.manualOnly
          ? '手动'
          : '关键词'}'
    : tavernActivationReason(d.reason);

Future<void> showTavernLines(
  BuildContext context,
  TavernSessionController c,
) => tavernSheet(
  context,
  '故事线',
  ListView(
    children: [
      for (final line in c.lines)
        ListTile(
          leading: Icon(
            line.id == c.projection?.storyLine.id
                ? Icons.radio_button_checked
                : Icons.radio_button_off,
          ),
          title: Text(line.name),
          subtitle: Text(
            line.parentId == null
                ? '主线'
                : '从 ${c.lines.where((p) => p.id == line.parentId).firstOrNull?.name ?? '另一条故事线'} 分叉',
          ),
          onTap: () async {
            await c.switchLine(line.id);
            if (context.mounted) Navigator.pop(context);
          },
        ),
    ],
  ),
);

Future<void> showTavernTurnMenu(
  BuildContext context,
  TavernSessionController c,
  TavernTurnProjection row,
) async {
  await c.loadAttemptDetails(row.selectedAlternative.id);
  if (!context.mounted) return;
  final attempt = c.attempts[row.selectedAlternative.id]?.lastOrNull;
  final own = row.turn.storyLineId == c.projection?.storyLine.id;
  await tavernSheet(
    context,
    '本轮选项',
    ListView(
      children: [
        if (own && row.turn.role == TavernTurnRole.character && !c.busy) ...[
          if (attempt?.status == TavernGenerationStatus.failed ||
              attempt?.status == TavernGenerationStatus.cancelled)
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('重试回应'),
              onTap: () {
                Navigator.pop(context);
                c.act(TavernGenerationCommandKind.retry, row);
              },
            ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('生成另一种回答'),
            onTap: () {
              Navigator.pop(context);
              c.act(TavernGenerationCommandKind.regenerate, row);
            },
          ),
          ListTile(
            leading: const Icon(Icons.more_horiz),
            title: const Text('续写当前回答'),
            onTap: () {
              Navigator.pop(context);
              c.act(TavernGenerationCommandKind.continueTurn, row);
            },
          ),
        ],
        if (!c.busy)
          ListTile(
            leading: const Icon(Icons.fork_right),
            title: const Text('从这里创建故事线'),
            onTap: () async {
              Navigator.pop(context);
              final name = await tavernNameDialog(context, '新故事线');
              if (name != null) await c.fork(row, name);
            },
          ),
        ListTile(
          leading: const Icon(Icons.manage_search),
          title: const Text('查看本轮详情'),
          onTap: () {
            Navigator.pop(context);
            showTavernInspector(context, c, row);
          },
        ),
      ],
    ),
  );
}
