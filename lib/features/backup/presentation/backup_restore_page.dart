import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../application/backup/backup_providers.dart';
import '../../../domain/backup/backup_models.dart';
import '../../../app/localization/app_localizations.dart';

class BackupRestorePage extends ConsumerStatefulWidget {
  const BackupRestorePage({super.key});

  @override
  ConsumerState<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends ConsumerState<BackupRestorePage> {
  BackupProgress? _progress;
  bool _busy = false;
  BackupCancellationToken? _cancellation;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          key: const Key('backup-restore-page'),
          padding: const EdgeInsets.all(AppTokens.spacingM),
          children: [
            IbukiGlassSurface(
              strong: true,
              child: Column(
                children: [
                  ListTile(
                    key: const Key('create-full-backup'),
                    leading: const Icon(Icons.archive_outlined),
                    title: const Text('创建完整备份'),
                    subtitle: const Text('保存小说、聊天、世界、世界书与兼容资料'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _busy ? null : _createBackup,
                  ),
                  const Divider(indent: 56),
                  ListTile(
                    key: const Key('restore-full-backup'),
                    leading: const Icon(Icons.settings_backup_restore_rounded),
                    title: const Text('从备份恢复'),
                    subtitle: const Text('选择 .ibukibackup，验证后再确认恢复'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _busy ? null : _restoreBackup,
                  ),
                  const Divider(indent: 56),
                  ListTile(
                    key: const Key('about-full-backup'),
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('关于备份'),
                    subtitle: const Text('了解凭据排除、卸载与本地存储的安全边界'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _busy ? null : _showAboutBackup,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.spacingM),
            const IbukiGlassSurface(
              child: Padding(
                padding: EdgeInsets.all(AppTokens.spacingM),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '关于完整备份',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '完整备份不包含 API Key、Authorization、SecureStorage 或 Provider 凭据。恢复后的 AI 绑定会回到未配置状态，由你重新选择。',
                    ),
                    SizedBox(height: 8),
                    Text('SillyTavern 扩展数据会作为不可执行兼容资料保存；恢复不会运行脚本，也不会访问网络。'),
                    SizedBox(height: 8),
                    Text('只有通过系统文件选择器保存到用户选择位置的备份，才能在卸载 App 后继续保留。'),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_busy)
          _ProgressOverlay(
            progress: _progress,
            onCancel: _cancellation == null
                ? null
                : () => _cancellation?.cancel(),
          ),
      ],
    );
  }

  Future<void> _createBackup() async {
    await _run(() async {
      final directory = ref.read(backupWorkingDirectoryProvider);
      await directory.create(recursive: true);
      final now = DateTime.now();
      final name =
          'IbukiHome-${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}-'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}.ibukibackup';
      final file = File('${directory.path}${Platform.pathSeparator}$name');
      final prepared = await ref.read(backupServiceProvider).prepareBackup();
      if (!mounted) return;
      final save = await showDialog<bool>(
        context: context,
        builder: (context) => _BackupPreviewDialog(preview: prepared.preview),
      );
      if (save != true || !mounted) return;
      _cancellation = BackupCancellationToken();
      try {
        await ref
            .read(backupServiceProvider)
            .writePreparedBackup(
              prepared,
              file,
              onProgress: _updateProgress,
              cancellation: _cancellation,
            );
        _cancellation = null;
        final saved = await ref
            .read(backupArchivePickerProvider)
            .save(file, name);
        if (mounted && saved) _message('完整备份已保存。');
      } finally {
        if (await file.exists()) await file.delete();
      }
    });
  }

  Future<void> _restoreBackup() async {
    await _run(() async {
      final directory = ref.read(backupWorkingDirectoryProvider);
      final source = await ref
          .read(backupArchivePickerProvider)
          .pickForRestore(directory);
      if (source == null) return;
      _cancellation = BackupCancellationToken();
      final inspection = await (() async {
        try {
          return await ref
              .read(backupServiceProvider)
              .inspect(
                source,
                onProgress: _updateProgress,
                cancellation: _cancellation,
              );
        } finally {
          if (await source.exists()) await source.delete();
        }
      })();
      if (!mounted) return;
      setState(() {
        _cancellation = null;
        _progress = null;
      });
      final mode = await showDialog<BackupRestoreMode>(
        context: context,
        builder: (context) =>
            _RestorePreviewDialog(preview: inspection.archive.preview),
      );
      if (mode == null) {
        await ref.read(backupServiceProvider).discardInspection(inspection);
        return;
      }
      _cancellation = BackupCancellationToken();
      await ref
          .read(backupServiceProvider)
          .restore(
            inspection,
            mode: mode,
            onProgress: _updateProgress,
            cancellation: _cancellation,
          );
      if (mounted) {
        notifyFullRestoreCompleted(ref);
        final configure = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('内容恢复完成'),
            content: const Text('API 设置和密钥不会包含在备份中。如需继续使用 AI，请重新配置 Provider。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('稍后'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('去配置 API'),
              ),
            ],
          ),
        );
        if (configure == true && mounted) {
          context.push(AppRoutes.aiProviders);
        }
      }
    });
  }

  Future<void> _showAboutBackup() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于完整备份'),
        content: const Text(
          '完整备份不包含 API Key、Authorization、SecureStorage 或 Provider 凭据。'
          '恢复不会运行兼容资料中的脚本，也不会访问网络。\n\n'
          '保存在 App 私有目录的普通文件可能随卸载消失。'
          '请通过系统文件选择器把备份保存到你选择的位置。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      await action();
    } on BackupException catch (error) {
      if (mounted) _message(error.message);
    } catch (error) {
      if (mounted) _message('操作未完成，请检查文件后重试。');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _cancellation = null;
        });
      }
    }
  }

  void _updateProgress(BackupProgress progress) {
    if (mounted) setState(() => _progress = progress);
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}

