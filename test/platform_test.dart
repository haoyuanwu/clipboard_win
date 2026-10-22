import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clipboard_win/src/platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'secondary engine waits for native registration and receives shared state',
    () async {
      var calls = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(WindowsBridge.channel, (call) async {
        expect(call.method, 'ready');
        if (++calls < 3) throw MissingPluginException();
        return {
          'history': [],
          'settings': {'sort': 'count'},
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(WindowsBridge.channel, null),
      );
      final state = await WindowsBridge.connect();
      expect(calls, 3);
      expect(state!['settings']['sort'], 'count');
    },
  );
}
