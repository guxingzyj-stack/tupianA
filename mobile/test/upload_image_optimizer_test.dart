import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:lao_zhao/core/image/upload_image_optimizer.dart';
import 'package:test/test.dart';

void main() {
  test('large upload images are resized to the configured longest edge', () {
    final source = img.Image(width: 2400, height: 1600);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(
          x,
          y,
          (x * 17 + y * 3) % 256,
          (x * 5 + y * 11) % 256,
          (x * 13 + y * 7) % 256,
        );
      }
    }
    final original = img.encodeJpg(source, quality: 100);

    final optimized = optimizeUploadImageBytes(original);
    final decoded = img.decodeImage(optimized);

    expect(decoded, isNotNull);
    expect(decoded!.width, 1536);
    expect(decoded.height, 1024);
    expect(optimized.length, lessThan(original.length));
  });

  test('undecodable input is returned unchanged', () {
    final original = Uint8List.fromList([1, 2, 3, 4, 5]);

    final optimized = optimizeUploadImageBytes(original);

    expect(optimized, original);
  });
}
