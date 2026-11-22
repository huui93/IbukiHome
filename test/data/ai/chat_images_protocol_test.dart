import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ibukihome/data/ai/ai_provider_registry.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';
import '../../helpers/chat_image_fixture.dart';
import 'provider_expansion_test.dart' as fixtures;

void main() {
  for (final type in AiProviderType.values) {
    for (final stream in [false, true]) {
      test(
        '${type.name}: image parts retain text and binary MIME in ${stream ? 'stream' : 'buffered'} transport',
        () async {
          late http.Request sent;
          final client = AiProviderRegistry(
            httpClientFactory: () => MockClient((req) async {
              sent = req;
              return http.Response.bytes(
                utf8.encode(
                  stream
                      ? fixtures.streaming(type)
                      : fixtures.nonStreaming(type),
                ),
                200,
                headers: {
                  'content-type': stream
                      ? 'text/event-stream'
                      : 'application/json',
                },
              );
            }),
          ).create(fixtures.config(type), 'synthetic-key');
          addTearDown(client.close);
          final request = AiGenerationRequest(
            requestId: 'image',
            systemPrompt: 'observe',
            model: 'configured-model',
            maxTokens: 512,
            messages: const [
              AiGenerationMessage(
                role: AiMessageRole.user,
                content: '这是什么？',
                images: [
                  AiImageInput(
                    mimeType: 'image/png',
                    base64Data: imageFixtureBase64,
                  ),
                ],
              ),
            ],
          );
          final text = stream
              ? (await client.streamEvents(request).toList())
                    .map((e) => e.content)
                    .join()
              : await client.generate(request);
          expect(text, '你好');
          final body = jsonDecode(sent.body) as Map;
          if (type == AiProviderType.gemini) {
            expect(body['contents'][0]['parts'], [
              {
                'inlineData': {
                  'mimeType': 'image/png',
                  'data': imageFixtureBase64,
                },
              },
              {'text': '这是什么？'},
            ]);
          } else if (type == AiProviderType.claude) {
            expect(body['messages'][0]['content'], [
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': 'image/png',
                  'data': imageFixtureBase64,
                },
              },
              {'type': 'text', 'text': '这是什么？'},
            ]);
            expect(body['system'], 'observe');
          } else {
            expect(body['messages'][1]['content'], [
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/png;base64,$imageFixtureBase64',
                },
              },
              {'type': 'text', 'text': '这是什么？'},
            ]);
          }
        },
      );
    }
  }
}
