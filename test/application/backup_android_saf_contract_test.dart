import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android SAF preserves the .ibukibackup product extension', () {
    final source = File(
      'android/app/src/main/kotlin/com/ibuki/ibukihome/MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('Intent.ACTION_CREATE_DOCUMENT'));
    expect(source, contains('type = "application/octet-stream"'));
    expect(source, isNot(contains('type = "application/zip"')));
    expect(source, contains('"IbukiHome.ibukibackup"'));
  });
}
