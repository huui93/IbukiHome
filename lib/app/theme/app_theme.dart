import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;

import 'app_tokens.dart';
import 'ibuki_theme_colors.dart';
import 'bubble_theme.dart';
import 'ibuki_motion.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppTokens.accentBlue,
          surface: AppTokens.pageBackground,
        ).copyWith(
          primary: AppTokens.accentBlue,
          secondary: AppTokens.accentPink,
          tertiary: AppTokens.accentBlue,
          onSurface: AppTokens.textPrimary,
          onSurfaceVariant: AppTokens.textSecondary,
          outlineVariant: AppTokens.divider,
          error: AppTokens.error,
        );

    return _base(
      scheme,
      surfaceContainer: AppTokens.surface,
      surfaceRaised: AppTokens.surfaceRaised,
      extension: const IbukiThemeColors(
        primarySoft: AppTokens.primarySoft,
        accent: AppTokens.accentPink,
        accentSoft: AppTokens.accentSoft,
        textMuted: AppTokens.textSecondary,
        surfaceRaised: AppTokens.surfaceRaised,
        disabled: AppTokens.disabled,
        success: AppTokens.success,
      ),
      bubble: const BubbleTheme(
        backgroundStart: Color(0xFFF3F7FF),
        backgroundMiddle: Color(0xFFFFFBFD),
        backgroundEnd: Color(0xFFFFF2F7),
        glass: Color(0xC9FFFFFF),
        glassStrong: Color(0xEDFFFFFF),
        glassBorder: Color(0xC7FFFFFF),
        shadow: Color(0x14718FE8),
        messageIncoming: Color(0xEAF2F6FF),
        messageOutgoingStart: Color(0xFF7795EE),
        messageOutgoingEnd: Color(0xFF8B91EA),
      ),
    );
  }

  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppTokens.accentBlue,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppTokens.accentBlueDark,
          secondary: AppTokens.accentPink,
          tertiary: AppTokens.accentBlue,
          surface: AppTokens.pageBackgroundDark,
          onSurface: AppTokens.textPrimaryDark,
          onSurfaceVariant: AppTokens.textSecondaryDark,
          outlineVariant: AppTokens.dividerDark,
          error: AppTokens.error,
        );

    return _base(
      scheme,
      surfaceContainer: AppTokens.surfaceDark,
      surfaceRaised: AppTokens.surfaceRaisedDark,
      extension: const IbukiThemeColors(
        primarySoft: AppTokens.primarySoftDark,
        accent: AppTokens.accentPinkDark,
        accentSoft: AppTokens.accentSoftDark,
        textMuted: AppTokens.textSecondaryDark,
        surfaceRaised: AppTokens.surfaceRaisedDark,
        disabled: AppTokens.disabledDark,
        success: AppTokens.success,
      ),
      bubble: const BubbleTheme(
        backgroundStart: Color(0xFF191B2A),
        backgroundMiddle: Color(0xFF171925),
        backgroundEnd: Color(0xFF24202D),
        glass: Color(0xB3292C3D),
        glassStrong: Color(0xEB252838),
        glassBorder: Color(0x1FFFFFFF),
        shadow: Color(0x52080A12),
        messageIncoming: Color(0xE82A3045),
        messageOutgoingStart: Color(0xFF7795EE),
        messageOutgoingEnd: Color(0xFF8F8BE4),
      ),
    );
  }

  static ThemeData _base(
    ColorScheme scheme, {
    required Color surfaceContainer,
    required Color surfaceRaised,
    required IbukiThemeColors extension,
    required BubbleTheme bubble,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [extension, bubble],
      scaffoldBackgroundColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: IbukiPageTransitionsBuilder(),
          TargetPlatform.windows: IbukiPageTransitionsBuilder(),
          TargetPlatform.linux: IbukiPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: IbukiPageTransitionsBuilder(),
        },
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        expansionAnimationStyle: AnimationStyle(
          duration: IbukiMotion.feedback,
          reverseDuration: IbukiMotion.feedback,
          curve: IbukiMotion.curve,
          reverseCurve: IbukiMotion.curve,
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(foregroundBuilder: IbukiMotion.buttonContent),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surfaceContainer,
        surfaceTintColor: Colors.transparent,
        width: AppTokens.drawerMaxWidth,
      ),
      cardTheme: CardThemeData(
        color: bubble.glass,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
          side: BorderSide(color: bubble.glassBorder),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bubble.glassStrong,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppTokens.buttonHeight),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusM),
          ),
          elevation: 0.5,
        ).copyWith(foregroundBuilder: IbukiMotion.buttonContent),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppTokens.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusM),
          ),
          backgroundColor: extension.primarySoft,
          foregroundColor: scheme.primary,
          side: BorderSide.none,
        ).copyWith(foregroundBuilder: IbukiMotion.buttonContent),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppTokens.compactButtonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusS),
          ),
        ).copyWith(foregroundBuilder: IbukiMotion.buttonContent),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bubble.glassStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.bubbleComposerRadius),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bubble.glassStrong,
        modalBackgroundColor: bubble.glassStrong,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.bubbleSheetRadius),
          ),
        ),
      ),
    );
  }
}
