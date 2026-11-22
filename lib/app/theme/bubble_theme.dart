import 'package:flutter/material.dart';

import 'app_tokens.dart';

@immutable
class BubbleTheme extends ThemeExtension<BubbleTheme> {
  const BubbleTheme({
    required this.backgroundStart,
    required this.backgroundMiddle,
    required this.backgroundEnd,
    required this.glass,
    required this.glassStrong,
    required this.glassBorder,
    required this.shadow,
    required this.messageIncoming,
    required this.messageOutgoingStart,
    required this.messageOutgoingEnd,
  });

  final Color backgroundStart;
  final Color backgroundMiddle;
  final Color backgroundEnd;
  final Color glass;
  final Color glassStrong;
  final Color glassBorder;
  final Color shadow;
  final Color messageIncoming;
  final Color messageOutgoingStart;
  final Color messageOutgoingEnd;

  @override
  BubbleTheme copyWith({
    Color? backgroundStart,
    Color? backgroundMiddle,
    Color? backgroundEnd,
    Color? glass,
    Color? glassStrong,
    Color? glassBorder,
    Color? shadow,
    Color? messageIncoming,
    Color? messageOutgoingStart,
    Color? messageOutgoingEnd,
  }) {
    return BubbleTheme(
      backgroundStart: backgroundStart ?? this.backgroundStart,
      backgroundMiddle: backgroundMiddle ?? this.backgroundMiddle,
      backgroundEnd: backgroundEnd ?? this.backgroundEnd,
      glass: glass ?? this.glass,
      glassStrong: glassStrong ?? this.glassStrong,
      glassBorder: glassBorder ?? this.glassBorder,
      shadow: shadow ?? this.shadow,
      messageIncoming: messageIncoming ?? this.messageIncoming,
      messageOutgoingStart: messageOutgoingStart ?? this.messageOutgoingStart,
      messageOutgoingEnd: messageOutgoingEnd ?? this.messageOutgoingEnd,
    );
  }

  @override
  BubbleTheme lerp(covariant BubbleTheme? other, double t) {
    if (other == null) return this;
    return BubbleTheme(
      backgroundStart: Color.lerp(backgroundStart, other.backgroundStart, t)!,
      backgroundMiddle: Color.lerp(
        backgroundMiddle,
        other.backgroundMiddle,
        t,
      )!,
      backgroundEnd: Color.lerp(backgroundEnd, other.backgroundEnd, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      glassStrong: Color.lerp(glassStrong, other.glassStrong, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      messageIncoming: Color.lerp(messageIncoming, other.messageIncoming, t)!,
      messageOutgoingStart: Color.lerp(
        messageOutgoingStart,
        other.messageOutgoingStart,
        t,
      )!,
      messageOutgoingEnd: Color.lerp(
        messageOutgoingEnd,
        other.messageOutgoingEnd,
        t,
      )!,
    );
  }
}

extension BubbleThemeContext on BuildContext {
  BubbleTheme get bubbleTheme {
    final theme = Theme.of(this);
    final configured = theme.extension<BubbleTheme>();
    if (configured != null) return configured;
    final dark = theme.brightness == Brightness.dark;
    return BubbleTheme(
      backgroundStart: dark
          ? AppTokens.surfaceRaisedDark
          : AppTokens.primarySoft,
      backgroundMiddle: dark
          ? AppTokens.pageBackgroundDark
          : AppTokens.pageBackground,
      backgroundEnd: dark ? AppTokens.accentSoftDark : AppTokens.accentSoft,
      glass: (dark ? AppTokens.surfaceDark : AppTokens.surface).withValues(
        alpha: AppTokens.glassOpacity,
      ),
      glassStrong: (dark ? AppTokens.surfaceDark : AppTokens.surface)
          .withValues(alpha: AppTokens.glassStrongOpacity),
      glassBorder: (dark ? AppTokens.dividerDark : AppTokens.divider)
          .withValues(alpha: AppTokens.glassBorderOpacity),
      shadow: Colors.black.withValues(alpha: dark ? 0.22 : 0.06),
      messageIncoming: dark ? AppTokens.primarySoftDark : AppTokens.primarySoft,
      messageOutgoingStart: dark
          ? AppTokens.accentBlueDark
          : AppTokens.accentBlue,
      messageOutgoingEnd: dark
          ? AppTokens.accentBlueDark
          : AppTokens.avatarLilac,
    );
  }
}
