import 'package:flutter/material.dart';

/// One timing language for the wheel, pages and small interactions. All motion
/// finishes; reading surfaces never run decorative repeating controllers.
class IbukiMotion {
  const IbukiMotion._();
  static const press = Duration(milliseconds: 100);
  static const feedback = Duration(milliseconds: 220);
  static const enter = Duration(milliseconds: 320);
  static const workspace = Duration(milliseconds: 420);
  static const curve = Curves.easeOutCubic;

  static bool reducedOf(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    return (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
  }

  static Duration durationOf(BuildContext context, Duration duration) =>
      reducedOf(context) ? Duration.zero : duration;

  /// ButtonStyle owns gesture recognition, focus, keyboard and semantics. This
  /// layer only animates its contents and never changes the button's hit box.
  static Widget buttonContent(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) {
    final pressed =
        states.contains(WidgetState.pressed) &&
        !states.contains(WidgetState.disabled);
    return AnimatedScale(
      scale: reducedOf(context) ? 1 : (pressed ? .94 : 1),
      duration: durationOf(context, pressed ? press : feedback),
      curve: pressed ? curve : Curves.easeOutBack,
      child: child,
    );
  }
}

class IbukiPageTransitionsBuilder extends PageTransitionsBuilder {
  const IbukiPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (IbukiMotion.reducedOf(context)) return child;
    final progress = animation.drive(CurveTween(curve: IbukiMotion.curve));
    return FadeTransition(
      opacity: progress,
      child: SlideTransition(
        position: progress.drive(
          Tween(begin: const Offset(.055, .012), end: Offset.zero),
        ),
        child: ScaleTransition(
          scale: progress.drive(Tween(begin: .985, end: 1.0)),
          alignment: Alignment.centerRight,
          child: child,
        ),
      ),
    );
  }
}
