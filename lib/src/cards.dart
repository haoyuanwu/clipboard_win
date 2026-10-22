part of 'app.dart';

class HistoryCard extends StatefulWidget {
  const HistoryCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onContext,
    this.copied = false,
    this.translucent = false,
  });
  final ClipEntry entry;
  final VoidCallback onTap;
  final ValueChanged<Offset> onContext;
  final bool copied, translucent;
  @override
  State<HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<HistoryCard> {
  bool hovered = false, pressed = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final e = widget.entry, dark = isDark(context);
    final tint = Color(e.tint);
    final top = Color.lerp(
      dark ? const Color(0xff383d47) : const Color(0xfffafafa),
      tint,
      dark ? .14 : .42,
    )!;
    final bottom = Color.lerp(
      dark ? const Color(0xff303642) : const Color(0xfff0f0f0),
      tint,
      dark ? .10 : .24,
    )!;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() {
        hovered = false;
        pressed = false;
      }),
      child: GestureDetector(
        onSecondaryTapDown: (d) => widget.onContext(d.globalPosition),
        child: AnimatedScale(
          scale: reduce
              ? 1
              : pressed
              ? .972
              : hovered
              ? 1.006
              : 1,
          duration: Duration(
            milliseconds: reduce
                ? 0
                : pressed
                ? 90
                : 160,
          ),
          child: AnimatedContainer(
            duration: Duration(milliseconds: reduce ? 0 : 160),
            transform: Matrix4.translationValues(
              0,
              !reduce && hovered && !pressed ? -2 : 0,
              0,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  top.withValues(
                    alpha: widget.translucent ? (dark ? .82 : .78) : 1,
                  ),
                  bottom.withValues(
                    alpha: widget.translucent ? (dark ? .82 : .78) : 1,
                  ),
                ],
              ),
              boxShadow: hovered
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: dark ? .22 : .10),
                        blurRadius: pressed ? 3 : 9,
                        offset: Offset(0, pressed ? 1 : 5),
                      ),
                    ]
                  : [],
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: focused
                    ? (dark ? const Color(0xff73b8ff) : const Color(0xff0d47c2))
                    : widget.translucent
                    ? Colors.white.withValues(alpha: dark ? .20 : .62)
                    : tint.withValues(alpha: .18),
                width: focused ? 2 : 1,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                onFocusChange: (v) => setState(() => focused = v),
                splashFactory: NoSplash.splashFactory,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                onHighlightChanged: (v) => setState(() => pressed = v),
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          EntryContent(entry: e),
                          const SizedBox(height: 12),
                          DefaultTextStyle(
                            style: TextStyle(
                              fontFamily: ReplicaMetrics.fontFamily,
                              fontFamilyFallback: ReplicaMetrics.fontFallback,
                              fontSize: 12,
                              color: dark
                                  ? const Color(0xfff0f2f7)
                                  : const Color(0xff1f242b),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(timestamp(e.lastCopiedAt)),
                                ),
                                const Text('  ·  '),
                                const Icon(CupertinoIcons.doc_on_doc, size: 12),
                                const SizedBox(width: 4),
                                Text('${e.count}'),
                                if (e.pinned) ...[
                                  const SizedBox(width: 7),
                                  const Icon(CupertinoIcons.pin_fill, size: 12),
                                ],
                                const SizedBox(width: 8),
                                const Spacer(),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 120,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(child: Text(e.source)),
                                      const SizedBox(width: 5),
                                      SourceIcon(e.sourceIcon),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.copied)
                      Positioned(
                        right: 9,
                        top: 9,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: dark
                                ? const Color(0xff1f4536)
                                : const Color(0xffe0f7eb),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.checkmark,
                                size: 11,
                                color: ReplicaMetrics.successText(context),
                              ),
                              SizedBox(width: 4),
                              Text(
                                '已复制',
                                style: TextStyle(
                                  fontFamily: ReplicaMetrics.fontFamily,
                                  fontFamilyFallback:
                                      ReplicaMetrics.fontFallback,
                                  fontSize: 11,
                                  color: ReplicaMetrics.successText(context),
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
          ),
        ),
      ),
    );
  }
}

