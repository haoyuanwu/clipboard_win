import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app.dart';
import 'src/store.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) MediaKit.ensureInitialized();
  final mode =
      args.isNotEmpty && ['main', 'popover', 'transfer'].contains(args.first)
      ? args.first
      : 'main';
  final dataIndex = args.indexOf('--data-dir');
  final store = ClipboardStore(
    mode: mode,
    directory: dataIndex >= 0 && dataIndex + 1 < args.length
        ? Directory(args[dataIndex + 1])
        : null,
    configureStartup: !args.contains('--no-startup'),
    captureClipboard: !args.contains('--no-capture'),
  );
  try {
    await store.initialize();
  } catch (e) {
    store.error = '启动失败：$e。请退出后重新打开。';
  }
  runApp(SuperClipboardApp(store: store));
}
