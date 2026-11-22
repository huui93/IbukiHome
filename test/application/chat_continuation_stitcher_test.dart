import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/ai/chat_continuation_stitcher.dart';

void main() {
  group('stitchChatContinuation', () {
    test('removes the longest exact Chinese overlap', () {
      expect(
        stitchChatContinuation('她缓缓推开门，门后的走廊已经完全', '门后的走廊已经完全陷入黑暗。'),
        '她缓缓推开门，门后的走廊已经完全陷入黑暗。',
      );
    });

    test(
      'manual prose separates English words while automatic recovery preserves partial words',
      () {
        expect(
          stitchChatContinuation(
            'READY',
            'Jasmine tea noted.',
            separateWords: true,
          ),
          'READY Jasmine tea noted.',
        );
        expect(
          stitchChatContinuation(
            'Hello.',
            'Next sentence.',
            separateWords: true,
          ),
          'Hello. Next sentence.',
        );
        expect(stitchChatContinuation('unfin', 'ished'), 'unfinished');
        expect(
          stitchChatContinuation('已有正文', '接续中文', separateWords: true),
          '已有正文接续中文',
        );
      },
    );

    test('appends text when there is no overlap', () {
      expect(stitchChatContinuation('她望向窗外。', '天空已经完全亮了。'), '她望向窗外。天空已经完全亮了。');
    });

    test('does not trim accidental three to five rune overlaps', () {
      expect(stitchChatContinuation('然后她', '她转过身。'), '然后她她转过身。');
      expect(stitchChatContinuation('她走到门后的', '门后的灯亮了。'), '她走到门后的门后的灯亮了。');
      expect(
        stitchChatContinuation('hello world', 'world again'),
        'hello worldworld again',
      );
    });

    test('handles English, newlines, quotes, and emoji as Unicode runes', () {
      expect(
        stitchChatContinuation('hello brave world', 'brave world again'),
        'hello brave world again',
      );
      expect(
        stitchChatContinuation('第一行\n这是共同的第二行', '这是共同的第二行\n第三行'),
        '第一行\n这是共同的第二行\n第三行',
      );
      expect(
        stitchChatContinuation('她说：“今晚早点休息”', '“今晚早点休息”以后便离开了。'),
        '她说：“今晚早点休息”以后便离开了。',
      );
      expect(
        stitchChatContinuation('出发🙂继续向遥远的前方', '🙂继续向遥远的前方前进'),
        '出发🙂继续向遥远的前方前进',
      );
    });

    test('supports a complete repeated prefix and caps the search window', () {
      expect(stitchChatContinuation('已有一段完整内容', '已有一段完整内容'), '已有一段完整内容');
      final overlap = List.filled(1200, '长').join();
      final result = stitchChatContinuation('开头$overlap', '$overlap结尾');
      expect(result.length, '开头$overlap'.length + '$overlap结尾'.length - 1024);
    });
  });
}
