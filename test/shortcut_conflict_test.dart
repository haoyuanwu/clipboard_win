import 'dart:io';

import 'package:clipboard_win/src/app.dart';
import 'package:clipboard_win/src/platform.dart';
import 'package:clipboard_win/src/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shortcut-conflicts-');
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WindowsBridge.channel, null);
    await directory.delete(recursive: true);
  });

  test(
    'tracks each registration failure and clears only the repaired shortcut',
    () async {
      final store = ClipboardStore(
        directory: directory,
        configureStartup: false,
      );
      addTearDown(store.dispose);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WindowsBridge.channel, (call) async {
            if (call.method == 'setShortcut') {
              final args = call.arguments as Map;
              return (args['shortcut'] as Map)['enabled'] == false;
            }
            return null;
          });
      await store.initialize();
      expect(store.shortcutConflicts, {
        'popover': 'Ctrl + Alt + C',
        'transfer': 'Ctrl + Alt + V',
      });
      expect(store.shortcutConflictMessage, contains('打开快捷历史：Ctrl + Alt + C'));
      final original = Map<String, dynamic>.from(
        store.settings['popoverShortcut'],
      );
      expect(
        await store.setting('popoverShortcut', {
          ...original,
          'key': 88,
          'label': 'Ctrl + Alt + X',
        }),
        isFalse,
      );
      expect(store.settings['popoverShortcut'], original);
      expect(store.shortcutConflicts['popover'], 'Ctrl + Alt + X');
      expect(
        await store.setting('popoverShortcut', {...original, 'enabled': false}),
        isTrue,
      );
      expect(store.shortcutConflicts, {'transfer': 'Ctrl + Alt + V'});
    },
  );

  testWidgets(
    'secondary-window notice routes to main-window shortcut settings',
    (tester) async {
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WindowsBridge.channel, (call) async {
            methods.add(call.method);
            return null;
          });
      final store = ClipboardStore(mode: 'transfer', directory: directory);
      addTearDown(store.dispose);
      store.shortcutConflicts['transfer'] = 'Ctrl + Alt + V';
      await tester.pumpWidget(SuperClipboardApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shortcut-conflict-notice')));
      await tester.pumpAndSettle();
      expect(methods, contains('shortcutSettings'));
      expect(find.byType(SettingsPanel), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'conflict notice opens settings with shortcuts visible and marked',
    (tester) async {
      tester.view.physicalSize = const Size(700, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = ClipboardStore(directory: directory, usePlatform: false);
      addTearDown(store.dispose);
      await tester.runAsync(store.initialize);
      store.shortcutConflicts['popover'] = 'Ctrl + Alt + C';
      await tester.pumpWidget(SuperClipboardApp(store: store));
      await tester.pumpAndSettle();
      expect(find.textContaining('打开快捷历史：Ctrl + Alt + C 已被占用'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shortcut-conflict-notice')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SettingsPanel>(find.byType(SettingsPanel)).shortcutsFirst,
        isTrue,
      );
      expect(find.text('Ctrl + Alt + C 已被占用，请重新录制或停用。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      store.shortcutConflicts.clear();
      store.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('shortcut-conflict-notice')),
        findsNothing,
      );
      expect(find.text('Ctrl + Alt + C 已被占用，请重新录制或停用。'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
