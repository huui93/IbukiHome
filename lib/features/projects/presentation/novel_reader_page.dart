import '../../../application/plugins/novel_plugin_providers.dart';
import 'novel_reply_content.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../domain/reader/reader_preferences.dart';
import '../../../domain/segments/segment.dart';

class NovelReaderPage extends ConsumerStatefulWidget {
  const NovelReaderPage({required this.projectId, super.key});

  final String projectId;

  @override
  ConsumerState<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends ConsumerState<NovelReaderPage> {
  final _scrollController = ScrollController();
  bool _controlsVisible = true;
  bool _restored = false;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scheduleProgressSave);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    unawaited(_saveProgress());
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectByIdProvider(widget.projectId));
    final segments = ref.watch(segmentListProvider(widget.projectId));
    final preferences = ref.watch(readerPreferencesProvider(widget.projectId));
    final progress = ref.watch(readerProgressProvider(widget.projectId));
    return project.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const Scaffold(body: Center(child: Text('无法打开作品。'))),
      data: (project) => preferences.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => const Scaffold(body: Center(child: Text('无法读取阅读设置。'))),
        data: (prefs) => segments.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, _) => const Scaffold(body: Center(child: Text('无法读取正文。'))),
          data: (items) {
            progress.whenData((value) => _restorePosition(value, items));
            return _buildReader(context, project.title, items, prefs);
          },
        ),
      ),
    );
  }

  Widget _buildReader(
    BuildContext context,
    String title,
    List<Segment> segments,
    ReaderPreferences preferences,
  ) {
    final palette = _ReaderPalette.of(preferences.theme);
    final renderPlugin =
        ref.watch(novelBoundPluginProvider(widget.projectId)).value != null;
    final progress =
        _scrollController.hasClients &&
            _scrollController.position.maxScrollExtent > 0
        ? (_scrollController.offset /
                  _scrollController.position.maxScrollExtent *
                  100)
              .clamp(0, 100)
        : 0;
    return Scaffold(
      key: const Key('novel-reader-page'),
      backgroundColor: palette.background,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => setState(() => _controlsVisible = !_controlsVisible),
        child: Stack(
          children: [
            SafeArea(
              child: segments.isEmpty
                  ? Center(
                      child: Text(
                        '这部作品还没有正文。',
                        style: TextStyle(color: palette.secondaryText),
                      ),
                    )
                  : ListView.builder(
                      key: const Key('reader-segment-list'),
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        preferences.horizontalMargin,
                        _controlsVisible ? 84 : AppTokens.spacingL,
                        preferences.horizontalMargin,
                        96,
                      ),
                      itemCount: segments.length,
                      itemBuilder: (context, index) {
                        final segment = segments[index];
                        final style = TextStyle(
                          color: palette.text,
                          fontSize: preferences.fontSize,
                          height: preferences.lineHeight,
                        );
                        return Padding(
                          key: ValueKey('reader-${segment.id}'),
                          padding: const EdgeInsets.only(bottom: 24),
                          child: renderPlugin
                              ? NovelReplyContent(
                                  segment: segment,
                                  style: style,
                                  textKey: ValueKey(
                                    'reader-plugin-${segment.id}',
                                  ),
                                )
                              : Text(segment.content, style: style),
                        );
                      },
                    ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 190),
              top: _controlsVisible ? 0 : -90,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.spacingS),
                  child: IbukiGlassSurface(
                    key: const Key('reader-controls'),
                    blur: true,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        IconButton(
                          key: const Key('reader-back-button'),
                          tooltip: '返回',
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text('${progress.round()}%'),
                        IconButton(
                          key: const Key('reader-settings-button'),
                          tooltip: '阅读设置',
                          onPressed: () => _showSettings(preferences),
                          icon: const Icon(Icons.text_fields_rounded),
                        ),
                      ],
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

  void _restorePosition(ReaderProgress progress, List<Segment> segments) {
    if (_restored) return;
    _restored = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      var target = progress.scrollOffset;
      if (progress.lastReadSegmentId != null &&
          !segments.any((item) => item.id == progress.lastReadSegmentId)) {
        target = target.clamp(0, _scrollController.position.maxScrollExtent);
      }
      _scrollController.jumpTo(
        target.clamp(0, _scrollController.position.maxScrollExtent),
      );
    });
  }

  void _scheduleProgressSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() {});
      unawaited(_saveProgress());
    });
  }

  Future<void> _saveProgress() async {
    if (!_scrollController.hasClients) return;
    final segments = await ref.read(
      segmentListProvider(widget.projectId).future,
    );
    final max = _scrollController.position.maxScrollExtent;
    final ratio = max <= 0 ? 0.0 : (_scrollController.offset / max).clamp(0, 1);
    final index = segments.isEmpty
        ? -1
        : (ratio * (segments.length - 1)).round().clamp(0, segments.length - 1);
    await ref
        .read(readerRepositoryProvider)
        .saveProgress(
          ReaderProgress(
            projectId: widget.projectId,
            lastReadSegmentId: index < 0 ? null : segments[index].id,
            scrollOffset: _scrollController.offset,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<void> _showSettings(ReaderPreferences initial) async {
    var value = initial;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spacingM),
            child: Column(
              key: const Key('reader-settings-sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('阅读设置', style: Theme.of(context).textTheme.titleLarge),
                _ReaderSlider(
                  label: '字号',
                  value: value.fontSize,
                  min: 14,
                  max: 28,
                  onChanged: (next) => setSheetState(
                    () => value = value.copyWith(fontSize: next),
                  ),
                ),
                _ReaderSlider(
                  label: '行距',
                  value: value.lineHeight,
                  min: 1.3,
                  max: 2.3,
                  onChanged: (next) => setSheetState(
                    () => value = value.copyWith(lineHeight: next),
                  ),
                ),
                _ReaderSlider(
                  label: '左右边距',
                  value: value.horizontalMargin,
                  min: 12,
                  max: 48,
                  onChanged: (next) => setSheetState(
                    () => value = value.copyWith(horizontalMargin: next),
                  ),
                ),
                SegmentedButton<ReaderThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ReaderThemeMode.light,
                      label: Text('浅色'),
                    ),
                    ButtonSegment(
                      value: ReaderThemeMode.warm,
                      label: Text('暖色'),
                    ),
                    ButtonSegment(
                      value: ReaderThemeMode.dark,
                      label: Text('深色'),
                    ),
                  ],
                  selected: {value.theme},
                  onSelectionChanged: (selection) => setSheetState(
                    () => value = value.copyWith(theme: selection.single),
                  ),
                ),
                const SizedBox(height: AppTokens.spacingM),
                FilledButton(
                  key: const Key('save-reader-settings'),
                  onPressed: () async {
                    await ref
                        .read(readerRepositoryProvider)
                        .savePreferences(
                          value.copyWith(updatedAt: DateTime.now().toUtc()),
                        );
                    notifyRepositoryChanged(
                      ref,
                      areas: const [RepositoryDataArea.reader],
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderSlider extends StatelessWidget {
  const _ReaderSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 72, child: Text(label)),
      Expanded(
        child: Slider(value: value, min: min, max: max, onChanged: onChanged),
      ),
      SizedBox(width: 42, child: Text(value.toStringAsFixed(1))),
    ],
  );
}

class _ReaderPalette {
  const _ReaderPalette(this.background, this.text, this.secondaryText);

  final Color background;
  final Color text;
  final Color secondaryText;

  static _ReaderPalette of(ReaderThemeMode mode) => switch (mode) {
    ReaderThemeMode.light => const _ReaderPalette(
      Color(0xFFFFFCFE),
      Color(0xFF303142),
      Color(0xFF7D8192),
    ),
    ReaderThemeMode.warm => const _ReaderPalette(
      Color(0xFFFFF7E8),
      Color(0xFF42382F),
      Color(0xFF84766A),
    ),
    ReaderThemeMode.dark => const _ReaderPalette(
      Color(0xFF171824),
      Color(0xFFF3F3F8),
      Color(0xFFA8AABB),
    ),
  };
}
