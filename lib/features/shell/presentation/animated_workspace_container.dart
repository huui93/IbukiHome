import 'package:flutter/material.dart';
import '../../../app/theme/ibuki_motion.dart';

/// Keeps all branch Navigators mounted. Only the selected branch accepts
/// input/semantics; outgoing branches stop their own animations immediately.
class AnimatedWorkspaceContainer extends StatefulWidget {
  const AnimatedWorkspaceContainer({
    required this.currentIndex,
    required this.children,
    super.key,
  });
  final int currentIndex;
  final List<Widget> children;
  @override
  State<AnimatedWorkspaceContainer> createState() =>
      _AnimatedWorkspaceContainerState();
}

class _AnimatedWorkspaceContainerState extends State<AnimatedWorkspaceContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<double> _fromOpacity;
  late List<double> _toOpacity;
  late List<double> _fromX;
  late List<double> _toX;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: IbukiMotion.workspace,
      value: 1,
    );
    _fromOpacity = List.generate(
      widget.children.length,
      (i) => i == widget.currentIndex ? 1 : 0,
    );
    _toOpacity = [..._fromOpacity];
    _fromX = List.filled(widget.children.length, 0);
    _toX = [..._fromX];
  }

  double _at(List<double> from, List<double> to, int i) =>
      from[i] +
      (to[i] - from[i]) * IbukiMotion.curve.transform(_controller.value);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (IbukiMotion.reducedOf(context)) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant AnimatedWorkspaceContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(widget.children.length == _fromOpacity.length);
    if (oldWidget.currentIndex == widget.currentIndex) return;
    // Retarget from the current pose so rapid wheel taps don't restart pages
    // from an unrelated position or recreate their navigation/editing state.
    final opacity = List.generate(
      widget.children.length,
      (i) => _at(_fromOpacity, _toOpacity, i),
    );
    final x = List.generate(
      widget.children.length,
      (i) => _at(_fromX, _toX, i),
    );
    final step =
        (widget.currentIndex -
            oldWidget.currentIndex +
            widget.children.length) %
        widget.children.length;
    final direction = step > widget.children.length / 2 ? -1.0 : 1.0;
    _controller.stop();
    _fromOpacity = opacity;
    _fromX = x;
    if (opacity[widget.currentIndex] == 0) {
      _fromX[widget.currentIndex] = direction * 28;
    }
    _toOpacity = List.generate(
      widget.children.length,
      (i) => i == widget.currentIndex ? 1 : 0,
    );
    _toX = List.generate(
      widget.children.length,
      (i) => i == widget.currentIndex ? 0 : -direction * 28,
    );
    if (IbukiMotion.reducedOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            Offstage(
              offstage:
                  i != widget.currentIndex &&
                  _at(_fromOpacity, _toOpacity, i) <= 0,
              child: FocusScope(
                canRequestFocus: i == widget.currentIndex,
                skipTraversal: i != widget.currentIndex,
                child: TickerMode(
                  enabled: i == widget.currentIndex,
                  child: IgnorePointer(
                    ignoring: i != widget.currentIndex,
                    child: ExcludeSemantics(
                      excluding: i != widget.currentIndex,
                      child: Opacity(
                        opacity: _at(_fromOpacity, _toOpacity, i).clamp(0, 1),
                        child: Transform.translate(
                          offset: Offset(_at(_fromX, _toX, i), 0),
                          child: Transform.scale(
                            scale:
                                .985 + .015 * _at(_fromOpacity, _toOpacity, i),
                            child: widget.children[i],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
