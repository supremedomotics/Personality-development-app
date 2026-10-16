import 'dart:io';

import 'package:crypto/crypto.dart';

import 'local_model.dart';

class IoModelFs implements ModelFs {
  @override
  Future<int?> sizeOf(String path) async {
    final f = File(path);
    return await f.exists() ? await f.length() : null;
  }

  /// Streams the file through SHA-256 (constant memory; slow for multi-GB files).
  @override
  Future<String> sha256Of(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();
}
