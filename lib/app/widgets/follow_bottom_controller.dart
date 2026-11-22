import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Keeps long, append-only views stable without stealing the user's reading
/// position when they have intentionally scrolled away from the newest item.
class FollowBottomController extends ChangeNotifier {
  FollowBottomController({
    required this.storageId,
    this.nearBottomThreshold = 160,
    this.followThrottle = const Duration(milliseconds: 80),
    this.initiallyFollowBottom = true,
  }) {
    scrollController = ScrollController()..addListener(_handlePositionChanged);
    _following = initiallyFollowBottom;
  }

  final String storageId;
  final double nearBottomThreshold;
  final Duration followThrottle;
  final bool initiallyFollowBottom;

  late final ScrollController scrollController;
  Timer? _followTimer;
  bool _frameScheduled = false;
  bool _following = true;
  bool _showJumpToBottom = false;
  bool _disposed = false;

  bool get isFollowing => _following;
  bool get showJumpToBottom => _showJumpToBottom;

  bool get isNearBottom {
    if (!scrollController.hasClients) return true;
    final position = scrollController.position;
    return position.maxScrollExtent - position.pixels <= nearBottomThreshold;
  }

  bool handleScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward) {
        _setFollowing(false);
      } else if (notification.direction == ScrollDirection.reverse &&
          isNearBottom) {
        _setFollowing(true);
      } else if (notification.direction == ScrollDirection.idle &&
          isNearBottom) {
        _setFollowing(true);
      }
    }
    _syncJumpButton();
    return false;
  }

  /// Schedules one post-layout follow. Repeated streaming updates are batched.
  void onContentAppended() {
    if (!_following || _disposed) {
      _syncJumpButton();
      return;
    }
    _followTimer?.cancel();
    _followTimer = Timer(
      followThrottle,
      () => _scheduleScroll(animated: false),
    );
  }

  /// Restores a previously-following view after its first layout.
  void restoreAfterFirstLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      final restoredAwayFromTop =
          scrollController.hasClients &&
          scrollController.position.pixels > 0 &&
          !isNearBottom;
      if (restoredAwayFromTop) {
        _setFollowing(false);
      } else if (initiallyFollowBottom) {
        _setFollowing(true);
        _scheduleScroll(animated: false);
      } else {
        _setFollowing(isNearBottom);
      }
      _syncJumpButton();
    });
  }

  void scrollToBottom() {
    _setFollowing(true);
    _followTimer?.cancel();
    _scheduleScroll(animated: true);
  }

  void _scheduleScroll({required bool animated, int remainingPasses = 1}) {
    if (_frameScheduled || _disposed) return;
    _frameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameScheduled = false;
      if (_disposed || !_following || !scrollController.hasClients) return;
      final target = scrollController.position.maxScrollExtent;
      if (animated) {
        final animation = scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
        unawaited(
          animation.whenComplete(() {
            if (!_disposed && _following) {
              _scheduleScroll(animated: false, remainingPasses: 0);
            }
          }),
        );
      } else {
        scrollController.jumpTo(target);
        if (remainingPasses > 0) {
          _scheduleScroll(
            animated: false,
            remainingPasses: remainingPasses - 1,
          );
        }
      }
      _syncJumpButton();
    });
  }

  void _handlePositionChanged() {
    _syncJumpButton();
  }

  void _setFollowing(bool value) {
    if (_following == value) return;
    _following = value;
    if (!value) _followTimer?.cancel();
    _syncJumpButton();
  }

  void _syncJumpButton() {
    if (_disposed) return;
    final next = !_following && !isNearBottom;
    if (_showJumpToBottom == next) return;
    _showJumpToBottom = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _followTimer?.cancel();
    scrollController
      ..removeListener(_handlePositionChanged)
      ..dispose();
    super.dispose();
  }
}

class JumpToBottomButton extends StatelessWidget {
  const JumpToBottomButton({
    required this.onPressed,
    required this.buttonKey,
    super.key,
  });

  final VoidCallback onPressed;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      elevation: 3,
      shadowColor: Theme.of(context).shadowColor.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(18),
      child: IconButton(
        key: buttonKey,
        tooltip: '回到底部',
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_downward_rounded, size: 20),
      ),
    );
  }
}
