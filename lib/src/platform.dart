import 'dart:async';

import 'package:flutter/services.dart';

class WindowsBridge {
  static const channel = MethodChannel('superclipboard/platform');
  static Future<T?> call<T>(String method, [dynamic args]) =>
      channel.invokeMethod<T>(method, args);

  /// A secondary engine can start Dart before its host has registered handlers.
  static Future<Map?> connect() async {
    for (var attempt = 0; attempt < 80; attempt++) {
      try {
        return await call<Map>('ready');
      } on MissingPluginException {
        if (attempt == 79) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
    return null;
  }
}
