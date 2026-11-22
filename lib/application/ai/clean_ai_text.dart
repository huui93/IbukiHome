String cleanAiText(String value) {
  var output = value.replaceAll('\ufeff', '').trim();
  if (output.isEmpty) {
    return '';
  }
  final fenced = RegExp(
    r'^```(?:text|markdown|md|plaintext)?\s*([\s\S]*?)\s*```$',
    caseSensitive: false,
  ).firstMatch(output);
  if (fenced != null) {
    output = fenced.group(1)!.trim();
  }
  final introductions = [
    RegExp(r'^好的[，,。!！\s]*(?:以下|下面)?(?:是|为)?[^：:\n]{0,16}[：:]?\s*'),
    RegExp(r'^(?:以下|下面)(?:是|为)?[^：:\n]{0,16}[：:]\s*'),
  ];
  for (final pattern in introductions) {
    final updated = output.replaceFirst(pattern, '').trim();
    if (updated != output) {
      output = updated;
      break;
    }
  }
  output = output.replaceAll(RegExp(r'\n[ \t]+'), '\n');
  output = output.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return output.trim();
}
