import 'package:flutter/material.dart';

import '../theme/bubble_theme.dart';

class BubbleBackground extends StatelessWidget {
  const BubbleBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.bubbleTheme;
    return DecoratedBox(
      key: const Key('bubble-background'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.backgroundStart,
            colors.backgroundMiddle,
            colors.backgroundEnd,
          ],
          stops: const [0, 0.52, 1],
        ),
      ),
      child: child,
    );
  }
}
