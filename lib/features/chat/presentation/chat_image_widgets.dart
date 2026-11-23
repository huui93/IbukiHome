import 'package:flutter/material.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../domain/chat/chat_image.dart';

class ChatImagePreview extends StatefulWidget {
  const ChatImagePreview({required this.image, this.size = 180, super.key});

  final ChatImage image;
  final double size;

  @override
  State<ChatImagePreview> createState() => _ChatImagePreviewState();
}

class _ChatImagePreviewState extends State<ChatImagePreview> {
  MemoryImage? _image;

  MemoryImage? _loadImage() {
    try {
      return MemoryImage(widget.image.bytes);
    } on FormatException {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _image = _loadImage();
  }

  @override
  void didUpdateWidget(covariant ChatImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reloading a persisted message creates new bytes even when recognition
    // only changed the description. Keep the same decoded image cache key.
    if (oldWidget.image.base64Data != widget.image.base64Data) {
      _image = _loadImage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pixels = (widget.size * MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(1, 768);
    final colors = Theme.of(context).colorScheme;
    final source = _image;
    return Semantics(
      label: context.tr('聊天图片，点击查看'),
      button: true,
      child: InkWell(
        onTap: source == null ? null : _open,
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox.square(
            key: const Key('chat-image-thumbnail-box'),
            dimension: widget.size,
            child: ColoredBox(
              color: colors.surfaceContainer,
              child: source == null
                  ? _unavailable(context)
                  : Image(
                      image: ResizeImage(
                        source,
                        width: pixels,
                        height: pixels,
                        policy: ResizeImagePolicy.fit,
                      ),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      frameBuilder: (context, child, frame, synchronous) {
                        if (synchronous || frame != null) return child;
                        return const Center(child: Icon(Icons.image_outlined));
                      },
                      errorBuilder: (context, _, _) => _unavailable(context),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _unavailable(BuildContext context) => Center(
    child: Text(
      context.tr('无法显示图片'),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
  );

  void _open() {
    final source = _image;
    if (source == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(context.tr('图片')),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 6,
              child: Image(
                image: source,
                fit: BoxFit.contain,
                errorBuilder: (context, _, _) => Text(
                  context.tr('无法显示图片'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChatImagePlaceholder extends StatelessWidget {
  const ChatImagePlaceholder({required this.loading, super.key});
  final bool loading;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 180,
    child: Center(
      child: loading
          ? const Icon(Icons.image_outlined, color: Colors.white)
          : Text(
              context.tr('无法显示图片'),
              style: const TextStyle(color: Colors.white),
            ),
    ),
  );
}

class ChatImageDraft extends StatelessWidget {
  const ChatImageDraft({
    required this.image,
    required this.onRemove,
    super.key,
  });
  final ChatImage image;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('chat-image-draft'),
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
    child: Row(
      children: [
        ChatImagePreview(image: image, size: 72),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('图片已准备好\n可以补充问题后发送', style: TextStyle(fontSize: 13)),
        ),
        IconButton(
          key: const Key('chat-remove-image'),
          tooltip: '移除图片',
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
}

class ChatImageRecord extends StatelessWidget {
  const ChatImageRecord({required this.image, super.key});
  final ChatImage image;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      ChatImagePreview(image: image),
      if (image.description == null)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            '图片待识别 · 可重试生成',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        )
      else
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const Key('chat-image-description'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            dense: true,
            iconColor: Colors.white,
            collapsedIconColor: Colors.white,
            title: const Text(
              '查看识图记录',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
            children: [
              Text(
                '${image.description}\n\n模型观察，可能有误。描述保存在本会话的图片记录中。',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      if (image.userText.isNotEmpty) const SizedBox(height: 6),
    ],
  );
}
