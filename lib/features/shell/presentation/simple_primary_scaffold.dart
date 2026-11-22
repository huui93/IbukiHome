import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/theme/bubble_theme.dart';
import '../../../app/theme/ibuki_theme_colors.dart';
import '../../../app/widgets/bubble_background.dart';
import '../../../app/theme/ibuki_motion.dart';

class PrimaryNavigationScope extends InheritedWidget {
  const PrimaryNavigationScope({
    required this.navigationShell,
    required super.child,
    super.key,
  });

  final StatefulNavigationShell navigationShell;

  static PrimaryNavigationScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PrimaryNavigationScope>();
  }

  @override
  bool updateShouldNotify(PrimaryNavigationScope oldWidget) {
    return navigationShell.currentIndex !=
        oldWidget.navigationShell.currentIndex;
  }
}

class SimplePrimaryScaffold extends StatefulWidget {
  const SimplePrimaryScaffold({
    required this.selectedIndex,
    required this.title,
    required this.body,
    this.titleWidget,
    this.showAppBar = true,
    this.leading,
    this.actions,
    this.exitApp,
    this.onBack,
    super.key,
  });

  final int selectedIndex;
  final String title;
  final Widget body;
  final Widget? titleWidget;
  final bool showAppBar;
  final Widget? leading;
  final List<Widget>? actions;
  final VoidCallback? exitApp;
  final VoidCallback? onBack;

  @override
  State<SimplePrimaryScaffold> createState() => _SimplePrimaryScaffoldState();
}

class _SimplePrimaryScaffoldState extends State<SimplePrimaryScaffold> {
  var _exitDialogVisible = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _handleRootBack();
      },
      child: BubbleBackground(
        child: Scaffold(
          key: const Key('simple-primary-scaffold'),
          resizeToAvoidBottomInset: true,
          extendBody: true,
          appBar: !widget.showAppBar
              ? null
              : AppBar(
                  automaticallyImplyLeading: false,
                  centerTitle: false,
                  leading: widget.leading,
                  title:
                      widget.titleWidget ??
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  actions: widget.actions,
                  scrolledUnderElevation: 0,
                  surfaceTintColor: Colors.transparent,
                  backgroundColor: Colors.transparent,
                  flexibleSpace: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: ColoredBox(color: context.bubbleTheme.glass),
                    ),
                  ),
                ),
          body: Padding(
            padding: EdgeInsets.only(
              bottom: PrimaryNavigationScope.maybeOf(context) == null
                  ? AppTokens.primaryNavigationHeight +
                        AppTokens.spacingM +
                        MediaQuery.paddingOf(context).bottom
                  : 0,
            ),
            child: SafeArea(
              top: !widget.showAppBar,
              bottom: false,
              child: widget.body,
            ),
          ),
          bottomNavigationBar: PrimaryNavigationScope.maybeOf(context) == null
              ? _PrimaryBottomBar(
                  key: const Key('primary-bottom-navigation'),
                  selectedIndex: widget.selectedIndex,
                )
              : null,
        ),
      ),
    );
  }

  Future<void> _handleRootBack() async {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }
    if (_exitDialogVisible || !mounted) return;
    _exitDialogVisible = true;
    try {
      final exit = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const Key('exit-app-dialog'),
          title: const Text('离开伊吹之家？'),
          content: const Text('确定要退出应用吗？'),
          actions: [
            TextButton(
              key: const Key('cancel-exit-app'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('confirm-exit-app'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('退出'),
            ),
          ],
        ),
      );
      if (exit == true) {
        (widget.exitApp ?? SystemNavigator.pop)();
      }
    } finally {
      _exitDialogVisible = false;
    }
  }
}

/// One shared wheel stays mounted while the indexed workspace changes.
class PrimaryNavigationFrame extends StatelessWidget {
  const PrimaryNavigationFrame({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) => BubbleBackground(
    child: Scaffold(
      body: navigationShell,
      bottomNavigationBar: _PrimaryBottomBar(
        key: const Key('primary-bottom-navigation'),
        selectedIndex: navigationShell.currentIndex,
      ),
    ),
  );
}

class _PrimaryBottomBar extends StatefulWidget {
  const _PrimaryBottomBar({required this.selectedIndex, super.key});
  final int selectedIndex;

