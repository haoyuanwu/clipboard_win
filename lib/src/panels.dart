part of 'app.dart';

class PanelHeader extends StatelessWidget {
  const PanelHeader(this.title, this.close, {super.key});
  final String title;
  final VoidCallback close;
  @override
  Widget build(BuildContext context) => Container(
    height: 49,
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: ReplicaMetrics.border(context), width: 1),
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: ReplicaMetrics.fontFamily,
            fontFamilyFallback: ReplicaMetrics.fontFallback,
            fontSize: 14,
            height: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        ToolButton(
          CupertinoIcons.xmark_circle_fill,
          '关闭',
          close,
          size: 20,
          iconSize: 20,
          color: secondary(context),
        ),
      ],
    ),
  );
}

class EntryDetail extends StatefulWidget {
  const EntryDetail({super.key, required this.store, required this.entry});
  final ClipboardStore store;
  final ClipEntry entry;
  @override
  State<EntryDetail> createState() => _EntryDetailState();
}

class _EntryDetailState extends State<EntryDetail> {
  bool copied = false, failed = false;
  Timer? _timer;
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return FrostedDialog(
      insetPadding: const EdgeInsets.all(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          key: const ValueKey('entry-detail-panel'),
          width: 420,
          height: 420,
          decoration: BoxDecoration(
            color: ReplicaMetrics.page(context),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  Color(e.tint).withValues(alpha: .30),
                  ReplicaMetrics.page(context),
                ).withValues(alpha: .24),
                header(context).withValues(alpha: .12),
                Color.alphaBlend(
                  Color(e.tint).withValues(alpha: .13),
                  ReplicaMetrics.page(context),
                ).withValues(alpha: .18),
              ],
            ),
          ),
          child: Stack(
            children: [
              if (e.sourceIcon.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Opacity(
                        opacity: .10,
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Image.file(
                            File(e.sourceIcon),
                            width: 240,
                            height: 240,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(e.kind.icon, size: 14, color: Color(e.tint)),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            e.kind == EntryKind.text ? '文字' : e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: ReplicaMetrics.fontFamily,
                              fontFamilyFallback: ReplicaMetrics.fontFallback,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ToolButton(
                          CupertinoIcons.xmark,
                          '关闭',
                          () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (e.kind == EntryKind.video && e.paths.isNotEmpty)
                            VideoPreview(path: e.paths.first)
                          else if (e.kind != EntryKind.file)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: e.kind == EntryKind.image
                                    ? 280
                                    : double.infinity,
                              ),
                              child: EntryContent(entry: e, detail: true),
                            ),
                          ...e.paths.map(
                            (path) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(CupertinoIcons.doc, size: 14),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          path
                                              .replaceAll('\\', '/')
                                              .split('/')
                                              .last,
                                          style: const TextStyle(
                                            fontFamily:
                                                ReplicaMetrics.fontFamily,
                                            fontFamilyFallback:
                                                ReplicaMetrics.fontFallback,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  InkWell(
                                    onTap: () =>
                                        WindowsBridge.call('reveal', path),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: control(context),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            CupertinoIcons.folder,
                                            size: 13,
                                            color: secondary(context),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              path,
                                              style: TextStyle(
                                                fontFamily: 'Consolas',
                                                fontFamilyFallback:
                                                    ReplicaMetrics.fontFallback,
                                                fontSize: 12,
                                                color: secondary(context),
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            CupertinoIcons.arrow_up_right,
                                            size: 10,
                                            color: secondary(context),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: ReplicaMetrics.border(context),
                          width: 1,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  SourceIcon(e.sourceIcon),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      e.source,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: ReplicaMetrics.fontFamily,
                                        fontFamilyFallback:
                                            ReplicaMetrics.fontFallback,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              IconTheme(
                                data: IconThemeData(
                                  size: 12,
                                  color: secondary(context),
                                ),
                                child: DefaultTextStyle(
                                  style: TextStyle(
                                    fontFamily: ReplicaMetrics.fontFamily,
                                    fontFamilyFallback:
                                        ReplicaMetrics.fontFallback,
                                    fontSize: 12,
                                    color: secondary(context),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(CupertinoIcons.clock),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          timestamp(e.lastCopiedAt),
                                          maxLines: 1,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Icon(CupertinoIcons.doc_on_doc),
                                      const SizedBox(width: 4),
                                      Text('${e.count}'),
                                    ],
                                  ),
                                ),
                              ),
                              if (failed)
                                Text(
                                  '复制失败，请检查原文件后重试',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: Tooltip(
                            message: copied ? '已复制' : '再次复制',
                            child: TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                backgroundColor: copied
                                    ? ReplicaMetrics.successFill(context)
                                    : ReplicaMetrics.action(context),
                                foregroundColor: copied
                                    ? ReplicaMetrics.successText(context)
                                    : ReplicaMetrics.actionText(context),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () async {
                                if (copied) return;
                                final ok = await widget.store.copy(e);
                                if (!mounted) return;
                                setState(() {
                                  copied = ok;
                                  failed = !ok;
                                });
                                if (ok) {
                                  _timer = Timer(
                                    const Duration(milliseconds: 400),
                                    () {
                                      if (mounted) Navigator.pop(context);
                                    },
                                  );
                                }
                              },
                              child: Icon(
                                copied
                                    ? CupertinoIcons.checkmark
                                    : failed
                                    ? CupertinoIcons.exclamationmark
                                    : CupertinoIcons.doc_on_doc_fill,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VideoPreview extends StatefulWidget {
  const VideoPreview({super.key, required this.path});
  final String path;
  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  late final Player player;
  late final VideoController controller;
  String? error;
  Duration position = Duration.zero, duration = Duration.zero;
  bool playing = false;
  final subscriptions = <StreamSubscription>[];
  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    subscriptions.add(
      player.stream.error.listen((e) {
        if (mounted) setState(() => error = e);
      }),
    );
    subscriptions.add(
      player.stream.position.listen((p) {
        if (mounted) setState(() => position = p);
      }),
    );
    subscriptions.add(
      player.stream.duration.listen((d) {
        if (mounted) setState(() => duration = d);
      }),
    );
    subscriptions.add(
      player.stream.playing.listen((p) {
        if (mounted) setState(() => playing = p);
      }),
    );
    player.open(Media(widget.path), play: false);
  }

  @override
  void dispose() {
    for (final s in subscriptions) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }

  String label(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 260,
    child: error != null
        ? Center(
            child: Text(
              '视频文件不可用',
              style: TextStyle(color: secondary(context), fontSize: 12),
            ),
          )
        : Column(
            children: [
              SizedBox(
                height: 210,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Video(
                    controller: controller,
                    controls: NoVideoControls,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ToolButton(
                    playing
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill,
                    playing ? '暂停' : '播放',
                    () => player.playOrPause(),
                    size: 24,
                    iconSize: 13,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: SliderComponentShape.noOverlay,
                        activeTrackColor: accent(context),
                        thumbColor: isDark(context)
                            ? Colors.white
                            : const Color(0xfff8f8f8),
                      ),
                      child: Slider(
                        padding: EdgeInsets.zero,
                        value: position.inMilliseconds.toDouble().clamp(
                          0,
                          duration.inMilliseconds.toDouble(),
                        ),
                        max: duration.inMilliseconds > 0
                            ? duration.inMilliseconds.toDouble()
                            : 1,
                        onChanged: (v) =>
                            player.seek(Duration(milliseconds: v.round())),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    '${label(position)} / ${label(duration)}',
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 11,
                      color: secondary(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
  );
}

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, required this.store});
  final ClipboardStore store;
  @override
  Widget build(BuildContext context) => FrostedDialog(
    insetPadding: const EdgeInsets.all(10),
    child: SizedBox(
      key: const ValueKey('settings-panel'),
      width: ReplicaMetrics.panelSize.width,
      height: ReplicaMetrics.panelSize.height,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) => Column(
          children: [
            PanelHeader('设置', () => Navigator.pop(context)),
            Expanded(
              child: ColoredBox(
                color:
                    (isDark(context)
                            ? const Color(0xff23262d)
                            : const Color(0xfff3f3f3))
                        .withValues(alpha: .24),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  children: [
                    _section(context, '通用', [
                      _toggle(
                        context,
                        '开机启动',
                        store.settings['startup'] == true,
                        (v) => store.setting('startup', v),
                      ),
                    ]),
                    _section(context, '外观', [
                      _select(context, '显示模式', store.settings['appearance'], {
                        'light': '浅色',
                        'dark': '深色',
                        'system': '跟随系统',
                      }, (v) => store.setting('appearance', v)),
                    ]),
                    _section(context, '历史记录', [
                      _select(context, '最多保留', store.settings['limit'], {
                        100: '100 条',
                        500: '500 条',
                        1000: '1000 条',
                      }, (v) => store.setting('limit', v)),
                      _hint(context, '重复内容合并计数，置顶记录不会自动清理。'),
                      _link(context, '清空未置顶记录', () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          barrierColor: Colors.black.withValues(alpha: .16),
                          builder: (c) => AlertDialog(
                            title: const Text(
                              '清空未置顶记录？',
                              style: TextStyle(fontSize: 14),
                            ),
                            content: const Text(
                              '记事本与原始文件会保留。',
                              style: TextStyle(fontSize: 12),
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
                        if (ok == true) {
                          await store.command({
                            'op': 'clear',
                            'library': 'history',
                          });
                        }
                      }, danger: true),
                    ]),
                    _section(context, '悬浮中转', [
                      _toggle(
                        context,
                        '拖入内容同时保存到历史记录',
                        store.settings['transferHistory'] == true,
                        (v) => store.setting('transferHistory', v),
                      ),
                      _hint(context, '默认关闭。拖入的图片、视频和文件始终保存独立中转副本；开启后也记入历史记录。'),
                      Row(
                        children: [
                          const Text('关闭后清空'),
                          const Spacer(),
                          SizedBox(
                            width: 48,
                            height: 24,
                            child: TextFormField(
                              key: ValueKey(store.settings['transferMinutes']),
                              initialValue:
                                  '${store.settings['transferMinutes']}',
                              textAlign: TextAlign.right,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: const TextStyle(
                                fontFamily: ReplicaMetrics.fontFamily,
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                filled: true,
                                fillColor: control(context),
                                border: OutlineInputBorder(
                                  borderSide: BorderSide.none,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              onFieldSubmitted: (v) => store.setting(
                                'transferMinutes',
                                int.tryParse(v) ?? 10,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '分钟',
                            style: TextStyle(color: secondary(context)),
                          ),
                          const SizedBox(width: 6),
                          _stepper(context),
                        ],
                      ),
                      _hint(
                        context,
                        '默认 10 分钟，支持 1–1440 分钟。重新打开取消倒计时，只清理中转副本。',
                      ),
                    ]),
                    _section(context, '记事本', [
                      InkWell(
                        onTap: () => WindowsBridge.call(
                          'openFolder',
                          store.notebookPath,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                CupertinoIcons.folder,
                                size: 13,
                                color: accent(context),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  store.notebookPath,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: ReplicaMetrics.fontFamily,
                                    fontFamilyFallback:
                                        ReplicaMetrics.fontFallback,
                                    fontSize: 11,
                                    color: accent(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _link(
                        context,
                        store.busy ? '正在保存或迁移…' : '更改保存位置…',
                        store.busy
                            ? null
                            : () async {
                                final path = await WindowsBridge.call<String>(
                                  'chooseFolder',
                                );
                                if (path != null && path.isNotEmpty) {
                                  await store.command({
                                    'op': 'migrate',
                                    'path': path,
                                  });
                                }
                              },
                      ),
                      _hint(context, '加入时保存独立副本，永久保留；更改位置会迁移已有内容。'),
                    ]),
                    if (store.error.isNotEmpty)
                      Text(
                        store.error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _section(BuildContext c, String title, List<Widget> rows) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 5),
          child: Text(
            title,
            style: TextStyle(
              fontFamily: ReplicaMetrics.fontFamily,
              fontFamilyFallback: ReplicaMetrics.fontFallback,
              fontSize: 12,
              color: secondary(c),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isDark(c) ? const Color(0xff30333a) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: ReplicaMetrics.border(c).withValues(alpha: .06),
              width: .5,
            ),
          ),
          child: DefaultTextStyle(
            style: TextStyle(
              fontFamily: ReplicaMetrics.fontFamily,
              fontFamilyFallback: ReplicaMetrics.fontFallback,
              fontSize: 13,
              color: ReplicaMetrics.primary(c),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows,
            ),
          ),
        ),
      ],
    ),
  );
  Widget _hint(BuildContext c, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: ReplicaMetrics.fontFamily,
        fontFamilyFallback: ReplicaMetrics.fontFallback,
        fontSize: 12,
        height: 1.3,
        color: secondary(c),
      ),
    ),
  );
  Widget _toggle(
    BuildContext c,
    String title,
    bool value,
    ValueChanged<bool> change,
  ) => SizedBox(
    height: 28,
    child: Row(
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 13))),
        SizedBox(
          width: 32,
          height: 20,
          child: FittedBox(
            child: CupertinoSwitch(
              value: value,
              activeTrackColor: const Color(0xff1f5ce0),
              onChanged: change,
            ),
          ),
        ),
      ],
    ),
  );
  Widget _link(
    BuildContext c,
    String title,
    VoidCallback? action, {
    bool danger = false,
  }) => SizedBox(
    height: 28,
    child: TextButton(
      onPressed: action,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        foregroundColor: danger
            ? (isDark(c) ? const Color(0xffff9494) : const Color(0xffad1f21))
            : accent(c),
        textStyle: const TextStyle(
          fontFamily: ReplicaMetrics.fontFamily,
          fontFamilyFallback: ReplicaMetrics.fontFallback,
          fontSize: 13,
        ),
      ),
      child: Text(title),
    ),
  );
  Widget _select<T>(
    BuildContext c,
    String title,
    T value,
    Map<T, String> values,
    ValueChanged<T> change,
  ) => SizedBox(
    height: 30,
    child: Row(
      children: [
        Text(title),
        const Spacer(),
        PopupMenuButton<T>(
          initialValue: value,
          tooltip: title,
          onSelected: change,
          itemBuilder: (_) => values.entries
              .map(
                (e) => PopupMenuItem(
                  value: e.key,
                  height: 26,
                  child: Text(e.value),
                ),
              )
              .toList(),
          child: Container(
            width: 108,
            height: 23,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: control(c).withValues(alpha: .06),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: ReplicaMetrics.border(c), width: .75),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    values[value] ?? '',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const Icon(CupertinoIcons.chevron_down, size: 10),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  Widget _stepper(BuildContext c) => Container(
    width: 16,
    height: 24,
    decoration: BoxDecoration(
      color: control(c),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => store.setting(
              'transferMinutes',
              (store.settings['transferMinutes'] as int) + 1,
            ),
            child: const Center(
              child: Icon(CupertinoIcons.chevron_up, size: 9),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: InkWell(
            onTap: () => store.setting(
              'transferMinutes',
              (store.settings['transferMinutes'] as int) - 1,
            ),
            child: const Center(
              child: Icon(CupertinoIcons.chevron_down, size: 9),
            ),
          ),
        ),
      ],
    ),
  );
}
