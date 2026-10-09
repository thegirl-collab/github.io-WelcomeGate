import 'dart:typed_data';
import 'package:flutter/services.dart';

class PickedLocalFile {
  PickedLocalFile({required this.name, required this.bytes, required this.mime});
  final String name;
  final Uint8List bytes;
  final String mime;
}

class LocalFiles {
  static const _channel = MethodChannel('com.snyderfamily/files');

  static Future<String?> saveBytes({required String fileName, required String mime, required Uint8List bytes}) async {
    final result = await _channel.invokeMethod<String>('saveBytes', {
      'fileName': fileName,
      'mime': mime,
      'bytes': bytes,
    });
    return result;
  }

  static Future<PickedLocalFile?> pickFile({List<String> mimeTypes = const ['*/*']}) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('pickFile', {'mimeTypes': mimeTypes});
    if (result == null) return null;
    final raw = result['bytes'];
    if (raw is! Uint8List) return null;
    return PickedLocalFile(
      name: result['name']?.toString() ?? 'file',
      bytes: raw,
      mime: result['mime']?.toString() ?? 'application/octet-stream',
    );
  }
}