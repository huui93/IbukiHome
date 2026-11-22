import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_settings_controller.dart';

class LocalUserProfile {
  const LocalUserProfile({this.name = '我', this.avatar = 'blue', this.photo});

  final String name;
  final String avatar;
  final Uint8List? photo;
  static const avatarChoices = ['blue', 'pink', 'lilac', 'mint'];

  factory LocalUserProfile.decode(String? raw) {
    if (raw == null) return const LocalUserProfile();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final name = (json['name'] as String?)?.trim();
      final avatar = json['avatar'] as String?;
      final encoded = json['photo'] as String?;
      return LocalUserProfile(
        name: name == null || name.isEmpty ? '我' : name,
        avatar: avatarChoices.contains(avatar) ? avatar! : 'blue',
        photo: encoded == null ? null : base64Decode(encoded),
      );
    } catch (_) {
      return const LocalUserProfile();
    }
  }

  String encode() => jsonEncode({
    'name': name,
    'avatar': avatar,
    'photo': photo == null ? null : base64Encode(photo!),
  });
}

final localUserProfileProvider =
    AsyncNotifierProvider<LocalUserProfileController, LocalUserProfile>(
      LocalUserProfileController.new,
    );

class LocalUserProfileController extends AsyncNotifier<LocalUserProfile> {
  static const storageKey = 'profile.local_user.v1';

  @override
  Future<LocalUserProfile> build() async => LocalUserProfile.decode(
    await ref.watch(aiSecureValueStoreProvider).read(storageKey),
  );

  Future<void> save(LocalUserProfile profile) async {
    final name = profile.name.trim();
    if (name.isEmpty) throw const FormatException('名字不能为空');
    if (name.runes.length > 80) throw const FormatException('名字太长了');
    if ((profile.photo?.length ?? 0) > 256 * 1024) {
      throw const FormatException('头像图片过大，请换一张图片');
    }
    final value = LocalUserProfile(
      name: name,
      avatar: profile.avatar,
      photo: profile.photo,
    );
    await ref
        .read(aiSecureValueStoreProvider)
        .write(storageKey, value.encode());
    if (ref.mounted) state = AsyncData(value);
  }
}
