import 'dart:async';
import 'dart:convert';

/// Decodes SSE data fields independently of TCP and UTF-8 chunk boundaries.
Stream<String> decodeSseData(Stream<List<int>> byteStream) async* {
  final dataLines = <String>[];
  await for (final line
      in byteStream.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (dataLines.isNotEmpty) {
        yield dataLines.join('\n');
        dataLines.clear();
      }
      continue;
    }
    if (line.startsWith(':')) continue;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    if (field != 'data') continue;
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    dataLines.add(value);
  }
  if (dataLines.isNotEmpty) yield dataLines.join('\n');
}
