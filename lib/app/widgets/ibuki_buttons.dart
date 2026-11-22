import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/ibuki_theme_colors.dart';

class IbukiPrimaryButton extends StatelessWidget {
  const IbukiPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = FilledButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon ?? Icons.arrow_forward_rounded, size: 19),
      label: Text(label),
    );
    return expand ? SizedBox(width: double.infinity, child: child) : child;
  }
}

class IbukiSecondaryButton extends StatelessWidget {
  const IbukiSecondaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.arrow_forward_rounded, size: 19),
      label: Text(label),
    );
    return expand ? SizedBox(width: double.infinity, child: child) : child;
  }
}

class IbukiTextAction extends StatelessWidget {
  const IbukiTextAction({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return TextButton(onPressed: onPressed, child: Text(label));
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class IbukiIconButton extends StatelessWidget {
  const IbukiIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(AppTokens.compactButtonHeight),
        maximumSize: const Size.square(AppTokens.compactButtonHeight),
        backgroundColor: selected ? context.ibukiColors.primarySoft : null,
        foregroundColor: selected
            ? Theme.of(context).colorScheme.primary
            : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
        ),
      ),
    );
  }
}
