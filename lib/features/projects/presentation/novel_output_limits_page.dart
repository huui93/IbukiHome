import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/widgets/bubble_background.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../application/projects/novel_output_limits_providers.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../domain/projects/novel_output_limits.dart';
import '../../../core/errors/data_exceptions.dart';
import '../../../app/localization/app_localizations.dart';

class NovelOutputLimitsPage extends ConsumerStatefulWidget {
  const NovelOutputLimitsPage({required this.projectId, super.key});
  final String projectId;
  @override
  ConsumerState<NovelOutputLimitsPage> createState() =>
      _NovelOutputLimitsPageState();
}

class _NovelOutputLimitsPageState extends ConsumerState<NovelOutputLimitsPage> {
  final _minimum = TextEditingController();
  final _maximum = TextEditingController();
  final _temperature = TextEditingController();
  NovelOutputLimits? _loaded;
  bool _saving = false, _dirty = false;
  String? _error;
  @override
  void dispose() {
    _minimum.dispose();
    _maximum.dispose();
    _temperature.dispose();
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
              title: Text(context.tr("放弃未保存的修改？")),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: Text(context.tr("继续编辑")),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: Text(context.tr("放弃")),
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
            title: Text(context.tr("输出字数与温度")),
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
                _temperature.text = value.temperature?.toString() ?? '';
              }
              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Text(
                    project?.title ?? context.tr("当前作品"),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(context.tr('为当前作品设置字数和温度，留空使用默认。')),
                  const SizedBox(height: 20),
                  IbukiGlassSurface(
                    strong: true,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _field(
                                _minimum,
                                '最少字数',
                                const Key('novel-output-minimum'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _field(
                                _maximum,
                                '最多字数',
                                const Key('novel-output-maximum'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('novel-output-temperature'),
                          controller: _temperature,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => _markDirty(),
                          decoration: InputDecoration(
                            labelText: context.tr('温度（0–2）'),
                            hintText: context.tr('默认'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr(
                      '最大字数在保存时执行；最低字数是目标，模型输出不足会提示。局部修改只应用温度。部分模型或推理模式使用服务默认温度。',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        context.tr(_error!),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  FilledButton(
                    key: const Key('save-novel-output-limits'),
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? context.tr("保存中") : context.tr("保存")),
                  ),
                  TextButton(
                    key: const Key('reset-novel-output-limits'),
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _minimum.clear();
                            _maximum.clear();
                            _temperature.clear();
                            _dirty = true;
                            _error = null;
                          }),
                    child: Text(context.tr('恢复默认')),
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
        onChanged: (_) => _markDirty(),
        decoration: InputDecoration(
          labelText: context.tr(label),
          hintText: context.tr("默认"),
          suffixText: context.tr('字'),
        ),
      );
  void _markDirty() => setState(() {
    _dirty = true;
    _error = null;
  });

  double? _parseTemperature() {
    final text = _temperature.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text.replaceAll(',', '.'));
    if (value == null || !value.isFinite || value < 0 || value > 2) {
      throw const FormatException('温度须在 0 到 2 之间；留空使用默认。');
    }
    return value;
  }

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
        temperature: _parseTemperature(),
      );
      final saved = await ref
          .read(novelOutputLimitsRepositoryProvider)
          .save(
            value,
            expectedRevision: _loaded!.revision,
            now: ref.read(utcClockProvider).now(),
          );
      if (!mounted) return;
      _loaded = saved;
      ref.invalidate(novelOutputLimitsProvider(widget.projectId));
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
