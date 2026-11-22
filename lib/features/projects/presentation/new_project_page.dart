import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../application/projects/current_project_controller.dart';
import '../../../application/providers/repository_providers.dart';
import '../../mascot/application/mascot_controller.dart';
import '../../mascot/domain/mascot_action.dart';
import 'project_flow_widgets.dart';

class NewProjectPage extends ConsumerStatefulWidget {
  const NewProjectPage({super.key});

  @override
  ConsumerState<NewProjectPage> createState() => _NewProjectPageState();
}

class _NewProjectPageState extends ConsumerState<NewProjectPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  var _isSaving = false;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController()..addListener(_listenToInput);
    _descriptionController = TextEditingController()
      ..addListener(_listenToInput);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        key: const Key('new-project-page'),
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppTokens.spacingM),
              children: [
                Text(
                  '新建项目',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppTokens.spacingS),
                TextButton.icon(
                  key: const Key('new-project-import-txt'),
                  onPressed: _isSaving
                      ? null
                      : () => context.push(AppRoutes.importTxtNovel),
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('从 TXT 导入小说'),
                ),
                const MemoryDataNotice(),
                const SizedBox(height: AppTokens.spacingM),
                TextField(
                  key: const Key('project-title-field'),
                  controller: _titleController,
                  enabled: !_isSaving,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: '项目名称',
                    errorText: _titleError,
                  ),
                ),
                const SizedBox(height: AppTokens.spacingM),
                TextField(
                  key: const Key('project-description-field'),
                  controller: _descriptionController,
                  enabled: !_isSaving,
                  keyboardType: TextInputType.multiline,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '项目说明（可选）',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spacingM,
                AppTokens.spacingS,
                AppTokens.spacingM,
                AppTokens.spacingM,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('save-project-button'),
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_isSaving ? '保存中' : '创建项目'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _listenToInput() {
    if (!mounted || _isSaving) {
      return;
    }
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.listen);
    if (_titleError != null && _titleController.text.trim().isNotEmpty) {
      setState(() {
        _titleError = null;
      });
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() {
        _titleError = '项目名称不能为空';
      });
      _showSnack('请先填写项目名称。');
      return;
    }

    setState(() {
      _isSaving = true;
      _titleError = null;
    });
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);

    try {
      final id = ref.read(entityIdGeneratorProvider).nextId('project');
      final now = ref.read(utcClockProvider).now();
      final project = await ref.read(createProjectProvider)(
        title: title,
        description: _descriptionController.text,
        id: id,
        nowUtc: now,
      );
      if (!mounted) {
        return;
      }
      ref
          .read(currentProjectControllerProvider.notifier)
          .selectProject(project.id);
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.projects]);
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
      context.go(AppRoutes.novelEditor(project.id));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      _showSnack(_friendlyError(error));
      setState(() {
        _isSaving = false;
      });
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('项目名称不能为空')) {
      return '项目名称不能为空。';
    }
    return '项目保存失败，请稍后重试。';
  }
}
