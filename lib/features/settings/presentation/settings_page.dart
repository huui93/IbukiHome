import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/app_language.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../app/navigation/app_workspace_mode.dart';
import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/theme/ibuki_theme_colors.dart';
import '../../../app/theme/theme_controller.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../app/widgets/ibuki_motion_widgets.dart';
import '../../../application/ai/ai_settings_controller.dart';
import '../../../application/ai/ai_output_preferences.dart';
import '../../../application/chat/chat_vision_preferences.dart';
import '../../ai/presentation/ai_model_binding_sheet.dart';
import '../../../application/profile/local_user_profile.dart';
import '../../../application/preferences/app_language_preferences.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({
    this.sourceWorkspace = AppWorkspaceMode.settings,
    super.key,
  });

  final AppWorkspaceMode sourceWorkspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(appLanguageProvider);
    final language = preference.value ?? AppLanguage.fallback;
    final profile = ref.watch(localUserProfileProvider).value;
    final themeMode = ref.watch(themeModeControllerProvider);
    final isDark = themeMode == ThemeMode.dark;
    final aiState = ref.watch(aiSettingsControllerProvider).value;
    final streamOutput = ref.watch(aiOutputPreferencesProvider);
    final vision = ref.watch(chatVisionPreferencesProvider);
    final defaultAi = aiState?.defaultSelection;
    final defaultConfig = defaultAi == null
        ? null
        : aiState?.configById(defaultAi.providerId);
    final defaultLabel = defaultConfig == null || defaultAi == null
        ? context.tr('尚未配置 AI')
        : '${defaultConfig.displayName} · ${defaultAi.modelId}';

    return ListView(
      key: const Key('settings-page'),
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spacingM,
        AppTokens.spacingS,
        AppTokens.spacingM,
        AppTokens.spacingXl,
      ),
      children: [
        _SettingsSection(
          title: '我的',
          children: [
            _SettingsRow(
              keyValue: const Key('settings-language'),
              icon: Icons.language_rounded,
              title: context.tr('语言'),
              subtitle: language.displayName,
              onTap: preference.isLoading
                  ? null
                  : () => _selectLanguage(context, ref, language),
            ),
            _SettingsRow(
              keyValue: const Key('settings-personal-profile'),
              icon: Icons.account_circle_outlined,
              title: context.tr('本人设定'),
              subtitle: profile?.name ?? context.tr('头像与名字'),
              onTap: () => context.push(AppRoutes.personalProfile),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spacingM),
        _SettingsSection(
          title: 'AI 与模型',
          children: [
            SwitchListTile(
              key: const Key('settings-stream-output'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              secondary: const _SettingsIcon(icon: Icons.stream_rounded),
              title: Text(context.tr('流式输出')),
              subtitle: Text(context.tr('小说与聊天；关闭后整段显示回答')),
              value: streamOutput.value ?? true,
              onChanged: streamOutput.isLoading
                  ? null
                  : (enabled) async {
                      try {
                        await ref
                            .read(aiOutputPreferencesProvider.notifier)
                            .setStreaming(enabled);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('设置未保存，请重试。')),
                          );
                        }
                      }
                    },
            ),
            _SettingsRow(
              keyValue: const Key('settings-ai-config'),
              icon: Icons.auto_awesome_outlined,
              title: context.tr('API 配置'),
              subtitle: context.tr('8 家官方服务与自定义 API'),
              onTap: () => context.push(AppRoutes.aiProviders),
              accent: true,
            ),
            _SettingsRow(
              keyValue: const Key('settings-default-ai'),
              icon: Icons.tune_rounded,
              title: context.tr('默认 AI'),
              subtitle: defaultLabel,
              onTap: () => context.push(AppRoutes.aiSettings),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spacingM),
        _SettingsSection(
          title: '聊天',
          children: [
            _SettingsRow(
              keyValue: const Key('settings-chat-vision'),
              icon: Icons.image_search_rounded,
              title: context.tr('识图模型'),
              subtitle: vision.hasError
                  ? context.tr('设置读取失败，请重试')
                  : vision.value == null
                  ? context.tr('跟随当前聊天模型')
                  : '${aiState?.configById(vision.value!.providerId)?.displayName ?? context.tr('单独设置')} · ${vision.value!.modelId}',
              onTap: () async {
                try {
                  await showAiModelBindingSheet(
                    context: context,
                    ref: ref,
                    scope: AiModelBindingScope.chatVision,
                    entityId: 'chat-vision',
                  );
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('识图模型设置读取失败，请稍后重试。')),
                    );
                  }
                }
              },
            ),
            _SettingsRow(
              keyValue: const Key('settings-chat-memory'),
              icon: Icons.psychology_outlined,
              title: context.tr('聊天记忆'),
              subtitle: context.tr('自动记忆与对话引用'),
              onTap: () => context.push(AppRoutes.chatMemorySettings),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spacingM),
        _SettingsSection(
          title: '外观',
          children: [
            SwitchListTile(
              key: const Key('settings-theme-switch'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              secondary: const _SettingsIcon(icon: Icons.dark_mode_outlined),
              title: Text(context.tr('深色模式')),
              subtitle: Text(context.tr(isDark ? '已开启' : '使用柔和浅色外观')),
              value: isDark,
              onChanged: (value) => ref
                  .read(themeModeControllerProvider.notifier)
                  .setDarkMode(value),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spacingM),
        _SettingsSection(
          title: '扩展',
          children: [
            _SettingsRow(
              keyValue: const Key('settings-plugins'),
              icon: Icons.extension_rounded,
              title: context.tr('插件'),
              subtitle: context.tr('安装和管理本地 .ibuki 扩展'),
              onTap: () => context.push(AppRoutes.plugins),
              accent: true,
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spacingM),
        _SettingsSection(
          title: '数据与备份',
          children: [
            _SettingsRow(
              keyValue: const Key('settings-backup-restore'),
              icon: Icons.archive_outlined,
              title: context.tr('完整备份与恢复'),
              subtitle: context.tr('创建或恢复 .ibukibackup 归档'),
              onTap: () => context.push(AppRoutes.backupRestore),
              accent: true,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _selectLanguage(
    BuildContext context,
    WidgetRef ref,
    AppLanguage current,
  ) async {
    final selected = await showModalBottomSheet<AppLanguage>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          key: const Key('language-options'),
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                sheetContext.tr('选择语言'),
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            for (final option in AppLanguage.values)
              ListTile(
                key: Key('language-option-${option.code}'),
                selected: option == current,
                leading: Icon(
                  option == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(option.displayName),
                onTap: () => Navigator.pop(sheetContext, option),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted || selected == null) return;
    try {
      await ref.read(appLanguageProvider.notifier).setLanguage(selected);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('语言设置未保存，请重试。'))));
      }
    }
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IbukiEntrance(
      order: switch (title) {
        '我的' => 0,
        'AI 与模型' => 1,
        '聊天' => 2,
        '外观' => 3,
        _ => 4,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
            child: Text(
              context.tr(title),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: context.ibukiColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IbukiGlassSurface(
            key: Key('settings-glass-$title'),
            strong: true,
            radius: AppTokens.bubbleRadius,
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  children[index],
                  if (index != children.length - 1)
                    const Divider(indent: 64, endIndent: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.keyValue,
    this.accent = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Key? keyValue;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return IbukiPressMotion(
      enabled: onTap != null,
      child: ListTile(
        key: keyValue,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: _SettingsIcon(icon: icon, accent: accent),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: onTap == null
            ? null
            : Icon(
                Icons.chevron_right_rounded,
                color: context.ibukiColors.textMuted,
              ),
        onTap: onTap,
      ),
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({required this.icon, this.accent = false});

  final IconData icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent
            ? context.ibukiColors.accentSoft
            : context.ibukiColors.primarySoft,
        borderRadius: BorderRadius.circular(AppTokens.bubbleSmallRadius),
      ),
      child: SizedBox.square(
        dimension: 38,
        child: Icon(
          icon,
          size: 20,
          color: accent
              ? context.ibukiColors.accent
              : Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
