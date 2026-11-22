import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/bubble_theme.dart';
import 'ibuki_motion_widgets.dart';

class IbukiGlassSurface extends StatelessWidget {
  const IbukiGlassSurface({
    required this.child,
    this.padding,
    this.margin,
    this.radius = AppTokens.bubbleRadius,
    this.blur = false,
    this.strong = false,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final bool blur;
  final bool strong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bubble = context.bubbleTheme;
    Widget inner = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    if (onTap != null) {
      inner = InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: inner,
      );
    }
    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: strong ? bubble.glassStrong : bubble.glass,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: bubble.glassBorder),
        boxShadow: [
          BoxShadow(
            color: bubble.shadow,
            blurRadius: strong ? 20 : 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(color: Colors.transparent, child: inner),
    );
    if (blur) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: content,
        ),
      );
    }
    if (onTap != null) content = IbukiPressMotion(child: content);
    return Padding(padding: margin ?? EdgeInsets.zero, child: content);
  }
}
