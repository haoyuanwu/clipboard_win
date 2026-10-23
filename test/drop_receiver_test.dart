import 'dart:async';
import 'dart:io';

import 'package:clipboard_win/src/platform.dart';
import 'package:clipboard_win/src/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native folder drop opens transfer and broadcasts its grouping decision',
    () async {
      final directory = await Directory.systemTemp.createTemp('receiver-drop-');
      final folder = await Directory('${directory.path}/source-folder')
          .create();
      await File('${folder.path}/one.txt').writeAsString('one');
      final store = ClipboardStore(
        directory: Directory('${directory.path}/app'),
        configureStartup: false,
        captureClipboard: false,
      );
      final events = <String>[];
      final pending = Completer<Map>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(WindowsBridge.channel, (call) async {
        if (call.method == 'setShortcut') return true;
        if (call.method == 'show') {
          expect(call.arguments, 'transfer');
          events.add('show');
        }
        if (call.method == 'broadcast') {
          final state = call.arguments as Map;
          if ((state['folderDrops'] as List).isNotEmpty &&
              !pending.isCompleted) {
            events.add('decision');
            pending.complete(state);
          }
        }
        return null;
      });
      try {
        await store.initialize();
        const codec = StandardMethodCodec();
        final delivered = Completer<void>();
        // Simulate the native-to-Dart method call, not just a direct store command.
        messenger.handlePlatformMessage(
          'superclipboard/platform',
          codec.encodeMethodCall(
            MethodCall('drop', {
              'paths': [folder.path],
            }),
          ),
          (_) => delivered.complete(),
        );
        await delivered.future;
        final snapshot = await pending.future.timeout(
          const Duration(seconds: 10),
        );
        expect(events, ['show', 'decision']);
        expect((snapshot['folderDrops'] as List).single['folders'], [
          folder.path,
        ]);
        expect(store.transfer, isEmpty);
        expect(
          await store.command({
            'op': 'resolveFolderDrop',
            'id': store.folderDrops.single['id'],
            'choice': 'group',
            'remember': false,
          }),
          isTrue,
        );
        expect(store.folderDrops, isEmpty);
        expect(store.transfer, hasLength(1));
        expect(await File('${folder.path}/one.txt').readAsString(), 'one');
      } finally {
        store.dispose();
        messenger.setMockMethodCallHandler(WindowsBridge.channel, null);
        await directory.delete(recursive: true);
      }
    },
  );
}
