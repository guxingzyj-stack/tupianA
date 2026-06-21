import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const int uploadImageMaxDimension = 1536;
const int uploadImageJpegQuality = 90;

Future<Uint8List> prepareUploadImageBytes(
  File file, {
  int maxDimension = uploadImageMaxDimension,
  int jpegQuality = uploadImageJpegQuality,
}) async {
  return optimizeUploadImageBytes(
    await file.readAsBytes(),
    maxDimension: maxDimension,
    jpegQuality: jpegQuality,
  );
}

Uint8List optimizeUploadImageBytes(
  Uint8List original, {
  int maxDimension = uploadImageMaxDimension,
  int jpegQuality = uploadImageJpegQuality,
}) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(original);
  } catch (_) {
    return original;
  }
  if (decoded == null) {
    return original;
  }

  final oriented = img.bakeOrientation(decoded);
  final longest = math.max(oriented.width, oriented.height);
  final prepared = longest > maxDimension
      ? img.copyResize(
          oriented,
          width: oriented.width >= oriented.height ? maxDimension : null,
          height: oriented.height > oriented.width ? maxDimension : null,
          interpolation: img.Interpolation.average,
        )
      : oriented;

  final encoded = img.encodeJpg(prepared, quality: jpegQuality);
  if (longest <= maxDimension && encoded.length >= original.length) {
    return original;
  }
  return encoded;
}
