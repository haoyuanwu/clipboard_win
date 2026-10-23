part of 'app.dart';

class EntryDragSource extends StatelessWidget {
  const EntryDragSource({
    super.key,
    required this.store,
    required this.entry,
    required this.child,
    this.path,
  });
  final ClipboardStore store;
  final ClipEntry entry;
  final Widget child;
  final String? path;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onPanStart: store.usePlatform
        ? (_) async {
            final data = await store.dragPayload(entry, path: path);
            if (data != null) {
              await WindowsBridge.call('startDrag', data);
            } else {
              await store.refreshAvailability();
            }
          }
        : null,
    child: child,
  );
}

class MissingEntryPlaceholder extends StatelessWidget {
  const MissingEntryPlaceholder({super.key, required this.entry});
  final ClipEntry entry;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        CupertinoIcons.exclamationmark_triangle,
        size: 24,
        color: secondary(context),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.kind == EntryKind.image ? '图片暂时不可用' : '原文件暂时不可用',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(
              '内容已移动、删除或无法访问',
              style: TextStyle(fontSize: 11, color: secondary(context)),
            ),
          ],
        ),
      ),
    ],
  );
}

class UnavailableRecordsBar extends StatelessWidget {
  const UnavailableRecordsBar({
    super.key,
    required this.store,
    required this.library,
  });
  final ClipboardStore store;
  final String library;
  @override
  Widget build(BuildContext context) {
    final ids = store
        .library(library)
        .where((e) => !e.pinned && store.status(e).isMissing)
        .map((e) => e.id)
        .toList();
    if (ids.isEmpty || library == 'notebook') return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      color: control(context),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle,
            size: 13,
            color: secondary(context),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '${ids.length} 条失效记录',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          TextButton(
            onPressed: store.busy
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text(
                          '清理失效记录？',
                          style: TextStyle(fontSize: 16),
                        ),
                        content: const Text(
                          '仅移除全部内容均不可用的记录。置顶、部分可用的文件组和记事本会保留。',
                          style: TextStyle(fontSize: 12),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('清理'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await store.command({
                        'op': 'cleanInvalid',
                        'library': library,
                        'ids': ids,
                      });
                    }
                  },
            child: const Text('清理…', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class TransferFileGroupCard extends StatefulWidget {
  const TransferFileGroupCard({
    super.key,
    required this.store,
    required this.entry,
    required this.onCopy,
    required this.onContext,
    this.copied = false,
  });
  final ClipboardStore store;
  final ClipEntry entry;
  final VoidCallback onCopy;
  final ValueChanged<Offset> onContext;
  final bool copied;
  @override
  State<TransferFileGroupCard> createState() => _TransferFileGroupCardState();
}

class _TransferFileGroupCardState extends State<TransferFileGroupCard> {
  bool expanded = false;
  String? copiedPath;
  Timer? feedback;
  @override
  void dispose() {
    feedback?.cancel();
    super.dispose();
  }

  Future<void> copyFile(String path) async {
    final ok = await widget.store.command({
      'op': 'copy',
      'library': widget.entry.library,
      'id': widget.entry.id,
      'path': path,
    });
    if (!mounted || !ok) return;
    setState(() => copiedPath = path);
    feedback?.cancel();
    feedback = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => copiedPath = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry, status = widget.store.status(widget.entry);
    return GestureDetector(
      onSecondaryTapDown: (d) => widget.onContext(d.globalPosition),
      child: Container(
        decoration: BoxDecoration(
          color: ReplicaMetrics.page(context).withValues(alpha: .70),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ReplicaMetrics.border(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .07),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: EntryDragSource(
                      store: widget.store,
                      entry: e,
                      child: InkWell(
                        onTap: status.isMissing ? null : widget.onCopy,
                        child: Row(
                          children: [
                            _FileCover(paths: e.paths, size: 48, group: true),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        '文件组',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: control(context),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          '${e.paths.length} 项',
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    e.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: secondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ToolButton(
                    expanded
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    expanded ? '收起文件组' : '展开文件组',
                    () => setState(() => expanded = !expanded),
                    size: 28,
                  ),
                ],
              ),
            ),
            if (expanded) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Divider(color: ReplicaMetrics.border(context)),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  spacing: 4,
                  children: [
                    for (final path in e.paths)
                      Builder(
                        builder: (context) {
                          final valid =
                              status.total == 0 ||
                              status.validPaths.contains(path);
                          final name = path
                              .replaceAll('\\', '/')
                              .split('/')
                              .last;
                          return Container(
                            decoration: BoxDecoration(
                              color: control(context).withValues(alpha: .045),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: EntryDragSource(
                                    store: widget.store,
                                    entry: e,
                                    path: path,
                                    child: InkWell(
                                      onTap: valid
                                          ? () => copyFile(path)
                                          : null,
                                      onSecondaryTap: valid
                                          ? () => WindowsBridge.call(
                                              'reveal',
                                              path,
                                            )
                                          : null,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 7,
                                        ),
                                        child: Row(
                                          children: [
                                            _FileCover(paths: [path], size: 32),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    valid
                                                        ? (name.contains('.')
                                                              ? name
                                                                    .split('.')
                                                                    .last
                                                                    .toUpperCase()
                                                              : '文件夹')
                                                        : '文件暂时不可用',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: secondary(context),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                ToolButton(
                                  copiedPath == path
                                      ? CupertinoIcons.checkmark
                                      : CupertinoIcons.doc_on_doc,
                                  copiedPath == path ? '已复制' : '复制 $name',
                                  valid ? () => copyFile(path) : null,
                                  size: 28,
                                ),
                                ToolButton(
                                  CupertinoIcons.folder,
                                  '在资源管理器中显示 $name',
                                  valid
                                      ? () => WindowsBridge.call('reveal', path)
                                      : null,
                                  size: 28,
                                ),
                                const SizedBox(width: 6),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
            Container(
              color: control(context),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    status.isMissing || status.isPartial
                        ? CupertinoIcons.exclamationmark_triangle
                        : widget.copied
                        ? CupertinoIcons.checkmark
                        : CupertinoIcons.square_stack_3d_up,
                    size: 11,
                    color: secondary(context),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      status.isMissing
                          ? '组内文件暂时不可用'
                          : status.isPartial
                          ? '${status.missing} 个文件不可用'
                          : widget.copied
                          ? '已复制整组'
                          : '展开可单独复制或拖出',
                      style: TextStyle(fontSize: 10, color: secondary(context)),
                    ),
                  ),
                  Text(
                    timestamp(e.lastCopiedAt),
                    style: TextStyle(fontSize: 10, color: secondary(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileCover extends StatelessWidget {
  const _FileCover({
    required this.paths,
    required this.size,
    this.group = false,
  });
  final List<String> paths;
  final double size;
  final bool group;
  @override
  Widget build(BuildContext context) {
    final images = paths.where(
      (p) => RegExp(
        r'\.(png|jpe?g|gif|bmp|webp)$',
        caseSensitive: false,
      ).hasMatch(p),
    );
    final icon = Icon(
      group ? CupertinoIcons.folder_fill : CupertinoIcons.doc,
      size: size * .55,
      color: accent(context),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: control(context),
            borderRadius: BorderRadius.circular(9),
          ),
          child: images.isEmpty
              ? icon
              : Image.file(
                  File(images.first),
                  fit: BoxFit.cover,
                  cacheWidth: (size * 2).ceil(),
                  errorBuilder: (_, _, _) => icon,
                ),
        ),
        if (group)
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: ReplicaMetrics.page(context),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Icon(CupertinoIcons.square_stack_fill, size: 10),
            ),
          ),
      ],
    );
  }
}

class AppearanceChoices extends StatelessWidget {
  const AppearanceChoices({super.key, required this.store});
  final ClipboardStore store;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '显示模式',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        Row(
          spacing: 8,
          children: [
            for (final mode in ['light', 'dark', 'system'])
              Expanded(
                child: Semantics(
                  selected: store.settings['appearance'] == mode,
                  button: true,
                  child: InkWell(
                    onTap: () => store.setting('appearance', mode),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 72,
                      decoration: BoxDecoration(
                        color: store.settings['appearance'] == mode
                            ? accent(context).withValues(alpha: .10)
                            : control(context),
                        border: Border.all(
                          color: store.settings['appearance'] == mode
                              ? accent(context)
                              : ReplicaMetrics.border(context),
                          width: store.settings['appearance'] == mode ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            mode == 'light'
                                ? CupertinoIcons.sun_max
                                : mode == 'dark'
                                ? CupertinoIcons.moon
                                : CupertinoIcons.circle_lefthalf_fill,
                            size: 20,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            mode == 'light'
                                ? '浅色'
                                : mode == 'dark'
                                ? '深色'
                                : '跟随系统',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class ShortcutSettings extends StatefulWidget {
  const ShortcutSettings({super.key, required this.store, required this.mode});
  final ClipboardStore store;
  final String mode;
  @override
  State<ShortcutSettings> createState() => _ShortcutSettingsState();
}

class _ShortcutSettingsState extends State<ShortcutSettings> {
  bool recording = false;
  final focus = FocusNode();
  String message = '';
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  String get key => '${widget.mode}Shortcut';
  Map<String, dynamic> get value =>
      Map<String, dynamic>.from(widget.store.settings[key] as Map);
  Future<void> save(Map<String, dynamic> next) async {
    final ok = await widget.store.setting(key, next);
    if (mounted) {
      setState(() {
        recording = false;
        message = ok ? '' : '快捷键已被占用，请选择其他组合。';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.mode == 'popover' ? '打开快捷历史' : '打开悬浮中转',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Focus(
              focusNode: focus,
              onKeyEvent: (_, event) {
                if (!recording || event is! KeyDownEvent) {
                  return recording
                      ? KeyEventResult.handled
                      : KeyEventResult.ignored;
                }
                final logical = event.logicalKey;
                if (logical == LogicalKeyboardKey.escape) {
                  setState(() => recording = false);
                  return KeyEventResult.handled;
                }
                final keyboard = HardwareKeyboard.instance;
                final mods =
                    (keyboard.isAltPressed ? 1 : 0) |
                    (keyboard.isControlPressed ? 2 : 0) |
                    (keyboard.isShiftPressed ? 4 : 0) |
                    (keyboard.isMetaPressed ? 8 : 0);
                final id = logical.keyId;
                final virtual = id >= 97 && id <= 122
                    ? id - 32
                    : id >= 48 && id <= 57
                    ? id
                    : id >= LogicalKeyboardKey.f1.keyId &&
                          id <= LogicalKeyboardKey.f12.keyId
                    ? 112 + id - LogicalKeyboardKey.f1.keyId
                    : 0;
                if (virtual == 0) return KeyEventResult.handled;
                if (mods & 11 == 0) {
                  setState(() => message = '请同时按住 Ctrl、Alt 或 Win。');
                  return KeyEventResult.handled;
                }
                final label = [
                  if (mods & 2 != 0) 'Ctrl',
                  if (mods & 1 != 0) 'Alt',
                  if (mods & 4 != 0) 'Shift',
                  if (mods & 8 != 0) 'Win',
                  logical.keyLabel.toUpperCase(),
                ].join(' + ');
                unawaited(
                  save({
                    'enabled': true,
                    'key': virtual,
                    'modifiers': mods,
                    'label': label,
                  }),
                );
                return KeyEventResult.handled;
              },
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    recording = true;
                    message = '';
                  });
                  focus.requestFocus();
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(140, 29),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  recording
                      ? '按下组合键，Esc 取消'
                      : value['enabled'] == true
                      ? value['label']
                      : '已停用',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () =>
                  save({...value, 'enabled': !(value['enabled'] == true)}),
              child: Text(
                value['enabled'] == true ? '停用' : '启用',
                style: const TextStyle(fontSize: 11),
              ),
            ),
            TextButton(
              onPressed: () => save({
                'enabled': true,
                'modifiers': 3,
                'key': widget.mode == 'popover' ? 67 : 86,
                'label': widget.mode == 'popover'
                    ? 'Ctrl + Alt + C'
                    : 'Ctrl + Alt + V',
              }),
              child: const Text('恢复默认', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        if (message.isNotEmpty)
          Text(
            message,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    ),
  );
}

class AvailabilityCheckControl extends StatefulWidget {
  const AvailabilityCheckControl({super.key, required this.store});
  final ClipboardStore store;
  @override
  State<AvailabilityCheckControl> createState() =>
      _AvailabilityCheckControlState();
}

class _AvailabilityCheckControlState extends State<AvailabilityCheckControl> {
  bool checking = false, completed = false;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          checking
              ? '正在检查原始内容…'
              : completed
              ? '检查完成，列表状态已更新。'
              : '检查被移动、删除或无法访问的内容。',
          style: TextStyle(fontSize: 12, color: secondary(context)),
        ),
      ),
      if (checking)
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      TextButton(
        onPressed: checking
            ? null
            : () async {
                setState(() => checking = true);
                await widget.store.refreshAvailability();
                if (mounted) {
                  setState(() {
                    checking = false;
                    completed = true;
                  });
                }
              },
        child: const Text('检查', style: TextStyle(fontSize: 12)),
      ),
    ],
  );
}
