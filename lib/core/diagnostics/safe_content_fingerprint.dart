import 'dart:convert';

import 'package:crypto/crypto.dart';

String safeContentFingerprint(String value) {
  return sha256.convert(utf8.encode(value)).toString();
}

String anonymizedIdentifier(String value) {
  return safeContentFingerprint(value).substring(0, 16);
}
