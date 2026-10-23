import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clipboard_win/src/app.dart';
import 'package:clipboard_win/src/store.dart';
import 'package:clipboard_win/src/model.dart';

class _UiStore extends ClipboardStore {
  _UiStore({required super.directory}) : super(usePlatform: false);
  Future<bool>? pendingSetting;
  @override
  Future<bool> setting(String key, dynamic value) =>
      pendingSetting = super.setting(key, value);
}

class _QuickCopyStore extends ClipboardStore {
  _QuickCopyStore({required super.directory})
    : super(mode: 'popover', usePlatform: false);
  String? copied;
  @override
  Future<bool> copy(ClipEntry e) async {
    copied = e.id;
    return true;
  }
}

class _StoragePreviewStore extends ClipboardStore {
  _StoragePreviewStore({required super.directory}) : super(usePlatform: false);
  @override
  Future<bool> setting(String key, dynamic value) async {
    settings[key] = value;
    notifyListeners();
    return true;
  }
}

class _FolderPromptStore extends ClipboardStore {
  _FolderPromptStore({required super.directory})
    : super(mode: 'transfer', usePlatform: false);
  final resolved = <Map<String, dynamic>>[];
  @override
  Future<bool> command(Map<String, dynamic> action) async {
    resolved.add(action);
    folderDrops.removeWhere((e) => e['id'] == action['id']);
    notifyListeners();
    return true;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final latin = FontLoader('Segoe UI')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
          ),
        ),
      );
    await latin.load();
    final chinese = FontLoader('Microsoft YaHei UI')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
          ),
        ),
      );
    final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
      ..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      );
    await chinese.load();
    final defaultFont = FontLoader('Ahem')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
          ),
        ),
      );
    await defaultFont.load();
    await icons.load();
    final material = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await material.load();
  });
  late Directory directory;
  late _UiStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('superclipboard-ui-');
    store = _UiStore(directory: directory);
    await store.initialize();
    await store.command({
      'op': 'ingest',
      'data': {'text': '让每一次复制，都有迹可循。', 'source': '记事本', 'tint': 0xff0078d4},
    });
    await store.command({
      'op': 'ingest',
      'data': {
        'text': 'SuperClipboard\n文字、图片、文件、视频，随时找回。',
        'source': 'Microsoft Edge',
        'tint': 0xff159b87,
      },
    });
  });
  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });
  testWidgets(
    'source icons keep the same right inset across names and image states',
    (tester) async {
      final now = DateTime.now();
      store.history = [
        for (final (index, source, icon) in [
          (0, '记事本', ''),
          (
            1,
            'Microsoft Visual Studio Code',
            '${Directory.current.path}/assets/app_logo.png',
          ),
          (2, 'Shell', '${directory.path}/missing-icon.png'),
        ])
          ClipEntry(
            id: 'source-$index',
            fingerprint: 'source-$index',
            kind: EntryKind.text,
            createdAt: now,
            lastCopiedAt: now,
            text: '来源图标对齐',
            source: source,
            sourceIcon: icon,
            count: index == 2 ? 999 : 1,
            pinned: index == 1,
          ),
      ];
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundaryKey = GlobalKey();
      for (final width in [440.0, 420.0]) {
        tester.view.physicalSize = Size(width, 720);
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: SuperClipboardApp(store: store),
          ),
        );
        await tester.pumpAndSettle();
        final iconRights = <double>[];
        for (final element in find.byType(HistoryCard).evaluate()) {
          final card = find.byElementPredicate((e) => e == element);
          final icon = find.descendant(
            of: card,
            matching: find.byType(SourceIcon),
          );
          final rect = tester.getRect(icon);
          expect(rect.size, const Size(20, 20));
          expect(rect.right, tester.getRect(card).right - 16);
          iconRights.add(rect.right);
        }
        expect(iconRights, hasLength(3));
        expect(iconRights.toSet(), hasLength(1));
        expect(tester.takeException(), isNull);
        if (width == 440) {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('build/source-icon-alignment.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets(
    'storage preferences have clear groups and keep controls usable at narrow widths',
    (tester) async {
      final preferences = _StoragePreviewStore(directory: directory);
      addTearDown(preferences.dispose);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      preferences.notebookPath =
          r'C:\Users\Administrator\AppData\Roaming\SuperClipboard\Notebook';
      final boundaryKey = GlobalKey();
      for (final dark in [true, false]) {
        tester.view.physicalSize = const Size(420, 720);
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff1f5ce0),
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
                fontFamily: ReplicaMetrics.fontFamily,
                fontFamilyFallback: ReplicaMetrics.fontFallback,
              ),
              home: Scaffold(
                backgroundColor: dark
                    ? const Color(0xff23262d)
                    : const Color(0xfff3f3f3),
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ListenableBuilder(
                      listenable: preferences,
                      builder: (_, _) =>
                          TransferStorageSettings(store: preferences),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('悬浮中转'), findsOneWidget);
        expect(find.text('记事本'), findsOneWidget);
        expect(find.byType(Divider), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('build/settings-storage-${dark ? 'dark' : 'light'}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.tap(find.byTooltip('拖入文件夹'));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('作为文件组').last);
        });
        await tester.pumpAndSettle();
        expect(preferences.settings['folderDropMode'], 'group');
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('增加清空时间'));
        });
        await tester.pumpAndSettle();
        expect(preferences.settings['transferMinutes'], dark ? 11 : 12);
        tester.view.physicalSize = const Size(320, 720);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets(
    'transfer engine presents queued folder prompts and resolves each only once',
    (tester) async {
      final remote = _FolderPromptStore(directory: directory);
      remote.folderDrops = [
        {
          'id': 'first',
          'folders': ['C:/first'],
        },
        {
          'id': 'second',
          'folders': ['C:/second'],
        },
      ];
      tester.view.physicalSize = const Size(320, 460);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('folder-prompt-preview'),
          child: SuperClipboardApp(store: remote),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('folder-prompt-preview')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build').create(recursive: true);
        await File('build/folder-prompt.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.text('下次不再询问'));
      await tester.tap(find.text('作为文件组'));
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(remote.resolved.map((e) => e['id']), ['first', 'second']);
      expect(remote.resolved.first['remember'], isTrue);
      expect(remote.resolved.last['choice'], 'cancel');
      expect(find.byType(FolderDropDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      remote.dispose();
    },
  );
  testWidgets(
    'folder prompt fits compact windows and remembers either decision',
    (tester) async {
      tester.view.physicalSize = const Size(320, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final choice in ['作为文件组', '保留文件夹']) {
        ({String choice, bool remember})? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showDialog<({String choice, bool remember})>(
                      context: context,
                      builder: (_) =>
                          const FolderDropDialog(folders: ['C:/测试文件夹']),
                    );
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        expect(find.text('将文件夹作为文件组？'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('下次不再询问'));
        await tester.tap(find.text('下次不再询问'));
        await tester.ensureVisible(find.text(choice));
        await tester.tap(find.text(choice));
        await tester.pumpAndSettle();
        expect(result?.remember, isTrue);
        expect(result?.choice, choice == '作为文件组' ? 'group' : 'folder');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets(
    'main list, search, filters, detail and notebook work at original width',
    (tester) async {
      store.settings['titleBarStyle'] = 'mac';
      tester.view.physicalSize = const Size(440, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(SuperClipboardApp(store: store));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryCard), findsNWidgets(2));
      final firstCard = tester.getRect(find.byType(HistoryCard).first);
      expect(firstCard.left, 16);
      expect(firstCard.top, 110);
      expect(firstCard.width, 408);
      expect(tester.getRect(find.byType(MacWindowControls)).width, 78);
      expect(tester.getRect(find.text('剪贴板')).left, 78);

      await tester.tap(find.byTooltip('展开搜索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '有迹可循');
      await tester.pumpAndSettle();
      expect(find.byType(HistoryCard), findsOneWidget);
      await tester.tap(find.byTooltip('收起搜索'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(HistoryCard).first);
      await tester.pumpAndSettle();
      expect(find.byType(EntryDetail), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('entry-detail-panel'))),
        ReplicaMetrics.detailSize,
      );
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('图片'));
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的记录'), findsOneWidget);
      await tester.tap(find.byTooltip('记事本'));
      await tester.pumpAndSettle();
      expect(find.text('记事本还是空的'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('light and dark layouts render at 420px without overflow', (
    tester,
  ) async {
    store.settings['titleBarStyle'] = 'mac';
    tester.view.physicalSize = const Size(420, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: SuperClipboardApp(store: store),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> screenshot(String name) async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('docs/screenshots').create(recursive: true);
      await File('docs/screenshots/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    }

    await tester.runAsync(() => screenshot('main-light'));
    await tester.runAsync(() => store.setting('appearance', 'dark'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => screenshot('main-dark'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('设置与关于'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置…'));
    await tester.pumpAndSettle();
    expect(find.text('开机启动'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('settings-panel'))),
      const Size(400, 560),
    );
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => screenshot('settings-dark'));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('popover presents native-size history tabs and shared count', (
    tester,
  ) async {
    final remote = ClipboardStore(
      mode: 'popover',
      directory: directory,
      usePlatform: false,
    );
    remote.history = store.history;
    tester.view.physicalSize = ReplicaMetrics.popoverSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(SuperClipboardApp(store: remote));
    await tester.pumpAndSettle();
    expect(find.text('历史记录'), findsOneWidget);
    expect(find.text('2 条'), findsOneWidget);
    expect(find.byType(EntryDetail), findsNothing);
    await tester.tap(find.byTooltip('退出 SuperClipboard'));
    await tester.pumpAndSettle();
    expect(find.text('退出 SuperClipboard？'), findsOneWidget);
    final quitSurface = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(MacGlassSurface),
    );
    expect(tester.getSize(quitSurface).width, 310);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    remote.dispose();
  });
  testWidgets('transfer remains usable at its original minimum size', (
    tester,
  ) async {
    final remote = ClipboardStore(
      mode: 'transfer',
      directory: directory,
      usePlatform: false,
    );
    remote.settings['titleBarStyle'] = 'mac';
    tester.view.physicalSize = const Size(320, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(SuperClipboardApp(store: remote));
    await tester.pumpAndSettle();
    expect(find.text('中转站还是空的'), findsOneWidget);
    expect(find.textContaining('关闭后 10 分钟清空'), findsOneWidget);
    expect(tester.getSize(find.byType(MacWindowControls)).height, 44);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    remote.dispose();
  });
  testWidgets(
    'Windows is default; caption buttons stay right and settings switches live',
    (tester) async {
      tester.view.physicalSize = const Size(440, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: SuperClipboardApp(store: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.windowsStyle, isTrue);
      expect(find.byType(MacWindowControls), findsNothing);
      final controls = tester.getRect(find.byType(WindowsWindowControls));
      expect(controls.right, 440);
      expect(controls.size, const Size(138, 32));
      expect(
        tester
            .getRect(find.byKey(const ValueKey('windows-caption-minimize')))
            .left,
        302,
      );
      expect(
        tester
            .getRect(find.byKey(const ValueKey('windows-caption-close')))
            .right,
        440,
      );
      expect(find.byTooltip('最大化窗口'), findsOneWidget);
      store.setWindowMaximized(true);
      await tester.pumpAndSettle();
      expect(find.byTooltip('还原窗口'), findsOneWidget);
      store.setWindowMaximized(false);
      await tester.pumpAndSettle();
      Future<void> screenshot(String name) async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('docs/screenshots/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      await tester.runAsync(() => screenshot('windows-style-light'));
      await tester.runAsync(() => store.setting('appearance', 'dark'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => screenshot('windows-style-dark'));
      await tester.enterText(find.byType(TextField), '有迹可循');
      await tester.pumpAndSettle();
      expect(find.byType(HistoryCard), findsOneWidget);
      await tester.tap(find.byTooltip('设置与关于'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置…'));
      await tester.pumpAndSettle();
      Future<void> chooseStyle(String value) async {
        final selector = tester.widget<PopupMenuButton<dynamic>>(
          find.byWidgetPredicate(
            (w) => w is PopupMenuButton && w.tooltip == '标题栏样式',
          ),
        );
        await tester.runAsync(() async {
          selector.onSelected!(value);
          await store.pendingSetting!;
        });
        await tester.pumpAndSettle();
      }

      await chooseStyle('mac');
      expect(store.windowsStyle, isFalse);
      expect(find.byType(MacWindowControls), findsOneWidget);
      expect(find.byType(WindowsWindowControls), findsNothing);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('设置与关于'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置…'));
      await tester.pumpAndSettle();
      await chooseStyle('windows');
      expect(find.byType(WindowsWindowControls), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Windows transfer title bar fits its 320px minimum without duplicate close',
    (tester) async {
      final remote = ClipboardStore(
        mode: 'transfer',
        directory: directory,
        usePlatform: false,
      );
      tester.view.physicalSize = const Size(320, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(SuperClipboardApp(store: remote));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(WindowsWindowControls)).right, 320);
      expect(find.byTooltip('关闭窗口'), findsOneWidget);
      expect(find.byTooltip('关闭中转站'), findsNothing);
      expect(find.byType(MacWindowControls), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      remote.dispose();
    },
  );
  testWidgets(
    'popover Ctrl+number follows current search and notebook results',
    (tester) async {
      final remote = _QuickCopyStore(directory: directory);
      remote.history = store.history;
      remote.notebook = [
        store.history.first.copyWith(id: 'saved', library: 'notebook'),
      ];
      tester.view.physicalSize = const Size(390, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(SuperClipboardApp(store: remote));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '有迹可循');
      await tester.pumpAndSettle();
      final visible = tester.widget<HistoryCard>(find.byType(HistoryCard));
      Future<void> number(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      await number(LogicalKeyboardKey.digit1);
      expect(remote.copied, visible.entry.id);
      await tester.tap(find.text('记事本').first);
      await tester.pumpAndSettle();
      await number(LogicalKeyboardKey.digit1);
      expect(remote.copied, 'saved');
      remote.copied = null;
      await number(LogicalKeyboardKey.digit9);
      expect(remote.copied, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      remote.dispose();
    },
  );
}
