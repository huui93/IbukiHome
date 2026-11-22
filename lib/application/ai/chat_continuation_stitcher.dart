const int chatContinuationMaxOverlapRunes = 1024;
const int chatContinuationMinimumOverlapRunes = 8;

String stitchChatContinuation(
  String existing,
  String continuation, {
  bool separateWords = false,
  int maxOverlapRunes = chatContinuationMaxOverlapRunes,
  int minimumOverlapRunes = chatContinuationMinimumOverlapRunes,
}) {
  if (existing.isEmpty || continuation.isEmpty) return '$existing$continuation';
  final left = existing.runes.toList(growable: false);
  final right = continuation.runes.toList(growable: false);
  final maximum = [
    left.length,
    right.length,
    maxOverlapRunes,
  ].reduce((value, item) => value < item ? value : item);
  var overlap = 0;
  for (var length = maximum; length >= minimumOverlapRunes; length -= 1) {
    var matches = true;
    final leftStart = left.length - length;
    for (var index = 0; index < length; index += 1) {
      if (left[leftStart + index] != right[index]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      overlap = length;
      break;
    }
  }
  // Manual continuation begins a new piece of prose. Automatic recovery can
  // resume in the middle of a word, so it keeps byte-for-byte concatenation.
  if (separateWords &&
      overlap == 0 &&
      RegExp(r'[A-Za-z0-9.!?]$').hasMatch(existing) &&
      RegExp(r'^[A-Za-z0-9]').hasMatch(continuation)) {
    return '$existing $continuation';
  }
  return String.fromCharCodes([...left, ...right.skip(overlap)]);
}
