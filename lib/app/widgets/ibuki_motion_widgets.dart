import 'package:flutter/material.dart';
import '../theme/ibuki_motion.dart';

/// Passive press feedback: the child retains ownership of taps, scrolling,
/// focus and semantics. Dragging cancels the visual press; the child decides
/// how to recognize taps and scrolling.
class IbukiPressMotion extends StatefulWidget {
  const IbukiPressMotion({
    required this.child,
    this.enabled = true,
    this.scale = .98,
    super.key,
  });
  final Widget child;
  final bool enabled;
  final double scale;
  @override
  State<IbukiPressMotion> createState() => _IbukiPressMotionState();
}

class _IbukiPressMotionState extends State<IbukiPressMotion> {
  int? _pointer;
  Offset? _origin;
  bool _pressed = false;
  void _release() {
    if (_pressed) setState(() => _pressed = false);
    _pointer = null;
    _origin = null;
  }

  @override
  void didUpdateWidget(covariant IbukiPressMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _pressed = false;
      _pointer = null;
      _origin = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = IbukiMotion.reducedOf(context);
    return Listener(
      onPointerDown: (event) {
        if (!widget.enabled || reduced || _pointer != null) return;
        _pointer = event.pointer;
        _origin = event.position;
        setState(() => _pressed = true);
      },
      onPointerMove: (event) {
        if (event.pointer == _pointer &&
            _origin != null &&
            (event.position - _origin!).distance > 8) {
          _release();
        }
      },
      onPointerUp: (event) {
        if (event.pointer == _pointer) _release();
      },
      onPointerCancel: (event) {
        if (event.pointer == _pointer) _release();
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: !reduced && _pressed ? widget.scale : 1),
        duration: IbukiMotion.durationOf(
          context,
          _pressed ? IbukiMotion.press : IbukiMotion.feedback,
        ),
        curve: _pressed ? IbukiMotion.curve : Curves.easeOutBack,
        child: widget.child,
        builder: (context, scale, child) => Transform.scale(
          scale: scale,
          transformHitTests: false,
          child: child,
        ),
      ),
    );
  }
}

/// A finite entrance which runs only on mounting. Rebuilds (including streamed
/// text or repository updates) cannot restart it. It reserves its final layout.
class IbukiEntrance extends StatefulWidget {
  const IbukiEntrance({
    required this.child,
    this.order = 0,
    this.animate = true,
    this.offset = const Offset(0, 14),
    super.key,
  });
  final Widget child;
  final int order;
  final bool animate;
  final Offset offset;
  @override
  State<IbukiEntrance> createState() => _IbukiEntranceState();
}

class _IbukiEntranceState extends State<IbukiEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  bool _started = false;
  @override
  void initState() {
    super.initState();
    final delay = widget.order.clamp(0, 5) * 32;
    final total = IbukiMotion.enter.inMilliseconds + delay;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
    );
    _progress = _controller.drive(
      CurveTween(curve: Interval(delay / total, 1, curve: IbukiMotion.curve)),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (IbukiMotion.reducedOf(context) || !_started && !widget.animate) {
      _controller.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _progress,
    child: widget.child,
    builder: (context, child) {
      final value = IbukiMotion.reducedOf(context) ? 1.0 : _progress.value;
      return Opacity(
        opacity: value,
        child: Transform.translate(
          offset: widget.offset * (1 - value),
          child: child,
        ),
      );
    },
  );
}
