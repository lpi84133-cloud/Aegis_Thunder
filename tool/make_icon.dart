import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final src = File('assets/icon.png').readAsBytesSync();
  final original = img.decodePng(src)!;

  // We want the output to be a square where the original image
  // fits inside with ~14% padding on every side, centred.
  // This guarantees the full artwork is visible even in a circular crop.
  final padding = 0.14;

  // The canvas is a square equal to the longer edge of the original.
  final longerEdge = original.width > original.height ? original.width : original.height;
  final canvasSize = longerEdge;

  // Scale the original so it occupies (1 - 2*padding) of the canvas.
  final targetSize = (canvasSize * (1.0 - 2 * padding)).round();

  final scaled = img.copyResize(original, width: targetSize, height: targetSize, interpolation: img.Interpolation.cubic);

  // Create a dark navy background canvas (matching the game theme #0B0F1A).
  final canvas = img.Image(width: canvasSize, height: canvasSize);
  img.fill(canvas, color: img.ColorRgba8(11, 15, 26, 255));

  // Composite the scaled artwork centred on the canvas.
  final offsetX = ((canvasSize - targetSize) / 2).round();
  final offsetY = ((canvasSize - targetSize) / 2).round();
  img.compositeImage(canvas, scaled, dstX: offsetX, dstY: offsetY);

  final out = img.encodePng(canvas);
  File('assets/icon_padded.png').writeAsBytesSync(out);

  print('Done: assets/icon_padded.png (${canvasSize}x$canvasSize)');
}
