import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'model.dart';
import 'platform.dart';
import 'store.dart';
import 'rtf_preview.dart';
part 'panels.dart';
part 'cards.dart';
part 'mac_controls.dart';

class SuperClipboardApp extends StatelessWidget {
  const SuperClipboardApp({super.key, required this.store});
  final ClipboardStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => MaterialApp(
      title: 'SuperClipboard',
      debugShowCheckedModeBanner: false,
      themeMode: switch (store.settings['appearance']) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      },
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      builder: (context, child) => store.mode == 'main'
          ? child!
          : NativeGlassHost(
              enabled: store.usePlatform,
              child: MacGlassSurface(
                transfer: store.mode == 'transfer',
                child: child!,
              ),
            ),
      home: ClipboardHome(store: store),
    ),
  );
  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      fontFamily: ReplicaMetrics.fontFamily,
      fontFamilyFallback: ReplicaMetrics.fontFallback,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff1f5ce0),
        brightness: brightness,
      ).copyWith(surface: dark ? const Color(0xff1f2229) : Colors.white),
      scaffoldBackgroundColor: dark ? const Color(0xff1f2229) : Colors.white,
      textTheme: Typography.material2021().black.apply(
        bodyColor: dark ? const Color(0xfff0f2f7) : const Color(0xff1a1f26),
        displayColor: dark ? const Color(0xfff0f2f7) : const Color(0xff1a1f26),
        fontFamily: ReplicaMetrics.fontFamily,
        fontFamilyFallback: ReplicaMetrics.fontFallback,
      ),
      splashFactory: NoSplash.splashFactory,
      popupMenuTheme: PopupMenuThemeData(
        color: dark ? const Color(0xff303239) : const Color(0xfff6f6f6),
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        menuPadding: const EdgeInsets.all(4),
        textStyle: TextStyle(
          fontFamily: ReplicaMetrics.fontFamily,
          fontFamilyFallback: ReplicaMetrics.fontFallback,
          fontSize: 13,
          height: 1.2,
          color: dark ? const Color(0xfff0f2f7) : const Color(0xff1a1f26),
        ),
      ),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(seconds: 2)),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(30, 30),
          maximumSize: const Size(32, 32),
          padding: EdgeInsets.zero,
          iconSize: 16,
          foregroundColor: dark
              ? const Color(0xffc7d1e6)
              : const Color(0xff1f5ce0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? const Color(0xff1f2229) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(
        color: dark ? Colors.white12 : Colors.black12,
        space: 1,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }
}

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color secondary(BuildContext c) =>
    isDark(c) ? const Color(0xffb8bfcc) : const Color(0xff575e6b);
Color control(BuildContext c) => isDark(c)
    ? Colors.white.withValues(alpha: .065)
    : Colors.black.withValues(alpha: .065);
Color header(BuildContext c) =>
    isDark(c) ? const Color(0xff292d33) : const Color(0xfff7fafd);
Color accent(BuildContext c) =>
    isDark(c) ? const Color(0xffc7d1e6) : const Color(0xff1f5ce0);

class ClipboardHome extends StatefulWidget {
  const ClipboardHome({super.key, required this.store});
  final ClipboardStore store;
  @override
  State<ClipboardHome> createState() => _ClipboardHomeState();
}

