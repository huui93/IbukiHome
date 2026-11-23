import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/routing/app_routes.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../application/projects/txt_novel_source.dart';
import '../../../application/projects/txt_novel_providers.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../app/localization/app_localizations.dart';

class ImportTxtNovelPage extends ConsumerStatefulWidget {
  const ImportTxtNovelPage({super.key});
  @override
  ConsumerState<ImportTxtNovelPage> createState() => _ImportTxtNovelPageState();
}

class _ImportTxtNovelPageState extends ConsumerState<ImportTxtNovelPage> {
  final _title = TextEditingController();
  PreparedTxtNovel? _novel;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Column(
      key: const Key('import-txt-novel-page'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Text(
                context.tr("将 TXT 作为一部新小说导入。"),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('pick-txt-novel'),
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.file_open_outlined),
                label: Text(
                  _novel == null
                      ? context.tr("选择 TXT 文件")
                      : context.tr("更换 TXT 文件"),
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    key: const Key('txt-import-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_novel case final novel?) ...[
                const SizedBox(height: 16),
                Text(
                  context.tr("{file} · {count} 字 · {encoding}", {
                    "file": novel.fileName,
                    "count": novel.characters,
                    "encoding": novel.encoding,
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('txt-novel-title'),
                  controller: _title,
                  enabled: !_busy,
                  decoration: InputDecoration(labelText: context.tr("小说名称")),
                ),
                const SizedBox(height: 16),
                IbukiGlassSurface(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    novel.parts.first,
                    key: const Key('txt-novel-preview'),
                    maxLines: 10,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('confirm-txt-import'),
                onPressed: _busy || _novel == null ? null : _import,
                icon: const Icon(Icons.download_done_rounded),
                label: Text(context.tr("导入小说")),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ref.read(txtNovelPickerProvider).pick();
      if (file == null || !mounted) return;
      final decoded = await ref
          .read(txtNovelDecoderProvider)
          .decode(file.bytes);
      final novel = await compute(prepareTxtNovel, (
        fileName: file.name,
        text: decoded.text,
        encoding: decoded.encoding,
      ));
      if (!mounted) return;
      setState(() {
        _novel = novel;
        _title.text = novel.title;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _describe(error);
          _novel = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final novel = _novel;
    if (novel == null || _busy) return;
    if (_title.text.trim().isEmpty) {
      setState(() => _error = '请填写小说名称。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final project = await ref.read(importTxtNovelProvider)(
        novel,
        _title.text,
      );
      if (!mounted) return;
      notifyRepositoryChanged(
        ref,
        areas: const [RepositoryDataArea.projects, RepositoryDataArea.segments],
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr("《{title}》已导入。", {"title": project.title})),
        ),
      );
      context.go(AppRoutes.novel);
    } catch (error) {
      if (mounted) setState(() => _error = _describe(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describe(Object error) =>
      error is FormatException ? error.message : '导入失败，请检查文件后重试。';
}
