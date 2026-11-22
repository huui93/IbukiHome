import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/app/performance/app_performance_policy.dart';

void main() {
  testWidgets('image cache favors stable decoded avatar reuse', (tester) async {
    AppPerformancePolicy.configureImageCache();

    final cache = PaintingBinding.instance.imageCache;
    expect(cache.maximumSize, AppPerformancePolicy.imageCacheEntries);
    expect(cache.maximumSizeBytes, AppPerformancePolicy.imageCacheBytes);
  });
}
