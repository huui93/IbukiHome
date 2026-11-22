import 'package:flutter/material.dart';
import '../../../domain/chat/chat_image.dart';

class ChatImagePreview extends StatelessWidget {
  const ChatImagePreview({required this.image, this.size = 180, super.key});
  final ChatImage image;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '聊天图片，点击查看',
    button: true,
    child: InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: const Text('图片'),
            ),
            body: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 6,
                child: Image.memory(
                  image.bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(
          image.bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
          errorBuilder: (_, _, _) => SizedBox(
            width: size,
            height: size,
            child: const Center(child: Icon(Icons.broken_image_outlined)),
          ),
        ),
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
                '${image.description}\n\n模型观察，可能有误；作为本会话的记忆资料。',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      if (image.userText.isNotEmpty) const SizedBox(height: 6),
    ],
  );
}
