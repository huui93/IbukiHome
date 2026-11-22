import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../application/tavern/tavern_presentation_controller.dart';
import '../../../application/tavern/tavern_presentation_providers.dart';
import '../../../domain/tavern/tavern_models.dart';
import 'tavern_widgets.dart';

class TavernTranscript extends StatefulWidget {
  const TavernTranscript({
    required this.controller,
    required this.reading,
    required this.onTurnMenu,
    required this.avatarPath,
    super.key,
  });
  final TavernSessionController controller;
  final TavernReadingStore reading;
  final ValueChanged<TavernTurnProjection> onTurnMenu;
  final String? Function(TavernParticipant?) avatarPath;
  @override
  State<TavernTranscript> createState() => TavernTranscriptState();
}

class TavernTranscriptState extends State<TavernTranscript>
    with WidgetsBindingObserver {
  final scroll = ScrollController(), viewport = GlobalKey();
  final keys = <String, GlobalKey>{};
  Timer? _followTimer, _saveTimer;
  String? _line;
  bool following = true, ready = false;
  int _epoch = 0;
  TavernReadingAnchor? _anchor;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_dataChanged);
    widget.controller.live.addListener(_streamChanged);
    _openLine();
  }

  @override
  void dispose() {
    _save();
    _followTimer?.cancel();
    _saveTimer?.cancel();
    widget.controller.removeListener(_dataChanged);
    widget.controller.live.removeListener(_streamChanged);
    WidgetsBinding.instance.removeObserver(this);
    scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _save();
  }

  @override
  void didChangeMetrics() {
    _streamChanged();
  }

  TavernReadingAnchor _capture() {
    final box = viewport.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      for (final entry in keys.entries) {
        final item =
            entry.value.currentContext?.findRenderObject() as RenderBox?;
        if (item == null || !item.hasSize || !item.attached) continue;
        final y = item.localToGlobal(Offset.zero, ancestor: box).dy;
        if (y <= box.size.height && y + item.size.height >= 0) {
          return TavernReadingAnchor(
            turnId: entry.key,
            y: y,
            following: following,
            pixelHint: scroll.hasClients ? scroll.offset : 0,
          );
        }
      }
    }
    return TavernReadingAnchor(
      turnId: null,
      y: 0,
      following: following,
      pixelHint: scroll.hasClients ? scroll.offset : 0,
    );
  }

  void _save() {
    if (_line == null || !ready || !scroll.hasClients) return;
    unawaited(
      widget.reading.save(widget.controller.sessionId, _line!, _capture()),
    );
  }

  Future<void> savePosition() async {
    _save();
  }

  void _dataChanged() {
    final next = widget.controller.projection?.storyLine.id;
    if (next != _line) {
      _save();
      _openLine();
      return;
    }
    if (!following) {
      _anchor = _capture();
      _restoreAnchor(++_epoch);
    } else {
      _streamChanged();
    }
  }

  Future<void> _openLine() async {
    final line = widget.controller.projection?.storyLine.id;
    if (line == null) return;
    final epoch = ++_epoch;
    _line = line;
    ready = false;
    final anchor = await widget.reading.load(widget.controller.sessionId, line);
    if (!mounted || epoch != _epoch) return;
    _anchor = anchor;
    following = anchor?.following ?? true;
    setState(() => ready = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _epoch || !scroll.hasClients) return;
      scroll.jumpTo(
        following
            ? 0
            : (anchor?.pixelHint ?? 0).clamp(
                0,
                scroll.position.maxScrollExtent,
              ),
      );
      _restoreAnchor(epoch);
    });
  }

  void _restoreAnchor(int epoch) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _epoch || following || !scroll.hasClients) {
        return;
      }
      final item =
          keys[_anchor?.turnId]?.currentContext?.findRenderObject()
              as RenderBox?;
      final box = viewport.currentContext?.findRenderObject() as RenderBox?;
      if (item == null || box == null || !item.attached) return;
      final delta =
          item.localToGlobal(Offset.zero, ancestor: box).dy - (_anchor?.y ?? 0);
      // A reverse list moves content down when its scroll offset increases.
      scroll.jumpTo(
        (scroll.offset - delta).clamp(0, scroll.position.maxScrollExtent),
      );
    });
  }

  void _streamChanged() {
    if (!following) return;
    _followTimer ??= Timer(const Duration(milliseconds: 80), () {
      _followTimer = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && following && scroll.hasClients) scroll.jumpTo(0);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows =
        widget.controller.projection?.turns ?? const <TavernTurnProjection>[];
    if (rows.isEmpty) return const Center(child: Text('故事，从你的第一句话开始。'));
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is UserScrollNotification) {
              _epoch++;
              if (n.direction == ScrollDirection.reverse) following = false;
              if (n.direction == ScrollDirection.idle &&
                  scroll.hasClients &&
                  scroll.offset < 160) {
                following = true;
              }
              _saveTimer?.cancel();
              _saveTimer = Timer(const Duration(milliseconds: 350), _save);
              setState(() {});
            }
            return false;
          },
          child: ListView.builder(
            key: viewport,
            controller: scroll,
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            itemCount: rows.length,
            findChildIndexCallback: (key) => key is ValueKey<String>
                ? (() {
                    final i = rows.indexWhere((r) => r.turn.id == key.value);
                    return i < 0 ? null : rows.length - 1 - i;
                  })()
                : null,
            itemBuilder: (context, index) {
              final row = rows[rows.length - 1 - index];
              return KeyedSubtree(
                key: ValueKey(row.turn.id),
                child: Container(
                  key: keys.putIfAbsent(row.turn.id, GlobalKey.new),
                  child: TavernTurnView(
                    row: row,
                    controller: widget.controller,
                    onMenu: () => widget.onTurnMenu(row),
                    avatarPath: widget.avatarPath,
                  ),
                ),
              );
            },
          ),
        ),
        if (!following)
          Positioned(
            right: 12,
            bottom: 12,
            child: IconButton.filledTonal(
              key: const Key('tavern-bottom'),
              tooltip: '回到最新',
              onPressed: () {
                setState(() => following = true);
                _streamChanged();
              },
              icon: const Icon(Icons.arrow_downward),
            ),
          ),
      ],
    );
  }
}

