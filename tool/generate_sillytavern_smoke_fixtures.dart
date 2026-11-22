import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:ibukihome/application/import/sillytavern_parser.dart';

// Synthetic, redistributable input only. No imported JavaScript is executed.
Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    final file = File(args.single);
    final result = const SillyTavernParser().parse(
      await file.readAsBytes(),
      fileName: file.uri.pathSegments.last,
    );
    stdout.writeln(
      jsonEncode({
        'format': result.sourceFormat,
        'version': result.sourceVersion,
        'greetings': result.characterCard?.alternateGreetings.length,
        'lore': result.characterCard?.characterBook?.entries.length,
        'extensions': result.extensionSummaries
            .map((e) => {'kind': e.kind.name, 'chars': e.encodedChars})
            .toList(),
        'securityFlags': result.security.flags,
      }),
    );
    return;
  }
  final out = Directory('artifacts/sillytavern-compat/fixtures');
  await out.create(recursive: true);
  await _json(out, 'ST-Rin-persona.json', {
    'personas': {'rin.png': 'Rin'},
    'persona_descriptions': {
      'rin.png': {
        'description': 'A visiting Master who enjoys sharing tea.',
        'position': 0,
      },
    },
    'default_persona': 'rin.png',
  });
  await _json(out, 'ST-Cafe-lorebook.json', {
    'name': 'Cafe Book',
    'entries': [
      {
        'uid': 1,
        'comment': 'Evening cafe',
        'content': 'The cafe stays open until midnight.',
        'constant': true,
      },
      {
        'uid': 2,
        'comment': 'Tea',
        'content': 'The tea counter serves warm green tea.',
        'key': ['tea'],
        'sticky': 2,
      },
    ],
  });
  for (final name in ['Mira', 'Morgan']) {
    final card = <String, Object?>{
      'spec': 'chara_card_v3',
      'spec_version': '3.0',
      'data': {
        'name': '$name Local',
        'description': 'A calm traveler at the cafe.',
        'personality': 'Thoughtful and friendly.',
        'scenario': 'An evening at the cafe.',
        'first_mes': 'Welcome. Shall we have tea?',
        'alternate_greetings': ['Good evening.', 'There you are.'],
        'mes_example': '<START>\n{{char}}: The tea is ready.',
        'system_prompt': 'Keep the character voice calm.',
        'creator': 'IbukiHome synthetic tests',
        'character_book': {
          'name': '$name Book',
          'entries': [
            {
              'id': 1,
              'keys': ['tea'],
              'content': '$name enjoys tea.',
            },
          ],
        },
        'extensions': {
          'future_ibuki_test': {'preserved': true},
          'tavern_helper': {
            'script': 'document.createElement("button");',
            'reference': 'https://invalid.example.test/never-requested.js',
          },
          'api_key': 'synthetic-not-a-key',
        },
      },
    };
    final pixels = BytesBuilder();
    for (var y = 0; y < 64; y++) {
      pixels.addByte(0);
      for (var x = 0; x < 64; x++) {
        pixels.add(name == 'Mira' ? [96, 182, 162] : [188, 132, 155]);
      }
    }
    final header = ByteData(13)
      ..setUint32(0, 64)
      ..setUint32(4, 64)
      ..setUint8(8, 8)
      ..setUint8(9, 2);
    final png = BytesBuilder()
      ..add([137, 80, 78, 71, 13, 10, 26, 10])
      ..add(_chunk('IHDR', header.buffer.asUint8List()))
      ..add(
        _chunk(
          'tEXt',
          latin1.encode(
            'ccv3\u0000${base64Encode(utf8.encode(jsonEncode(card)))}',
          ),
        ),
      )
      ..add(_chunk('IDAT', zlib.encode(pixels.takeBytes())))
      ..add(_chunk('IEND', []));
    await File('${out.path}/ST-$name-card.png').writeAsBytes(png.takeBytes());
  }
  stdout.writeln('Created four local synthetic fixtures in ${out.path}');
}

Future<void> _json(Directory directory, String name, Object value) => File(
  '${directory.path}/$name',
).writeAsString(const JsonEncoder.withIndent('  ').convert(value)).then((_) {});

Uint8List _chunk(String type, List<int> bytes) {
  final body = [...ascii.encode(type), ...bytes];
  return (BytesBuilder()
        ..add((ByteData(4)..setUint32(0, bytes.length)).buffer.asUint8List())
        ..add(body)
        ..add((ByteData(4)..setUint32(0, getCrc32(body))).buffer.asUint8List()))
      .takeBytes();
}
