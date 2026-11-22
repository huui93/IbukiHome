import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/widgets/bubble_background.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../application/projects/novel_output_limits_providers.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../domain/projects/novel_output_limits.dart';
import '../../../core/errors/data_exceptions.dart';

class NovelOutputLimitsPage extends ConsumerStatefulWidget {
  const NovelOutputLimitsPage({required this.projectId, super.key});
  final String projectId;
  @override
  ConsumerState<NovelOutputLimitsPage> createState() =>
      _NovelOutputLimitsPageState();
}

class _NovelOutputLimitsPageState extends ConsumerState<NovelOutputLimitsPage> {
  final _minimum = TextEditingController(), _maximum = TextEditingController();
  NovelOutputLimits? _loaded;
  bool _saving = false, _dirty = false;
  String? _error;
  @override
  void dispose() {
    _minimum.dispose();
    _maximum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final limits = ref.watch(novelOutputLimitsProvider(widget.projectId));
    final project = ref.watch(projectByIdProvider(widget.projectId)).value;
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && !_saving) {
          final discard = await showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: const Text('放弃未保存的修改？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('继续编辑'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('放弃'),
                ),
              ],
            ),
          );
          if (discard == true && context.mounted) {
            setState(() => _dirty = false);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) Navigator.pop(context);
            });
          }
        }
      },
      child: BubbleBackground(
        child: Scaffold(
          key: const Key('novel-output-limits-page'),
          appBar: AppBar(
            title: const Text('输出字数'),
            leading: const BackButton(),
          ),
          body: limits.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Center(child: Text('无法读取作品设置。')),
            data: (value) {
              if (_loaded == null) {
                _loaded = value;
                _minimum.text = value.minimum?.toString() ?? '';
                _maximum.text = value.maximum?.toString() ?? '';
              }
              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Text(
                    project?.title ?? '当前作品',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('设置每次生成正文的目标字数。留空使用默认，也可以只设置一侧。'),
                  const SizedBox(height: 20),
                  IbukiGlassSurface(
                    strong: true,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        _field(
                          _minimum,
                          '最少字数',
                          const Key('novel-output-minimum'),
                        ),
                        const SizedBox(height: 18),
                        _field(
                          _maximum,
                          '最多字数',
                          const Key('novel-output-maximum'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '用于生成下一段、自动剧情和整段重写。局部修改按选中内容处理。\n\n字数与模型的 token 上限不是同一单位。实际输出以模型和服务允许的上限为准，字数范围作为创作目标。',
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  FilledButton(
                    key: const Key('save-novel-output-limits'),
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '保存中' : '保存'),
                  ),
                  TextButton(
                    key: const Key('reset-novel-output-limits'),
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _minimum.clear();
                            _maximum.clear();
                            _dirty = true;
                            _error = null;
                          }),
                    child: const Text('恢复默认'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, Key key) =>
      TextField(
        key: key,
        controller: controller,
        enabled: !_saving,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() {
          _dirty = true;
          _error = null;
        }),
        decoration: InputDecoration(
          labelText: label,
          hintText: '默认',
          suffixText: '字',
        ),
      );
  int? _parse(String text) {
    if (text.trim().isEmpty) return null;
    final value = int.tryParse(text.trim());
    if (value == null || value <= 0) {
      throw const FormatException('字数请输入大于 0 的整数；留空使用默认。');
    }
    return value;
  }

  Future<void> _save() async {
    if (_loaded == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final value = NovelOutputLimits(
        projectId: widget.projectId,
        minimum: _parse(_minimum.text),
        maximum: _parse(_maximum.text),
      );
      _loaded = await ref
          .read(novelOutputLimitsRepositoryProvider)
          .save(
            value,
            expectedRevision: _loaded!.revision,
            now: ref.read(utcClockProvider).now(),
          );
      ref.invalidate(novelOutputLimitsProvider(widget.projectId));
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('输出字数已保存')));
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message.toString()
              : error is DataException
              ? error.message
              : '设置未保存，请检查字数或重新打开后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
