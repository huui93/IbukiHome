import 'package:flutter/material.dart';
import '../theme/ibuki_motion.dart';

/// Shared floating menu for the two chat plus buttons.
Future<T?> showIbukiActionMenu<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Alignment alignment = Alignment.topRight,
  EdgeInsets padding = const EdgeInsets.fromLTRB(16, 64, 16, 16),
  double width = 240,
  Key? menuKey,
}) => showGeneralDialog<T>(
  context: context,
  useRootNavigator: true,
  barrierDismissible: true,
  barrierLabel: '关闭菜单',
  barrierColor: Colors.black54,
  transitionDuration: IbukiMotion.durationOf(context, IbukiMotion.enter),
  pageBuilder: (dialogContext, _, _) => SafeArea(
    child: Padding(
      padding: padding.add(
        EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(dialogContext).bottom),
      ),
      child: Align(
        alignment: alignment,
        child: Material(
          key: menuKey,
          color: Theme.of(dialogContext).colorScheme.surface,
          elevation: 10,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(child: builder(dialogContext)),
          ),
        ),
      ),
    ),
  ),
  transitionBuilder: (context, animation, _, child) {
    if (IbukiMotion.reducedOf(context)) return child;
    final progress = animation.drive(CurveTween(curve: IbukiMotion.curve));
    return FadeTransition(
      opacity: progress,
      child: ScaleTransition(
        scale: Tween<double>(begin: .9, end: 1).animate(progress),
        alignment: alignment,
        child: RotationTransition(
          turns: Tween<double>(
            begin: alignment.y < 0 ? -.008 : .008,
            end: 0,
          ).animate(progress),
          alignment: alignment,
          child: child,
        ),
      ),
    );
  },
);
