import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/routing/app_routes.dart';
import '../../../app/widgets/bubble_background.dart';
import '../../../application/tavern/tavern_presentation_providers.dart';
import '../../../application/tavern/tavern_story_service.dart';
import '../../../application/tavern/tavern_presentation_controller.dart';
import 'tavern_widgets.dart';

class TavernCreationPage extends ConsumerStatefulWidget {
  const TavernCreationPage({this.from = 'character', super.key});
  final String from;
  @override
  ConsumerState<TavernCreationPage> createState() => _TavernCreationPageState();
}

class _TavernCreationPageState extends ConsumerState<TavernCreationPage> {
  final title = TextEditingController(),
      name = TextEditingController(),
      identity = TextEditingController(),
      scene = TextEditingController(text: '初始场景'),
      description = TextEditingController(),
      time = TextEditingController();
  int step = 0;
  String? persona;
  final cast = <String>{}, books = <String>{};
  TavernWorldChoice? world;
  Map<String, Object?> binding = {};
  bool saving = false;
  String? error;
  @override
  void dispose() {
    for (final c in [title, name, identity, scene, description, time]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(tavernAssetsProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('开始新故事'),
      ),
      body: BubbleBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Expanded(
                        child: Text(
                          ['1 我的角色', '2 登场角色', '3 故事世界'][i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: step == i
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: step == i
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: assets.when(
                  data: (data) => ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      if (step == 0) ...[
                        TextField(
                          key: const Key('tavern-story-title'),
                          controller: title,
                          decoration: const InputDecoration(labelText: '故事名字'),
                        ),
                        const SizedBox(height: 16),
                        for (final p in data.personas)
                          ListTile(
                            onTap: () => setState(() => persona = p.id),
                            trailing: Icon(
                              persona == p.id
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                            ),
                            title: Text(p.name),
                            leading: TavernAvatar(
                              p.name,
                              path: p.avatarReference,
                            ),
                            subtitle: Text(
                              p.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ListTile(
                          trailing: Icon(
                            persona == null
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          onTap: () => setState(() => persona = null),
                          title: const Text('创建我的角色'),
                        ),
                        if (persona == null) ...[
                          TextField(
                            key: const Key('tavern-persona-name'),
                            controller: name,
                            decoration: const InputDecoration(
                              labelText: '我的角色名字',
                            ),
                          ),
                          TextField(
                            controller: identity,
                            minLines: 2,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              labelText: '公开身份 / 简介',
                            ),
                          ),
                        ],
                      ],
                      if (step == 1) ...[
                        Text(
                          '和谁一起开始？',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (data.characters.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text('还没有角色卡，可以新建或导入。'),
                          ),
                        for (final c in data.characters)
                          CheckboxListTile(
                            value: cast.contains(c.id),
                            onChanged: (v) => setState(
                              () => v == true
                                  ? cast.add(c.id)
                                  : cast.remove(c.id),
                            ),
                            secondary: TavernAvatar(
                              c.name,
                              path: c.avatarReference,
                            ),
                            title: Text(c.name),
                            subtitle: Text(
                              c.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ListTile(
                          leading: const Icon(Icons.person_add_outlined),
                          title: const Text('新建角色'),
                          onTap: _createCharacter,
                        ),
                        if (cast.isEmpty) const Text('也可以先保存空白故事，添加角色后再开始回应。'),
                      ],
                      if (step == 2) ...[
                        DropdownButtonFormField<String>(
                          initialValue: world?.key,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: '故事世界'),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('自由故事'),
                            ),
                            for (final w in data.worlds)
                              DropdownMenuItem(
                                value: w.key,
                                child: Text(
                                  w.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (key) => setState(
                            () => world = data.worlds
                                .where((w) => w.key == key)
                                .firstOrNull,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: scene,
                          decoration: const InputDecoration(labelText: '场景名字'),
                        ),
                        TextField(
                          controller: description,
                          minLines: 3,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            labelText: '故事从哪里开始',
                          ),
                        ),
                        TextField(
                          controller: time,
                          decoration: const InputDecoration(
                            labelText: '时间（可选）',
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.auto_awesome_outlined),
                          title: Text(binding['model'] as String? ?? '选择回应模型'),
                          subtitle: const Text('只用于这个故事'),
                          onTap: () => tavernSheet(
                            context,
                            '回应模型',
                            TavernModelPicker(
                              onSelected: (v) => setState(() => binding = v),
                            ),
                          ),
                        ),
                        ExpansionTile(
                          title: const Text('故事设定 · 世界书'),
                          children: [
                            for (final b in data.books)
                              CheckboxListTile(
                                value: books.contains(b.id),
                                title: Text(b.name),
                                onChanged: (v) => setState(
                                  () => v == true
                                      ? books.add(b.id)
                                      : books.remove(b.id),
                                ),
                              ),
                            ListTile(
                              title: const Text('打开世界书库'),
                              leading: const Icon(Icons.library_books_outlined),
                              onTap: () async {
                                await context.push(AppRoutes.worldBookLibrary);
                                ref.invalidate(tavernAssetsProvider);
                              },
                            ),
                          ],
                        ),
                      ],
                      ListTile(
                        leading: const Icon(Icons.file_upload_outlined),
                        title: Text(
                          step == 0
                              ? '导入我的角色'
                              : step == 1
                              ? '导入角色卡'
                              : '导入世界书',
                        ),
                        onTap: () async {
                          await context.push(
                            '${AppRoutes.sillyTavernImport}?kind=${step == 0
                                ? 'persona'
                                : step == 1
                                ? 'character'
                                : 'lorebook'}&return=1',
                          );
                          ref.invalidate(tavernAssetsProvider);
                        },
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                  error: (_, _) => const Center(child: Text('资源暂时无法读取')),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (step > 0)
                      TextButton(
                        onPressed: saving ? null : () => setState(() => step--),
                        child: const Text('上一步'),
                      ),
                    const Spacer(),
                    FilledButton(
                      key: const Key('tavern-create-next'),
                      onPressed: saving ? null : _next,
                      child: Text(
                        saving
                            ? '正在保存…'
                            : step == 2
                            ? '开始故事'
                            : '下一步',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createCharacter() async {
    final n = await tavernNameDialog(context, '新建角色');
    if (n == null || !mounted) return;
    final content = await tavernNameDialog(context, '角色简介');
    if (content == null) return;
    final c = await ref
        .read(tavernStoryServiceProvider)
        .createCharacter(n, content);
    if (!mounted) return;
    setState(() => cast.add(c.id));
    ref.invalidate(tavernAssetsProvider);
  }

  Future<void> _next() async {
    if (step == 0 &&
        (title.text.trim().isEmpty ||
            (persona == null && name.text.trim().isEmpty))) {
      setState(() => error = '请填写故事名字与我的角色名字。');
      return;
    }
    if (step < 2) {
      setState(() {
        step++;
        error = null;
      });
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final saved = await ref
          .read(tavernStoryServiceProvider)
          .createStory(
            TavernStoryDraft(
              title: title.text,
              characterIds: cast,
              personaId: persona,
              personaName: name.text,
              personaDescription: identity.text,
              world: world,
              bookIds: books,
              sceneName: scene.text,
              sceneDescription: description.text,
              timeText: time.text,
              binding: binding,
            ),
          );
      ref.invalidate(tavernStoriesProvider);
      ref.invalidate(tavernAssetsProvider);
      if (mounted) context.pushReplacement(AppRoutes.tavernStory(saved.id));
    } catch (e) {
      if (mounted) setState(() => error = tavernFriendlyError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}
