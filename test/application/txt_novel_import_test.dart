import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ibukihome/application/projects/txt_novel_source.dart';
import 'package:ibukihome/application/projects/txt_novel_providers.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('UTF-8 and UTF-8 BOM retain Chinese and emoji', () {
    for (final prefix in [
      <int>[],
      [0xef, 0xbb, 0xbf],
    ]) {
      final value = decodeUnicodeNovelText(
        Uint8List.fromList([...prefix, ...utf8.encode('第一章\n你好🌙')]),
      )!;
      expect(value.text, '第一章\n你好🌙');
    }
  });
  for (final little in [true, false]) {
    test('UTF-16 ${little ? 'LE' : 'BE'} preserves surrogate pairs', () {
      final units = '中文🌙\r\n下一章'.codeUnits;
      final bytes = Uint8List.fromList([
        ...little ? [0xff, 0xfe] : [0xfe, 0xff],
        for (final unit in units)
          ...little ? [unit & 255, unit >> 8] : [unit >> 8, unit & 255],
      ]);
      expect(decodeUnicodeNovelText(bytes)!.text, '中文🌙\r\n下一章');
    });
  }
  test('truncated UTF-16 is rejected without replacing characters', () {
    expect(
      () => decodeUnicodeNovelText(Uint8List.fromList([255, 254, 1])),
      throwsFormatException,
    );
    expect(
      () => decodeUnicodeNovelText(Uint8List.fromList([255, 254, 0, 216])),
      throwsFormatException,
    );
  });
  test(
    'legacy decoding uses the native GB18030 adapter only after UTF fails',
    () async {
      var calls = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(TxtNovelDecoder.channel, (call) async {
        expect(call.method, 'decodeLegacyTxt');
        expect((call.arguments as Map)['bytes'], [0xd6, 0xd0, 0xce, 0xc4]);
        calls++;
        return '中文';
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(TxtNovelDecoder.channel, null),
      );
      expect(
        (await const TxtNovelDecoder().decode(
          Uint8List.fromList(utf8.encode('小说')),
        )).encoding,
        'UTF-8',
      );
      expect(calls, 0);
      final decoded = await const TxtNovelDecoder().decode(
        Uint8List.fromList([0xd6, 0xd0, 0xce, 0xc4]),
      );
      expect(decoded.text, '中文');
      expect(decoded.encoding, 'GB18030 / GBK');
      expect(calls, 1);
    },
  );
  test('chunking preserves full text, paragraph boundaries and emoji', () {
    final text = '${'文' * 5999}🌙\r\n${'第二章\n正文\n' * 1500}';
    final parsed = prepareTxtNovel((
      fileName: '小说.TXT',
      text: text,
      encoding: 'UTF-8',
    ));
    expect(parsed.title, '小说');
    expect(parsed.parts.join(), text.replaceAll('\r\n', '\n'));
    expect(parsed.parts.every((p) => p.length <= 6000), isTrue);
    for (final part in parsed.parts) {
      expect(utf8.decode(utf8.encode(part)), part);
    }
  });
  test('files larger than ten megabytes are not truncated', () {
    final text = '中文\n' * 1800000;
    final parsed = prepareTxtNovel((
      fileName: '长篇.txt',
      text: text,
      encoding: 'UTF-8',
    ));
    expect(utf8.encode(text).length, greaterThan(10 * 1024 * 1024));
    expect(parsed.parts.join(), text);
    expect(parsed.characters, text.length);
  });
  for (final input in [
    (fileName: '空白.txt', text: ' \n\t', encoding: 'UTF-8'),
    (fileName: '数据.txt', text: 'abc\x00def', encoding: 'UTF-8'),
    (fileName: '图片.png', text: '正文', encoding: 'UTF-8'),
  ]) {
    test(
      'reject invalid input ${input.fileName}',
      () => expect(() => prepareTxtNovel(input), throwsFormatException),
    );
  }
  test(
    'import creates an independent novel and does not copy another story or chat',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final parsed = prepareTxtNovel((
        fileName: '长篇.txt',
        text: '段落\n' * 3000,
        encoding: 'UTF-8',
      ));
      final imported = await c.read(importTxtNovelProvider)(parsed, '我的小说');
      expect(imported.title, '我的小说');
      expect(imported.systemPrompt, isEmpty);
      final segments = await c
          .read(segmentRepositoryProvider)
          .listSegments(imported.id);
      expect(segments.map((s) => s.content).join(), parsed.parts.join());
      expect(
        segments.map((s) => s.orderIndex),
        List.generate(segments.length, (i) => i),
      );
      expect(
        await c.read(characterRepositoryProvider).listCharacters(imported.id),
        isEmpty,
      );
      expect(await c.read(chatRepositoryProvider).listSessions(), isEmpty);
    },
  );
}