class _ClipboardHomeState extends State<ClipboardHome> {
  ClipboardStore get store => widget.store;
  final search = TextEditingController();
  final searchFocus = FocusNode();
  final historySession = ListSession(), notebookSession = ListSession();
  String library = 'history', lastSort = '';
  EntryKind? category;
  bool expanded = false;
  String? copiedId;
  int revision = -1;
  Timer? feedbackTimer, clockTimer;
  bool get popover => store.mode == 'popover';
  bool get transfer => store.mode == 'transfer';
  @override
  void initState() {
    super.initState();
    if (transfer) library = 'transfer';
    store.addListener(_changed);
    _begin();
    clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _begin() {
    historySession.begin(store.history, store.settings['sort']);
    notebookSession.begin(store.notebook, store.settings['sort']);
    revision = store.sessionRevision;
    lastSort = store.settings['sort'];
  }

  void _changed() {
    if (revision != store.sessionRevision) {
      if (popover) {
        library = 'history';
        search.clear();
        copiedId = null;
      }
      _begin();
    }
    if (lastSort != store.settings['sort']) _begin();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    search.dispose();
    searchFocus.dispose();
    feedbackTimer?.cancel();
    clockTimer?.cancel();
    super.dispose();
  }

  List<ClipEntry> get entries {
    final list = transfer
        ? store.transfer
        : (library == 'history'
              ? historySession.entries(store.history)
              : notebookSession.entries(store.notebook));
    return list
        .where(
          (e) =>
              (category == null || category == e.kind) &&
              e.searchText.toLowerCase().contains(search.text.toLowerCase()),
        )
        .toList();
  }

  void _switchLibrary(String name) => setState(() {
    library = name;
    category = null;
    search.clear();
    copiedId = null;
  });
  Future<void> _copy(ClipEntry e) async {
    if (await store.copy(e) && mounted) {
      setState(() => copiedId = e.id);
      feedbackTimer?.cancel();
      feedbackTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => copiedId = null);
      });
    }
  }

  void _open(String mode) {
    if (store.usePlatform) WindowsBridge.call('show', mode);
  }

  @override
  Widget build(BuildContext context) {
    final items = entries;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          setState(() => expanded = true);
          searchFocus.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (expanded || search.text.isNotEmpty) {
            setState(() {
              expanded = false;
              search.clear();
            });
          } else if (store.usePlatform) {
            WindowsBridge.call('hide');
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: popover || transfer ? Colors.transparent : null,
          body: Stack(
            children: [
              Column(
                children: [
                  if (transfer)
                    _transferHeader(context)
                  else if (popover)
                    _popoverHeader(context, items.length)
                  else
                    _mainHeader(context),
                  if (store.busy) const LinearProgressIndicator(minHeight: 2),
                  if (store.error.isNotEmpty)
                    Material(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                store.error,
                                style: const TextStyle(
                                  fontFamily: ReplicaMetrics.fontFamily,
                                  fontFamilyFallback:
                                      ReplicaMetrics.fontFallback,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            ToolButton(
                              CupertinoIcons.xmark,
                              '关闭提示',
                              () => store.command({'op': 'dismissError'}),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: items.isEmpty
                        ? !popover && !transfer
                              ? Align(
                                  alignment: Alignment.topCenter,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: SizedBox(
                                      height: 300,
                                      child: _empty(context),
                                    ),
                                  ),
                                )
                              : _empty(context)
                        : Scrollbar(
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: items.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final e = items[i];
                                final card = HistoryCard(
                                  entry: e,
                                  copied: copiedId == e.id,
                                  translucent: transfer,
                                  onTap: () => popover || transfer
                                      ? _copy(e)
                                      : _detail(e),
                                  onContext: (p) => _context(e, p),
                                );
                                if (!transfer) return card;
                                return GestureDetector(
                                  onPanStart: store.usePlatform
                                      ? (_) => WindowsBridge.call(
                                          'startDrag',
                                          e.toJson(),
                                        )
                                      : null,
                                  child: card,
                                );
                              },
                            ),
                          ),
                  ),
                  if (transfer)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: control(context),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.clock,
                              size: 11,
                              color: secondary(context),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '关闭后 ${store.settings['transferMinutes']} 分钟清空',
                              style: TextStyle(
                                fontFamily: ReplicaMetrics.fontFamily,
                                fontFamilyFallback: ReplicaMetrics.fontFallback,
                                fontSize: 11,
                                color: secondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              if (transfer && store.dropTargeted)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      margin: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: accent(context).withValues(alpha: .12),
                        border: Border.all(color: accent(context), width: 2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          '松开加入中转站',
                          style: TextStyle(
                            fontFamily: ReplicaMetrics.fontFamily,
                            fontFamilyFallback: ReplicaMetrics.fontFallback,
                            color: accent(context),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drag(Widget child) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onPanStart: store.usePlatform
        ? (_) => WindowsBridge.call('dragWindow')
        : null,
    child: child,
  );
  Widget _mainHeader(BuildContext context) => ColoredBox(
    color: header(context),
    child: Column(
      children: [
        Stack(
          children: [
            _drag(
              SizedBox(
                height: ReplicaMetrics.titleHeight,
                child: Padding(
                  padding: const EdgeInsets.only(left: 78, right: 12),
                  child: Row(
                    children: [
                      if (expanded)
                        Expanded(child: _searchField(context, collapse: true))
                      else ...[
                        Text(
                          library == 'notebook' ? '记事本' : '剪贴板',
                          maxLines: 1,
                          style: const TextStyle(
                            fontFamily: ReplicaMetrics.fontFamily,
                            fontFamilyFallback: ReplicaMetrics.fontFallback,
                            fontSize: 14,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        ToolButton(CupertinoIcons.search, '展开搜索', () {
                          setState(() => expanded = true);
                          searchFocus.requestFocus();
                        }, size: 30),
                      ],
                      const SizedBox(width: 8),
                      ToolButton(
                        library == 'notebook'
                            ? CupertinoIcons.book_fill
                            : CupertinoIcons.book,
                        library == 'notebook' ? '返回剪贴板历史' : '记事本',
                        () => _switchLibrary(
                          library == 'notebook' ? 'history' : 'notebook',
                        ),
                        selected: library == 'notebook',
                        size: 30,
                      ),
                      const SizedBox(width: 8),
                      ToolButton(
                        CupertinoIcons.tray_full,
                        '悬浮中转',
                        () => _open('transfer'),
                        size: 30,
                      ),
                      const SizedBox(width: 8),
                      ToolButton(
                        CupertinoIcons.gear,
                        '设置',
                        _settings,
                        size: 30,
                      ),
                      const SizedBox(width: 8),
                      ToolButton(
                        CupertinoIcons.info_circle,
                        '关于',
                        _about,
                        size: 30,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: MacWindowControls(enabled: store.usePlatform),
            ),
          ],
        ),
        Container(
          height: ReplicaMetrics.filterHeight,
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              ReplicaMetrics.page(context).withValues(alpha: .74),
              header(context),
            ),
            border: Border(
              bottom: BorderSide(
                color: ReplicaMetrics.border(context).withValues(alpha: .084),
                width: 1,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: control(context),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _category(context, null),
                    ...EntryKind.values.map((k) => _category(context, k)),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 30,
                height: 30,
                child: PopupMenuButton<String>(
                  tooltip:
                      '排序：${store.settings['sort'] == 'time' ? '时间排序' : '次数排序'}',
                  padding: EdgeInsets.zero,
                  iconSize: 13,
                  icon: Icon(
                    CupertinoIcons.arrow_up_arrow_down,
                    size: 13,
                    color: accent(context),
                  ),
                  onSelected: (v) => store.setting('sort', v),
                  itemBuilder: (_) => ['time', 'count']
                      .map(
                        (v) => PopupMenuItem(
                          value: v,
                          height: 26,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                child: store.settings['sort'] == v
                                    ? const Icon(
                                        CupertinoIcons.checkmark,
                                        size: 12,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 4),
                              Text(v == 'time' ? '时间排序' : '次数排序'),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _category(BuildContext context, EntryKind? kind) => MacCategoryButton(
    kind: kind,
    selected: category == kind,
    onTap: () => setState(() => category = kind),
  );

  Widget _searchField(BuildContext context, {bool collapse = false}) =>
      Container(
        height: collapse ? 30 : 36,
        decoration: BoxDecoration(
          color: popover
              ? (isDark(context) ? const Color(0xff141a24) : Colors.white)
                    .withValues(alpha: .88)
              : control(context),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            const SizedBox(width: 9),
            Icon(CupertinoIcons.search, size: 14, color: secondary(context)),
            Expanded(
              child: TextField(
                controller: search,
                focusNode: searchFocus,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontFamily: ReplicaMetrics.fontFamily,
                  fontFamilyFallback: ReplicaMetrics.fontFallback,
                  fontSize: 13,
                ),
                decoration: const InputDecoration(hintText: '搜索记录'),
              ),
            ),
            if (collapse || search.text.isNotEmpty)
              ToolButton(
                CupertinoIcons.xmark_circle_fill,
                collapse ? '收起搜索' : '清空搜索',
                () => setState(() {
                  search.clear();
                  if (collapse) expanded = false;
                }),
              ),
          ],
        ),
      );
  Widget _popoverHeader(BuildContext context, int count) => MacGlassSurface(
    strip: true,
    radius: 0,
    child: Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: ReplicaMetrics.border(context).withValues(alpha: .072),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 9),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _searchField(context)),
              const SizedBox(width: 8),
              ToolButton(
                CupertinoIcons.tray_full,
                '悬浮中转',
                () => _open('transfer'),
              ),
              const SizedBox(width: 8),
              ToolButton(
                CupertinoIcons.arrow_up_right_square,
                '打开主窗口',
                () => _open('main'),
              ),
              const SizedBox(width: 8),
              ToolButton(CupertinoIcons.power, '退出 SuperClipboard', _quit),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: control(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  spacing: 2,
                  children: ['history', 'notebook']
                      .map(
                        (v) => SizedBox(
                          height: 27,
                          child: TextButton(
                            onPressed: () => _switchLibrary(v),
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: library == v
                                  ? ReplicaMetrics.primary(context)
                                  : secondary(context),
                              backgroundColor: library == v
                                  ? (isDark(context)
                                            ? const Color(0xff141a24)
                                            : Colors.white)
                                        .withValues(alpha: .88)
                                  : Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              textStyle: TextStyle(
                                fontFamily: ReplicaMetrics.fontFamily,
                                fontFamilyFallback: ReplicaMetrics.fontFallback,
                                fontSize: 11,
                                height: 1,
                                fontWeight: library == v
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  v == 'history'
                                      ? CupertinoIcons.clock
                                      : CupertinoIcons.book,
                                  size: 11,
                                ),
                                const SizedBox(width: 5),
                                Text(v == 'history' ? '历史记录' : '记事本'),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const Spacer(),
              Text(
                '$count 条',
                style: TextStyle(
                  fontFamily: ReplicaMetrics.fontFamily,
                  fontFamilyFallback: ReplicaMetrics.fontFallback,
                  fontSize: 11,
                  color: secondary(context),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  Widget _transferHeader(BuildContext context) => MacGlassSurface(
    strip: true,
    radius: 0,
    transfer: true,
    child: Stack(
      children: [
        _drag(
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.only(left: 78, right: 12),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.tray_full_fill,
                    size: 14,
                    color: accent(context),
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    '中转站',
                    style: TextStyle(
                      fontFamily: ReplicaMetrics.fontFamily,
                      fontFamilyFallback: ReplicaMetrics.fontFallback,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '${store.transfer.length}',
                    style: TextStyle(
                      fontFamily: ReplicaMetrics.fontFamily,
                      fontFamilyFallback: ReplicaMetrics.fontFallback,
                      fontSize: 11,
                      color: secondary(context),
                    ),
                  ),
                  const Spacer(),
                  ToolButton(
                    CupertinoIcons.trash,
                    '清空中转站',
                    store.busy || store.transfer.isEmpty
                        ? null
                        : () => _clear('transfer'),
                    size: 28,
                  ),
                  const SizedBox(width: 7),
                  ToolButton(
                    CupertinoIcons.xmark,
                    '关闭中转站',
                    store.usePlatform
                        ? () => WindowsBridge.call('hide')
                        : () {},
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          child: MacWindowControls(enabled: store.usePlatform, transfer: true),
        ),
      ],
    ),
  );
  Widget _empty(BuildContext context) {
    final searching = search.text.isNotEmpty || category != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              transfer
                  ? CupertinoIcons.tray_arrow_down
                  : library == 'notebook'
                  ? CupertinoIcons.book
                  : CupertinoIcons.doc_on_clipboard,
              size: 48,
              color: secondary(context).withValues(alpha: .65),
            ),
            const SizedBox(height: 18),
            Text(
              searching
                  ? '没有匹配的记录'
                  : transfer
                  ? '中转站还是空的'
                  : library == 'notebook'
                  ? '记事本还是空的'
                  : '暂无剪贴板记录',
              style: const TextStyle(
                fontFamily: ReplicaMetrics.fontFamily,
                fontFamilyFallback: ReplicaMetrics.fontFallback,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              searching
                  ? '试试其他搜索词。'
                  : transfer
                  ? '拖入图片、视频、文件或文字，或在记录上右键加入。'
                  : library == 'notebook'
                  ? '在历史记录上右键，选择「加入记事本」。'
                  : '复制文字、图片或文件后会自动出现在这里。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: ReplicaMetrics.fontFamily,
                fontFamilyFallback: ReplicaMetrics.fontFallback,
                fontSize: 12,
                height: 1.7,
                color: secondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _context(ClipEntry e, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'copy', child: Text('再次复制')),
        if (e.library != 'transfer')
          PopupMenuItem(
            value: 'transfer',
            enabled: !store.busy,
            child: Text(
              store.transfer.any((x) => x.fingerprint == e.fingerprint)
                  ? '在悬浮中转中显示'
                  : '加入悬浮中转',
            ),
          ),
        if (e.library != 'notebook')
          PopupMenuItem(
            value: 'notebook',
            enabled:
                !store.busy &&
                !store.notebook.any((x) => x.fingerprint == e.fingerprint),
            child: Text(
              store.notebook.any((x) => x.fingerprint == e.fingerprint)
                  ? '已加入记事本'
                  : '加入记事本',
            ),
          ),
        if (e.library != 'transfer')
          PopupMenuItem(value: 'pin', child: Text(e.pinned ? '取消置顶' : '置顶')),
        if (e.paths.isNotEmpty)
          const PopupMenuItem(value: 'reveal', child: Text('在资源管理器中显示')),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Text(
            e.library == 'transfer'
                ? '移出中转站'
                : e.library == 'notebook'
                ? '从记事本移除'
                : '删除记录',
            style: TextStyle(
              fontFamily: ReplicaMetrics.fontFamily,
              fontFamilyFallback: ReplicaMetrics.fontFallback,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ],
    );
    if (action == null || !mounted) return;
    if (action == 'copy') {
      await _copy(e);
    } else if (action == 'reveal') {
      await WindowsBridge.call('reveal', e.paths.first);
    } else if (action == 'transfer' || action == 'notebook') {
      await store.command({
        'op': 'archive',
        'id': e.id,
        'library': e.library,
        'target': action,
      });
      if (action == 'transfer') _open('transfer');
    } else {
      await store.command({'op': action, 'id': e.id, 'library': e.library});
      if (action == 'pin' && mounted) setState(_begin);
    }
  }

  void _detail(ClipEntry e) => showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .16),
    builder: (_) => EntryDetail(store: store, entry: e),
  );
  void _settings() => showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .16),
    builder: (_) => SettingsPanel(store: store),
  );
  void _about() => showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .16),
    builder: (c) => FrostedDialog(
      child: SizedBox(
        width: 390,
        height: 440,
        child: Column(
          children: [
            PanelHeader('关于', () => Navigator.pop(c)),
            const Spacer(),
            Image.asset('assets/app_logo.png', width: 80, height: 80),
            const SizedBox(height: 12),
            const Text(
              'SuperClipboard',
              style: TextStyle(
                fontFamily: ReplicaMetrics.fontFamily,
                fontFamilyFallback: ReplicaMetrics.fontFallback,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Windows 剪贴板历史管理 · 版本 1.2.0',
              style: TextStyle(
                fontFamily: ReplicaMetrics.fontFamily,
                fontFamilyFallback: ReplicaMetrics.fontFallback,
                color: secondary(c),
                fontSize: 12,
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    ),
  );
  Future<void> _quit() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .16),
      builder: (c) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 310,
          child: MacGlassSurface(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: control(c),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      CupertinoIcons.power,
                      size: 24,
                      color: accent(c),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '退出 SuperClipboard？',
                    style: TextStyle(
                      fontFamily: ReplicaMetrics.fontFamily,
                      fontFamilyFallback: ReplicaMetrics.fontFallback,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '退出后将停止记录剪贴板内容。',
                    style: TextStyle(
                      fontFamily: ReplicaMetrics.fontFamily,
                      fontFamilyFallback: ReplicaMetrics.fontFallback,
                      fontSize: 12,
                      color: secondary(c),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _confirmationButton(
                          c,
                          '取消',
                          () => Navigator.pop(c, false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _confirmationButton(
                          c,
                          '退出',
                          () => Navigator.pop(c, true),
                          danger: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (ok == true) await WindowsBridge.call('quit');
  }

  Widget _confirmationButton(
    BuildContext c,
    String label,
    VoidCallback action, {
    bool danger = false,
  }) => SizedBox(
    height: 34,
    child: TextButton(
      onPressed: action,
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        backgroundColor: control(c),
        foregroundColor: danger
            ? (isDark(c) ? const Color(0xffff9494) : const Color(0xffad1f21))
            : ReplicaMetrics.primary(c),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontFamily: ReplicaMetrics.fontFamily,
          fontFamilyFallback: ReplicaMetrics.fontFallback,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: Text(label),
    ),
  );

  Future<void> _clear(String lib) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          lib == 'transfer' ? '清空中转站？' : '清空未置顶记录？',
          style: const TextStyle(
            fontFamily: ReplicaMetrics.fontFamily,
            fontFamilyFallback: ReplicaMetrics.fontFallback,
            fontSize: 16,
          ),
        ),
        content: const Text(
          '只清理应用保存的记录和副本，原始文件会保留。',
          style: TextStyle(
            fontFamily: ReplicaMetrics.fontFamily,
            fontFamilyFallback: ReplicaMetrics.fontFallback,
            fontSize: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) await store.command({'op': 'clear', 'library': lib});
  }
}
