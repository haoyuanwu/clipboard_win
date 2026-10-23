part of 'app.dart';

class FolderDropDialog extends StatefulWidget {
  const FolderDropDialog({super.key, required this.folders});
  final List<String> folders;
  @override
  State<FolderDropDialog> createState() => _FolderDropDialogState();
}

class _FolderDropDialogState extends State<FolderDropDialog> {
  bool remember = false;
  @override
  Widget build(BuildContext context) => FrostedDialog(
    child: SizedBox(
      width: 310,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                CupertinoIcons.doc_on_doc_fill,
                color: accent(context),
                size: 32,
              ),
              const SizedBox(height: 14),
              const Text(
                '将文件夹作为文件组？',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                widget.folders
                    .map((p) => p.replaceAll('\\', '/').split('/').last)
                    .join('、'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                '作为文件组：展开第一层内容，便于逐项复制和拖出。子文件夹和空文件夹保持完整。',
                style: TextStyle(fontSize: 12, color: secondary(context)),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('下次不再询问', style: TextStyle(fontSize: 13)),
                value: remember,
                onChanged: (v) => setState(() => remember = v ?? false),
              ),
              Text(
                '可在设置 → 悬浮中转中修改。',
                style: TextStyle(fontSize: 11, color: secondary(context)),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 6,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, (
                      choice: 'folder',
                      remember: remember,
                    )),
                    child: const Text('保留文件夹'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, (
                      choice: 'group',
                      remember: remember,
                    )),
                    child: const Text('作为文件组'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

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
          WindowStyleScope.isWindows(context)
              ? Icons.close
              : CupertinoIcons.xmark_circle_fill,
          '关闭',
          close,
          size: 20,
          iconSize: WindowStyleScope.isWindows(context) ? 12 : 20,
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
  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.store.addListener(changed);
  }

  bool copied = false, failed = false;
  Timer? _timer;
  @override
  void dispose() {
    widget.store.removeListener(changed);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final status = widget.store.status(e);
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
                          if (status.isMissing) ...[
                            MissingEntryPlaceholder(entry: e),
                            TextButton(
                              onPressed: () async {
                                final ok = await widget.store.command({
                                  'op': 'delete',
                                  'id': e.id,
                                  'library': e.library,
                                });
                                if (ok && context.mounted) {
                                  Navigator.pop(context);
                                }
                              },
                              child: const Text(
                                '移除这条失效记录',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ] else if (e.kind == EntryKind.video &&
                              e.paths.isNotEmpty)
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
                                    onTap:
                                        status.total > 0 &&
                                            !status.validPaths.contains(path)
                                        ? null
                                        : () => WindowsBridge.call(
                                            'reveal',
                                            path,
                                          ),
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
                              onPressed: status.isMissing
                                  ? null
                                  : () async {
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
  const SettingsPanel({
    super.key,
    required this.store,
    this.shortcutsFirst = false,
  });
  final ClipboardStore store;
  final bool shortcutsFirst;
  Widget _shortcuts(BuildContext context) => _section(context, '快捷键', [
    ShortcutSettings(store: store, mode: 'popover'),
    const Divider(),
    ShortcutSettings(store: store, mode: 'transfer'),
    _hint(context, '弹窗中按 Ctrl + 1–9 复制当前搜索结果。点击组合键可重新录制。'),
  ]);
  @override
  Widget build(BuildContext context) => FrostedDialog(
    insetPadding: const EdgeInsets.all(10),
    child: SizedBox(
      key: const ValueKey('settings-panel'),
      width: 420,
      height: 560,
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
                    if (shortcutsFirst) _shortcuts(context),
                    _section(context, '通用与外观', [
                      _toggle(
                        context,
                        '开机启动',
                        store.settings['startup'] == true,
                        (v) => store.setting('startup', v),
                      ),
                      _hint(context, '登录 Windows 后，自动准备好剪贴板。'),
                      const SizedBox(height: 8),
                      AppearanceChoices(store: store),
                      _select(
                        context,
                        '标题栏样式',
                        store.settings['titleBarStyle'] ?? 'windows',
                        {'windows': 'Windows', 'mac': 'macOS'},
                        (v) => store.setting('titleBarStyle', v),
                      ),
                    ]),
                    if (!shortcutsFirst) _shortcuts(context),
                    _section(context, '历史记录', [
                      _select(context, '最多保留', store.settings['limit'], {
                        100: '100 条',
                        500: '500 条',
                        1000: '1000 条',
                      }, (v) => store.setting('limit', v)),
                      _hint(context, '重复内容合并计数，置顶记录不会自动清理。'),
                      ExpansionTile(
                        title: const Text(
                          '记录维护',
                          style: TextStyle(fontSize: 13),
                        ),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        shape: const Border(),
                        collapsedShape: const Border(),
                        children: [
                          UnavailableRecordsBar(
                            store: store,
                            library: 'history',
                          ),
                          AvailabilityCheckControl(store: store),
                          _link(context, '清空未置顶记录…', () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text(
                                  '清空未置顶记录？',
                                  style: TextStyle(fontSize: 16),
                                ),
                                content: const Text(
                                  '移除历史记录与副本，置顶记录、记事本和中转站会保留。',
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
                        ],
                      ),
                    ]),
                    TransferStorageSettings(store: store),
                    if (store.error.isNotEmpty)
                      Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer
                                .withValues(alpha: .25),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.error
                                  .withValues(alpha: .2),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                CupertinoIcons.exclamationmark_circle,
                                size: 16,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  store.error,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 12,
                                    height: 1.5,
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
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ReplicaMetrics.primary(c),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: (isDark(c) ? const Color(0xff30333a) : Colors.white)
                .withValues(alpha: .70),
            borderRadius: BorderRadius.circular(10),
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
}