class SourceIcon extends StatelessWidget {
  const SourceIcon(this.path, {super.key});
  final String path;
  @override
  Widget build(BuildContext context) => path.isEmpty
      ? SizedBox(
          width: 20,
          height: 20,
          child: Center(
            child: Icon(
              CupertinoIcons.app_fill,
              size: 14,
              color: secondary(context),
            ),
          ),
        )
      : Image.file(
          File(path),
          width: 20,
          height: 20,
          errorBuilder: (_, _, _) => Icon(
            CupertinoIcons.app_fill,
            size: 20,
            color: secondary(context),
          ),
        );
}

class EntryContent extends StatelessWidget {
  const EntryContent({super.key, required this.entry, this.detail = false});
  final ClipEntry entry;
  final bool detail;
  @override
  Widget build(BuildContext context) {
    final e = entry;
    if (e.kind == EntryKind.text) {
      Widget content;
      if (e.html.isNotEmpty || e.rtf.isNotEmpty) {
        final match = RegExp(
          r'<!--StartFragment-->([\s\S]*?)<!--EndFragment-->',
          caseSensitive: false,
        ).firstMatch(e.html);
        content = Container(
          padding: const EdgeInsets.all(12),
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark(context)
                ? const Color(0xff262a33)
                : const Color(0xfff7f7fa),
            borderRadius: BorderRadius.circular(12),
          ),
          child: HtmlWidget(
            e.html.isNotEmpty ? (match?.group(1) ?? e.html) : rtfPreview(e.rtf),
            textStyle: const TextStyle(
              fontFamily: ReplicaMetrics.fontFamily,
              fontFamilyFallback: ReplicaMetrics.fontFallback,
              fontSize: 14,
              height: 1.4,
            ),
            customWidgetBuilder: (element) =>
                [
                  'img',
                  'iframe',
                  'video',
                  'audio',
                  'script',
                  'object',
                ].contains(element.localName)
                ? const SizedBox.shrink()
                : null,
            onTapUrl: (_) => true,
          ),
        );
      } else {
        content = detail
            ? SelectableText(
                e.text,
                style: TextStyle(
                  fontFamily: ReplicaMetrics.fontFamily,
                  fontFamilyFallback: ReplicaMetrics.fontFallback,
                  fontSize: 14,
                  height: 1.428571,
                  color: ReplicaMetrics.cardPrimary(context),
                ),
              )
            : Text(
                e.text.length > 12000 ? e.text.substring(0, 12000) : e.text,
                style: TextStyle(
                  fontFamily: ReplicaMetrics.fontFamily,
                  fontFamilyFallback: ReplicaMetrics.fontFallback,
                  fontSize: 14,
                  height: 1.428571,
                  color: ReplicaMetrics.cardPrimary(context),
                ),
                textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                  applyHeightToLastDescent: false,
                ),
                overflow: TextOverflow.clip,
              );
      }
      if (detail) return content;
      return ClipRect(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 150),
          child: content,
        ),
      );
    }
    if (e.kind == EntryKind.file) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(CupertinoIcons.doc, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              e.title,
              maxLines: detail ? null : 3,
              style: TextStyle(
                fontFamily: ReplicaMetrics.fontFamily,
                fontFamilyFallback: ReplicaMetrics.fontFallback,
                fontSize: 14,
                height: 1.428571,
                color: ReplicaMetrics.cardPrimary(context),
              ),
            ),
          ),
        ],
      );
    }
    final path = e.kind == EntryKind.image ? e.imagePath : e.previewPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: path.isNotEmpty
              ? Image.file(
                  File(path),
                  width: double.infinity,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => _placeholder(context),
                )
              : _placeholder(context),
        ),
        if (e.kind == EntryKind.image) ...[
          const SizedBox(height: 8),
          Text(
            e.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: ReplicaMetrics.fontFamily,
              fontFamilyFallback: ReplicaMetrics.fontFallback,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _placeholder(BuildContext context) => AspectRatio(
    aspectRatio: entry.kind == EntryKind.video ? 16 / 9 : 1,
    child: ColoredBox(
      color: control(context),
      child: Icon(entry.kind.icon, size: 38, color: secondary(context)),
    ),
  );
}
