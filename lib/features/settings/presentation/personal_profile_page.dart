import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/widgets/bubble_background.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../application/profile/local_user_profile.dart';
import '../../../application/profile/profile_avatar_picker.dart';
import 'local_user_avatar.dart';
import '../../../app/localization/app_localizations.dart';

class PersonalProfilePage extends ConsumerStatefulWidget {
  const PersonalProfilePage({super.key});
  @override
  ConsumerState<PersonalProfilePage> createState() =>
      _PersonalProfilePageState();
}

class _PersonalProfilePageState extends ConsumerState<PersonalProfilePage> {
  final _name = TextEditingController();
  String _avatar = 'blue';
  Uint8List? _photo;
  bool _loaded = false, _saving = false, _picking = false;
  String? _error;
  LocalUserProfile? _original;
  bool _leaving = false;
  bool get _dirty =>
      _original != null &&
      (_name.text.trim() != _original!.name ||
          _avatar != _original!.avatar ||
          !listEquals(_photo, _original!.photo));

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(localUserProfileProvider);
    return PopScope(
      canPop: !_dirty && !_saving && !_picking,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _leave();
      },
      child: BubbleBackground(
        child: Scaffold(
          key: const Key('personal-profile-page'),
          appBar: AppBar(
            title: Text(context.tr("本人设定")),
            leading: BackButton(onPressed: _saving || _picking ? null : _leave),
          ),
          body: value.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(localUserProfileProvider),
                child: Text(context.tr("读取失败，点击重试")),
              ),
            ),
            data: (profile) {
              if (!_loaded) {
                _loaded = true;
                _original = profile;
                _name.text = profile.name;
                _avatar = profile.avatar;
                _photo = profile.photo;
              }
              return SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: LocalUserAvatar(
                        profile: LocalUserProfile(
                          name: _name.text,
                          avatar: _avatar,
                          photo: _photo,
                        ),
                        radius: 44,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        key: const Key('pick-personal-avatar'),
                        onPressed: _saving || _picking ? null : _pick,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(
                          _picking
                              ? context.tr("正在读取图片")
                              : context.tr("选择头像图片"),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Wrap(
                        spacing: 14,
                        children: [
                          for (final avatar in LocalUserProfile.avatarChoices)
                            Semantics(
                              label:
                                  '使用${{'blue': '蓝色', 'pink': '粉色', 'lilac': '紫色', 'mint': '绿色'}[avatar]}默认头像',
                              selected: _photo == null && _avatar == avatar,
                              button: true,
                              child: InkWell(
                                key: Key('personal-avatar-$avatar'),
                                borderRadius: BorderRadius.circular(28),
                                onTap: _saving || _picking
                                    ? null
                                    : () => setState(() {
                                        _avatar = avatar;
                                        _photo = null;
                                      }),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: LocalUserAvatar(
                                    profile: LocalUserProfile(avatar: avatar),
                                    radius: 20,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    IbukiGlassSurface(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        key: const Key('personal-name-field'),
                        controller: _name,
                        onChanged: (_) => setState(() => _error = null),
                        enabled: !_saving,
                        maxLength: 40,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: context.tr("名字"),
                          hintText: context.tr("你希望显示的名字"),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.tr("头像和名字会显示在聊天页左上角。"),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('save-personal-profile'),
                      onPressed: _saving || _picking ? null : _save,
                      child: Text(
                        _saving ? context.tr("保存中") : context.tr("保存"),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _leave() async {
    if (_saving || _picking || _leaving) return;
    _leaving = true;
    try {
      if (_dirty) {
        final discard = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(dialogContext.tr("放弃未保存的修改？")),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(dialogContext.tr("继续编辑")),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(dialogContext.tr("放弃")),
              ),
            ],
          ),
        );
        if (discard != true || !mounted) return;
      }
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.settings);
      }
    } finally {
      _leaving = false;
    }
  }

  Future<void> _pick() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final photo = await ref.read(profileAvatarPickerProvider).pick();
      if (mounted && photo != null) setState(() => _photo = photo);
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取这张图片，请选择有效的图片后重试。');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '名字不能为空');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(localUserProfileProvider.notifier)
          .save(
            LocalUserProfile(name: _name.text, avatar: _avatar, photo: _photo),
          );
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.settings);
      }
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，修改内容仍在，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
