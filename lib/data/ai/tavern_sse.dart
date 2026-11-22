import 'dart:convert';
import '../../application/tavern/provider/tavern_provider_models.dart';

class TavernSseFrame {
  const TavernSseFrame(this.event, this.data);
  final String event, data;
}

Stream<TavernSseFrame> decodeTavernSse(Stream<List<int>> bytes) async* {
  var event = '';
  var size = 0;
  var first = true;
  final data = <String>[];
  await for (var line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (first) {
      line = line.replaceFirst(RegExp(r'^\uFEFF'), '');
      first = false;
    }
    if (line.isEmpty) {
      if (data.isNotEmpty) yield TavernSseFrame(event, data.join('\n'));
      event = '';
      data.clear();
      size = 0;
      continue;
    }
    if (line.startsWith(':')) continue;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'data') {
      size += value.length;
      if (size > 1024 * 1024) {
        throw const TavernProviderFailure(
          TavernProviderErrorKind.malformedResponse,
        );
      }
      data.add(value);
    } else if (field == 'event') {
      event = value;
    }
  }
  // A trailing unterminated event is not a protocol completion signal.
  if (data.isNotEmpty) {
    throw const TavernProviderFailure(TavernProviderErrorKind.incompleteStream);
  }
}
