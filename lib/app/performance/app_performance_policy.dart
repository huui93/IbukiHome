import 'package:flutter/painting.dart';

abstract final class AppPerformancePolicy {
  static const imageCacheEntries = 2048;
  static const imageCacheBytes = 256 * 1024 * 1024;

  static void configureImageCache() {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = imageCacheEntries;
    cache.maximumSizeBytes = imageCacheBytes;
  }
}