class TavernTurnView extends StatelessWidget {
  const TavernTurnView({
    required this.row,
    required this.controller,
    required this.onMenu,
    required this.avatarPath,
    super.key,
  });
  final TavernTurnProjection row;
  final TavernSessionController controller;
  final VoidCallback onMenu;
  final String? Function(TavernParticipant?) avatarPath;
  @override
  Widget build(BuildContext context) {
    final participant = controller.participants
        .where((p) => p.id == row.turn.participantId)
        .firstOrNull;
    final narrator = row.turn.role == TavernTurnRole.narrator,
        player = row.turn.role == TavernTurnRole.player,
        event = row.turn.role == TavernTurnRole.system;
    final name = narrator
        ? '旁白'
        : event
        ? '故事动态'
        : participant?.displayName ?? '角色暂不可用';
    final own = row.turn.storyLineId == controller.projection?.storyLine.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!narrator && !event) ...[
                TavernAvatar(name, path: avatarPath(participant), size: 28),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  player ? '$name · 你' : name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                key: Key('tavern-turn-menu-${row.turn.id}'),
                tooltip: '本轮选项',
                onPressed: onMenu,
                icon: const Icon(Icons.more_horiz),
              ),
            ],
          ),
          if (row.alternatives.length > 1)
            Row(
              children: [
                IconButton(
                  tooltip: '上一种回答',
                  onPressed: own ? () => _answer(-1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  '回答 ${row.alternatives.indexWhere((a) => a.id == row.selectedAlternative.id) + 1} / ${row.alternatives.length}',
                ),
                IconButton(
                  tooltip: '下一种回答',
                  onPressed: own ? () => _answer(1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
                if (!own)
                  const Expanded(
                    child: Text('已冻结', textAlign: TextAlign.right),
                  ),
              ],
            ),
          _LiveParts(
            row: row,
            controller: controller,
            narrator: narrator,
            player: player,
            event: event,
          ),
          if (controller.partials[row.selectedAlternative.id]?.isNotEmpty ==
              true)
            ExpansionTile(
              title: const Text('未完成的回应'),
              subtitle: const Text('已保存的部分内容，不作为完成回答。'),
              children: [
                TavernPartsView(
                  parts: controller.partials[row.selectedAlternative.id]!,
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _answer(int delta) {
    final i = row.alternatives.indexWhere(
      (a) => a.id == row.selectedAlternative.id,
    );
    final next = (i + delta) % row.alternatives.length;
    unawaited(controller.selectAnswer(row, row.alternatives[next].id));
  }
}

class _LiveParts extends StatefulWidget {
  const _LiveParts({
    required this.row,
    required this.controller,
    required this.narrator,
    required this.player,
    required this.event,
  });
  final TavernTurnProjection row;
  final TavernSessionController controller;
  final bool narrator, player, event;
  @override
  State<_LiveParts> createState() => _LivePartsState();
}

class _LivePartsState extends State<_LiveParts> {
  bool _wasLive = false;
  @override
  void initState() {
    super.initState();
    widget.controller.live.addListener(_change);
  }

  @override
  void dispose() {
    widget.controller.live.removeListener(_change);
    super.dispose();
  }

  void _change() {
    final active =
        widget.controller.live.value.target?.turnId == widget.row.turn.id;
    if (active || _wasLive) setState(() {});
    _wasLive = active;
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.controller.live.value;
    final parts = <String, TavernContentPart>{
      for (final p in widget.row.selectedParts) p.id: p,
    };
    if (live.target?.alternativeId == widget.row.selectedAlternative.id) {
      for (final p in live.parts) {
        parts[p.id] = p;
      }
    }
    final values = parts.values.toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    final selected = TavernPartsView(
      parts: values,
      narrator: widget.narrator,
      player: widget.player,
      event: widget.event,
    );
    if (live.target?.turnId == widget.row.turn.id &&
        live.target?.alternativeId != widget.row.selectedAlternative.id) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          selected,
          const SizedBox(height: 12),
          Text('另一种回答 · 正在生成', style: Theme.of(context).textTheme.labelMedium),
          TavernPartsView(parts: live.parts),
        ],
      );
    }
    return selected;
  }
}

class TavernPartsView extends StatelessWidget {
  const TavernPartsView({
    required this.parts,
    this.narrator = false,
    this.player = false,
    this.event = false,
    super.key,
  });
  final List<TavernContentPart> parts;
  final bool narrator, player, event;
  @override
  Widget build(BuildContext context) {
    final visible = <Widget>[];
    final text = StringBuffer();
    void flushText() {
      if (text.isEmpty) return;
      visible.add(
        Padding(
          padding: EdgeInsets.symmetric(horizontal: narrator ? 12 : 0),
          child: SelectableText(
            text.toString(),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.65,
              color: narrator
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : null,
              fontStyle: player ? FontStyle.italic : null,
            ),
          ),
        ),
      );
      text.clear();
    }

    for (final part in parts) {
      if (part.kind == TavernContentKind.text) {
        text.write(part.text ?? '');
      } else if (part.kind == TavernContentKind.event ||
          part.kind == TavernContentKind.attachment) {
        flushText();
        visible.add(
          Text(
            part.kind == TavernContentKind.event
                ? part.text ?? ''
                : '附件 · ${part.mimeType ?? ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      }
    }
    flushText();
    final reasoning = parts.where(
      (p) =>
          p.kind == TavernContentKind.reasoning ||
          p.kind == TavernContentKind.reasoningSummary ||
          p.kind == TavernContentKind.reasoningUnavailable,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...visible,
        if (reasoning.isNotEmpty)
          ExpansionTile(
            key: ValueKey('reasoning-${parts.first.alternativeId}'),
            title: const Text('推理信息'),
            children: [
              for (final p in reasoning)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(switch (p.kind) {
                        TavernContentKind.reasoning => '模型原生推理',
                        TavernContentKind.reasoningSummary => '模型推理摘要',
                        _ => '推理不可用',
                      }),
                      if (p.kind != TavernContentKind.reasoningUnavailable)
                        SelectableText(
                          p.text ?? '',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
