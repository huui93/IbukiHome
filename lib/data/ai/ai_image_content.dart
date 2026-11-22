import '../../domain/ai/ai_generation.dart';

Object openAiMessageContent(AiGenerationMessage message) =>
    message.images.isEmpty
    ? message.content
    : <Map<String, Object?>>[
        for (final image in message.images)
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:${image.mimeType};base64,${image.base64Data}',
            },
          },
        if (message.content.isNotEmpty)
          {'type': 'text', 'text': message.content},
      ];

Object claudeMessageContent(AiGenerationMessage message) =>
    message.images.isEmpty
    ? message.content
    : <Map<String, Object?>>[
        for (final image in message.images)
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': image.mimeType,
              'data': image.base64Data,
            },
          },
        if (message.content.isNotEmpty)
          {'type': 'text', 'text': message.content},
      ];

List<Map<String, Object?>> geminiMessageParts(AiGenerationMessage message) => [
  for (final image in message.images)
    {
      'inlineData': {'mimeType': image.mimeType, 'data': image.base64Data},
    },
  if (message.content.isNotEmpty) {'text': message.content},
];
