import 'package:flutter/material.dart';

import 'app_tokens.dart';

@immutable
class IbukiThemeColors extends ThemeExtension<IbukiThemeColors> {
  const IbukiThemeColors({
    required this.primarySoft,
    required this.accent,
    required this.accentSoft,
    required this.textMuted,
    required this.surfaceRaised,
    required this.disabled,
    required this.success,
  });

  final Color primarySoft;
  final Color accent;
  final Color accentSoft;
  final Color textMuted;
  final Color surfaceRaised;
  final Color disabled;
  final Color success;

  @override
  IbukiThemeColors copyWith({
    Color? primarySoft,
    Color? accent,
    Color? accentSoft,
    Color? textMuted,
    Color? surfaceRaised,
    Color? disabled,
    Color? success,
  }) {
    return IbukiThemeColors(
      primarySoft: primarySoft ?? this.primarySoft,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      textMuted: textMuted ?? this.textMuted,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      disabled: disabled ?? this.disabled,
      success: success ?? this.success,
    );
  }

  @override
  IbukiThemeColors lerp(covariant IbukiThemeColors? other, double t) {
    if (other == null) {
      return this;
    }
    return IbukiThemeColors(
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      success: Color.lerp(success, other.success, t)!,
    );
  }
}

extension IbukiThemeContext on BuildContext {
  IbukiThemeColors get ibukiColors {
    final theme = Theme.of(this);
    final configured = theme.extension<IbukiThemeColors>();
    if (configured != null) return configured;
    final dark = theme.brightness == Brightness.dark;
    return IbukiThemeColors(
      primarySoft: dark ? AppTokens.primarySoftDark : AppTokens.primarySoft,
      accent: dark ? AppTokens.accentPinkDark : AppTokens.accentPink,
      accentSoft: dark ? AppTokens.accentSoftDark : AppTokens.accentSoft,
      textMuted: dark ? AppTokens.textSecondaryDark : AppTokens.textSecondary,
      surfaceRaised: dark
          ? AppTokens.surfaceRaisedDark
          : AppTokens.surfaceRaised,
      disabled: dark ? AppTokens.disabledDark : AppTokens.disabled,
      success: AppTokens.success,
    );
  }
}
