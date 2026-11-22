import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../application/world_roleplay/world_roleplay_providers.dart';
import '../../../domain/common/entity_metadata.dart';
import '../../../domain/world_roleplay/world_roleplay_models.dart';

class WorldBookLibraryPage extends ConsumerStatefulWidget {
  const WorldBookLibraryPage({super.key});

  @override
  ConsumerState<WorldBookLibraryPage> createState() =>
      _WorldBookLibraryPageState();
}

class _WorldBookLibraryPageState extends ConsumerState<WorldBookLibraryPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(worldRoleplayRepositoryProvider);
    ref.watch(worldRoleplayRevisionProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTokens.spacingM),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('world-book-library-search'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: '搜索书名、标题、关键词或正文',
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(width: AppTokens.spacingS),
              IconButton.filledTonal(
                key: const Key('create-library-world-book'),
                tooltip: '新建世界书',
                onPressed: () => _editBook(),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<WorldBook>>(
            future: repository.listWorldBookLibrary(query: _query),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final books = snapshot.data!;
              if (books.isEmpty) {
                return const Center(child: Text('世界书库还是空的。'));
              }
              return ListView.builder(
                key: const Key('world-book-library-list'),
                padding: const EdgeInsets.all(AppTokens.spacingM),
                itemCount: books.length,
                itemBuilder: (context, index) {
                  final book = books[index];
                  return ListTile(
                    key: ValueKey(book.id),
                    leading: const Icon(Icons.auto_stories_outlined),
                    title: Text(book.name),
                    subtitle: Text(
                      book.worldId == null ? '独立世界书' : '已有世界设定 · 可跨世界引用',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) => switch (action) {
                        'edit' => _editBook(book),
                        'copy' => _copyBook(book),
                        'delete' => _deleteBook(book),
                        _ => Future<void>.value(),
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('重命名')),
                        PopupMenuItem(value: 'copy', child: Text('复制')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                    onTap: () => _showEntries(book),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _editBook([WorldBook? book]) async {
    final controller = TextEditingController(text: book?.name ?? '');
    final saved = await _textDialog(
      title: book == null ? '新建世界书' : '编辑世界书',
      controller: controller,
      label: '名称',
    );
    if (saved && mounted && controller.text.trim().isNotEmpty) {
      final repository = ref.read(worldRoleplayRepositoryProvider);
      final now = ref.read(utcClockProvider).now();
      await repository.upsertWorldBook(
        book?.copyWith(
              entity: _next(book.entity, now),
              name: controller.text.trim(),
            ) ??
            WorldBook(
              entity: _entity(ref, 'world_book'),
              name: controller.text.trim(),
            ),
      );
      notifyWorldRoleplayChanged(ref);
    }
    controller.dispose();
  }

  Future<void> _copyBook(WorldBook book) async {
    final repository = ref.read(worldRoleplayRepositoryProvider);
    final copy = WorldBook(
      entity: _entity(ref, 'world_book'),
      name: '${book.name} · 副本',
      metadata: {...book.metadata, 'copiedFrom': book.id},
    );
    await repository.upsertWorldBook(copy);
    for (final entry in await repository.listLoreEntries(book.id)) {
      await repository.upsertLoreEntry(
        entry.copyWith(
          entity: _entity(ref, 'lore_entry'),
          worldBookId: copy.id,
        ),
      );
    }
    notifyWorldRoleplayChanged(ref);
  }

  Future<void> _deleteBook(WorldBook book) async {
    final repository = ref.read(worldRoleplayRepositoryProvider);
    final references = await repository.countWorldBookReferences(book.id);
    if (!mounted) return;
    if (references > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('这本世界书仍有 $references 个引用，请先解除引用。')),
      );
      return;
    }
    final confirmed = await _confirm('删除“${book.name}”及其中全部设定？');
    if (!confirmed) return;
    await repository.deleteWorldBook(book.id);
    notifyWorldRoleplayChanged(ref);
  }

  Future<void> _showEntries(WorldBook book) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _WorldBookEntrySheet(book: book),
    );
    if (mounted) setState(() {});
  }

  Future<bool> _textDialog({
    required String title,
    required TextEditingController controller,
    required String label,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              decoration: InputDecoration(labelText: label),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _confirm(String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认删除'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;
}

class _WorldBookEntrySheet extends ConsumerStatefulWidget {
  const _WorldBookEntrySheet({required this.book});
  final WorldBook book;

  @override
  ConsumerState<_WorldBookEntrySheet> createState() =>
      _WorldBookEntrySheetState();
}

class _WorldBookEntrySheetState extends ConsumerState<_WorldBookEntrySheet> {
  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(loreEntryListProvider(widget.book.id));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .88,
        child: Column(
          children: [
            ListTile(
              title: Text(widget.book.name),
              subtitle: const Text('每条设定可独立启用与激活'),
              trailing: IconButton.filledTonal(
                tooltip: '新增设定',
                onPressed: () => _editEntry(),
                icon: const Icon(Icons.add_rounded),
              ),
            ),
            Expanded(
              child: entries.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const Center(child: Text('设定读取失败。')),
                data: (items) => ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return SwitchListTile(
                      value: item.enabled,
                      title: Text(item.title),
                      subtitle: Text(
                        '${item.activationMode.name} · priority ${item.priority}',
                      ),
                      onChanged: (value) => _save(
                        item.copyWith(
                          entity: _next(
                            item.entity,
                            ref.read(utcClockProvider).now(),
                          ),
                          enabled: value,
                        ),
                      ),
                      secondary: IconButton(
                        tooltip: '编辑',
                        onPressed: () => _editEntry(item),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editEntry([LoreEntry? entry]) async {
    final title = TextEditingController(text: entry?.title ?? '');
    final content = TextEditingController(text: entry?.content ?? '');
    final keywords = TextEditingController(
      text: entry?.keywords.join(', ') ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.all(AppTokens.spacingM),
        title: Text(entry == null ? '新增设定' : '编辑设定'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '标题'),
                ),
                TextField(
                  controller: keywords,
                  decoration: const InputDecoration(labelText: '关键词，逗号分隔'),
                ),
                TextField(
                  key: const Key('library-lore-content'),
                  controller: content,
                  minLines: 14,
                  maxLines: 26,
                  decoration: const InputDecoration(labelText: '内容'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true && mounted && title.text.trim().isNotEmpty) {
      final now = ref.read(utcClockProvider).now();
      await _save(
        entry?.copyWith(
              entity: _next(entry.entity, now),
              title: title.text.trim(),
              content: content.text.trim(),
              keywords: _keywords(keywords.text),
            ) ??
            LoreEntry(
              entity: _entity(ref, 'lore_entry'),
              worldBookId: widget.book.id,
              title: title.text.trim(),
              content: content.text.trim(),
              keywords: _keywords(keywords.text),
            ),
      );
    }
    title.dispose();
    content.dispose();
    keywords.dispose();
  }

  Future<void> _save(LoreEntry entry) async {
    await ref.read(worldRoleplayRepositoryProvider).upsertLoreEntry(entry);
    notifyWorldRoleplayChanged(ref);
  }
}

EntityMetadata _entity(WidgetRef ref, String prefix) {
  final now = ref.read(utcClockProvider).now();
  return EntityMetadata(
    id: ref.read(entityIdGeneratorProvider).nextId(prefix),
    createdAt: now,
    updatedAt: now,
    revision: 1,
  );
}

EntityMetadata _next(EntityMetadata entity, DateTime now) =>
    entity.copyWith(updatedAt: now, revision: entity.revision + 1);

List<String> _keywords(String value) => value
    .split(RegExp(r'[,，\n]'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toSet()
    .toList();