  @override
  State<_PrimaryBottomBar> createState() => _PrimaryBottomBarState();
}

class _PrimaryBottomBarState extends State<_PrimaryBottomBar>
    with SingleTickerProviderStateMixin {
  static const _step = math.pi * 2 / 3;
  static const _destinations = [
    (
      id: 'novel',
      label: '小说',
      image: 'assets/images/navigation/nav_novel.png',
      route: AppRoutes.novel,
    ),
    (
      id: 'chat',
      label: '聊天',
      image: 'assets/images/navigation/nav_chat.png',
      route: AppRoutes.chat,
    ),
    (
      id: 'settings',
      label: '设置',
      image: 'assets/images/navigation/nav_settings.png',
      route: AppRoutes.settings,
    ),
  ];
  late final AnimationController _controller;
  late Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: IbukiMotion.workspace,
    );
    _rotation = AlwaysStoppedAnimation(-widget.selectedIndex * _step);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (IbukiMotion.reducedOf(context) && _controller.isAnimating) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _PrimaryBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex == widget.selectedIndex) return;
    final from = _rotation.value;
    final desired = -widget.selectedIndex * _step;
    final delta = (desired - from + math.pi) % (2 * math.pi) - math.pi;
    _controller.stop();
    if (IbukiMotion.reducedOf(context)) {
      _rotation = AlwaysStoppedAnimation(from + delta);
      return;
    }
    _rotation = Tween<double>(
      begin: from,
      end: from + delta,
    ).chain(CurveTween(curve: Curves.easeInOutCubic)).animate(_controller);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bubble = context.bubbleTheme;
    final labelHeight =
        MediaQuery.textScalerOf(
          context,
        ).scale(Theme.of(context).textTheme.labelSmall?.fontSize ?? 11) *
        1.4;
    final itemHeight = math.max(70.0, 44 + labelHeight);
    final wheelHeight = math.max(
      AppTokens.primaryNavigationHeight,
      itemHeight + 18,
    );
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.bubbleRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bubble.glassStrong,
              borderRadius: BorderRadius.circular(AppTokens.bubbleRadius),
              border: Border.all(color: bubble.glassBorder),
            ),
            child: SizedBox(
              height: wheelHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = math.min(92.0, constraints.maxWidth / 3);
                  final radius = (constraints.maxWidth - itemWidth) / 2;
                  return AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final order = [0, 1, 2]
                        ..sort(
                          (a, b) => math
                              .cos(a * _step + _rotation.value)
                              .compareTo(math.cos(b * _step + _rotation.value)),
                        );
                      return Stack(
                        children: [
                          for (final index in order)
                            Positioned(
                              key: ValueKey(
                                'wheel-position-${_destinations[index].id}',
                              ),
                              left:
                                  radius +
                                  math.sin(index * _step + _rotation.value) *
                                      radius,
                              top:
                                  2 +
                                  (1 -
                                          math.cos(
                                            index * _step + _rotation.value,
                                          )) *
                                      7,
                              width: itemWidth,
                              height: itemHeight,
                              child: _PrimaryNavItem(
                                itemKey: Key(
                                  'bottom-nav-${_destinations[index].id}',
                                ),
                                label: _destinations[index].label,
                                assetPath: _destinations[index].image,
                                selected: widget.selectedIndex == index,
                                prominent: index == 1,
                                onTap: () => _go(
                                  context,
                                  index,
                                  _destinations[index].route,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _go(BuildContext context, int index, String location) {
    if (widget.selectedIndex == index) return;
    final scope = PrimaryNavigationScope.maybeOf(context);
    if (scope == null) {
      context.go(location);
    } else {
      scope.navigationShell.goBranch(index);
    }
  }
}

class _PrimaryNavItem extends StatelessWidget {
  const _PrimaryNavItem({
    required this.itemKey,
    required this.label,
    required this.assetPath,
    required this.selected,
    required this.onTap,
    this.prominent = false,
  });
  final Key itemKey;
  final String label;
  final String assetPath;
  final bool selected;
  final VoidCallback onTap;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      enabled: true,
      selected: selected,
      button: true,
      label: prominent ? '$label，主系统' : label,
      child: InkWell(
        key: itemKey,
        borderRadius: BorderRadius.circular(AppTokens.bubbleSmallRadius),
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            key: selected ? Key('bottom-nav-selected-$label') : null,
            duration: IbukiMotion.durationOf(context, IbukiMotion.feedback),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: selected
                  ? context.ibukiColors.primarySoft.withValues(alpha: 0.75)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTokens.bubbleSmallRadius),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: prominent ? 44 : 38,
                  height: 36,
                  child: AnimatedScale(
                    key: Key('bottom-nav-image-scale-$label'),
                    scale: selected ? 1.16 : 0.94,
                    duration: IbukiMotion.durationOf(
                      context,
                      IbukiMotion.feedback,
                    ),
                    child: AnimatedOpacity(
                      key: Key('bottom-nav-image-opacity-$label'),
                      opacity: selected || prominent ? 1 : 0.68,
                      duration: IbukiMotion.durationOf(
                        context,
                        IbukiMotion.feedback,
                      ),
                      child: Image.asset(
                        assetPath,
                        key: Key('bottom-nav-image-$label'),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selected || prominent
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: selected || prominent
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
