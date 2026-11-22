import 'package:flutter/material.dart';

import '../../../application/profile/local_user_profile.dart';

class LocalUserAvatar extends StatelessWidget {
  const LocalUserAvatar({required this.profile, this.radius = 20, super.key});
  final LocalUserProfile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = switch (profile.avatar) {
      'pink' => const Color(0xFFF9DDE8),
      'lilac' => const Color(0xFFE8E0FA),
      'mint' => const Color(0xFFD8EFE5),
      _ => const Color(0xFFDFE7FF),
    };
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: profile.photo == null
          ? Icon(
              Icons.person_rounded,
              size: radius * 1.25,
              color: const Color(0xFF6574AE),
            )
          : ClipOval(
              child: Image.memory(
                profile.photo!,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.person_rounded, size: radius),
              ),
            ),
    );
  }
}
