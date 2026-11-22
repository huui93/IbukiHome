import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/routing/app_routes.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../application/tavern/tavern_presentation_providers.dart';
import '../../../domain/tavern/tavern_models.dart';
import 'tavern_widgets.dart';

class TavernHomePage extends ConsumerStatefulWidget {
  const TavernHomePage({super.key});
  @override
  ConsumerState<TavernHomePage> createState() => _TavernHomePageState();
}

class _TavernHomePageState extends ConsumerState<TavernHomePage> {
  bool archived = false;
  Future<void> _open(TavernSession session) async {
    await context.push(AppRoutes.tavernStory(session.id));
    ref.invalidate(tavernStoriesProvider);
    ref.invalidate(tavernAssetsProvider);
  }

  Future<void> _new(String from) async {
    await context.push('${AppRoutes.newTavernStory}?from=$from');
    ref.invalidate(tavernStoriesProvider);
    ref.invalidate(tavernAssetsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final stories = ref.watch(tavernStoriesProvider(archived));
    final assets = ref.watch(tavernAssetsProvider).value;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(tavernStoriesProvider);
        ref.invalidate(tavernAssetsProvider);
        await ref.read(tavernStoriesProvider(archived).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  archived ? '已归档的故事' : '继续你的故事',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: archived ? '最近故事' : '已归档',
                icon: Icon(
                  archived ? Icons.history : Icons.inventory_2_outlined,
                ),
                onPressed: () => setState(() => archived = !archived),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('tavern-new-story'),
            onPressed: () => tavernSheet(
              context,
              '开始新故事',
              ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('从角色开始'),
                    onTap: () {
                      Navigator.pop(context);
                      _new('character');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.public),
                    title: const Text('从世界开始'),
                    onTap: () {
                      Navigator.pop(context);
                      _new('world');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.create_outlined),
                    title: const Text('从空白故事开始'),
                    onTap: () {
                      Navigator.pop(context);
                      _new('blank');
                    },
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text('新建故事'),
          ),
          const SizedBox(height: 20),
          ...stories.when(
            data: (items) => items.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          Image.asset(
                            'assets/mascot/mascot_idle.png',
                            width: 86,
                            height: 86,
                          ),
                          const SizedBox(height: 16),
                          Text(archived ? '这里还没有归档故事' : '你的第一个故事，从这里开始。'),
                        ],
                      ),
                    ),
                  ]
                : items
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: IbukiGlassSurface(
                            radius: 8,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.session.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      tooltip: '故事选项',
                                      onSelected: (action) =>
                                          _manage(item.session, action),
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'rename',
                                          child: Text('重命名'),
                                        ),
                                        if (!archived)
                                          const PopupMenuItem(
                                            value: 'archive',
                                            child: Text('归档故事'),
                                          ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('删除故事'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Text(
                                  tavernWorldName(
                                    assets,
                                    item.session.worldAssetType,
                                    item.session.worldAssetId,
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    for (final p in item.participants)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TavernAvatar(
                                            p.displayName,
                                            path:
                                                p.kind ==
                                                    TavernParticipantKind
                                                        .character
                                                ? assets?.characters
                                                      .where(
                                                        (c) =>
                                                            c.id == p.entityId,
                                                      )
                                                      .firstOrNull
                                                      ?.avatarReference
                                                : assets?.personas
                                                      .where(
                                                        (c) =>
                                                            c.id == p.entityId,
                                                      )
                                                      .firstOrNull
                                                      ?.avatarReference,
                                          ),
                                          const SizedBox(width: 6),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 160,
                                            ),
                                            child: Text(
                                              '${p.displayName}${p.kind == TavernParticipantKind.persona ? ' · 你' : ''}',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  item.excerpt.isEmpty
                                      ? '故事还未开始'
                                      : item.excerpt,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${item.session.updatedAt.toLocal()}'
                                            .split('.')
                                            .first,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _open(item.session),
                                      icon: const Icon(Icons.play_arrow),
                                      label: const Text('继续故事'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
            loading: () => [const Center(child: CircularProgressIndicator())],
            error: (_, _) => [
              ListTile(
                title: const Text('故事列表暂时无法读取'),
                trailing: IconButton(
                  tooltip: '重试',
                  onPressed: () => ref.invalidate(tavernStoriesProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _manage(TavernSession session, String action) async {
    final service = ref.read(tavernStoryServiceProvider);
    if (action == 'rename') {
      final name = await tavernNameDialog(
        context,
        '重命名故事',
        initial: session.title,
      );
      if (name != null) await service.rename(session.id, name);
    } else if (await tavernConfirm(
      context,
      action == 'delete' ? '删除故事？' : '归档故事？',
      action == 'delete'
          ? '这会删除该故事的故事线、回答和生成记录，不会删除角色和世界资源。'
          : '故事仍会保存在已归档列表中。',
      action == 'delete' ? '删除' : '归档',
    )) {
      if (action == 'delete') {
        await service.repository.deleteSession(session.id);
      } else {
        await service.repository.archiveSession(session.id);
      }
    }
    ref.invalidate(tavernStoriesProvider);
  }
}