class _BackupPreviewDialog extends StatelessWidget {
  const _BackupPreviewDialog({required this.preview});
  final BackupPreview preview;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('完整备份预览'),
      content: _PreviewBody(preview: preview),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.tr("取消")),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('选择保存位置'),
        ),
      ],
    );
  }
}

class _RestorePreviewDialog extends StatefulWidget {
  const _RestorePreviewDialog({required this.preview});
  final BackupPreview preview;

  @override
  State<_RestorePreviewDialog> createState() => _RestorePreviewDialogState();
}

class _RestorePreviewDialogState extends State<_RestorePreviewDialog> {
  BackupRestoreMode _mode = BackupRestoreMode.merge;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('恢复预览'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreviewBody(preview: widget.preview),
            const Divider(height: 24),
            RadioGroup<BackupRestoreMode>(
              groupValue: _mode,
              onChanged: (value) {
                if (value != null) setState(() => _mode = value);
              },
              child: const Column(
                children: [
                  RadioListTile(
                    value: BackupRestoreMode.merge,
                    title: Text('合并恢复'),
                    subtitle: Text('保留现有内容；ID 冲突时创建独立副本，不静默覆盖'),
                  ),
                  RadioListTile(
                    value: BackupRestoreMode.fresh,
                    title: Text('恢复到空资料库'),
                    subtitle: Text('仅在当前没有用户内容时使用'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr("取消")),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _mode),
          child: const Text('确认恢复'),
        ),
      ],
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.preview});
  final BackupPreview preview;

  @override
  Widget build(BuildContext context) {
    final manifest = preview.manifest;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('创建时间：${manifest.createdAt.toLocal()}'),
        Text('归档版本：${manifest.appVersion} / v$ibukiBackupVersion'),
        Text('数据记录：${preview.totalRows}'),
        Text('资源文件：${preview.totalAssets}'),
        const SizedBox(height: 10),
        const Text('包含小说、聊天、角色、世界、世界书、历史版本、记忆、时间线与兼容资料。'),
        const SizedBox(height: 8),
        const Text('不包含 API Key、Provider 凭据、缓存、日志或可执行扩展状态。'),
      ],
    );
  }
}

class _ProgressOverlay extends StatelessWidget {
  const _ProgressOverlay({required this.progress, this.onCancel});
  final BackupProgress? progress;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.22),
        child: Center(
          child: IbukiGlassSurface(
            strong: true,
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spacingL),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(progress?.stage ?? '正在准备…'),
                    if ((progress?.total ?? 0) > 0) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: (progress!.completed / progress!.total).clamp(
                          0,
                          1,
                        ),
                      ),
                    ],
                    if (onCancel != null) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: onCancel,
                        child: Text(context.tr("取消")),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
