import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clipboard_win/src/app.dart';
import 'package:clipboard_win/src/store.dart';

class _UiStore extends ClipboardStore {
  _UiStore({required super.directory}) : super(usePlatform: false);
  Future<bool>? pendingSetting;
  @override
  Future<bool> setting(String key, dynamic value) =>
      pendingSetting = super.setting(key, value);
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
      expect(firstCard.top, 104);
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
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('开机启动'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('settings-panel'))),
      ReplicaMetrics.panelSize,
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
    expect(find.text('关闭后 10 分钟清空'), findsOneWidget);
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
      await tester.tap(find.byTooltip('设置'));
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
      await tester.tap(find.byTooltip('设置'));
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
}
