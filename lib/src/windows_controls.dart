part of 'app.dart';

/// Platform chrome is a preference, independent of content and glass styling.
class WindowStyleScope extends InheritedWidget {
  const WindowStyleScope({
    super.key,
    required this.windows,
    required super.child,
  });
  final bool windows;
  static bool isWindows(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WindowStyleScope>()?.windows ??
      true;
  @override
  bool updateShouldNotify(WindowStyleScope oldWidget) =>
      windows != oldWidget.windows;
}

class WindowChromeHost extends StatefulWidget {
  const WindowChromeHost({
    super.key,
    required this.store,
    required this.windows,
    required this.child,
  });
  final ClipboardStore store;
  final bool windows;
  final Widget child;
  @override
  State<WindowChromeHost> createState() => _WindowChromeHostState();
}

class _WindowChromeHostState extends State<WindowChromeHost> {
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(WindowChromeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.windows != widget.windows) _sync();
  }

  void _sync() {
    if (!widget.store.usePlatform) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final maximized = await WindowsBridge.call<bool>(
        'setWindowStyle',
        widget.windows ? 'windows' : 'mac',
      );
      if (mounted && maximized != null) {
        widget.store.setWindowMaximized(maximized);
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      WindowStyleScope(windows: widget.windows, child: widget.child);
}

class WindowsTitleBar extends StatelessWidget {
  const WindowsTitleBar({
    super.key,
    required this.title,
    required this.enabled,
    required this.maximized,
    this.trailing,
  });
  final String title;
  final bool enabled, maximized;
  final Widget? trailing;
  void _action(String action) {
    if (enabled) WindowsBridge.call('windowAction', action);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 32,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: enabled
                ? (_) => WindowsBridge.call('dragWindow')
                : null,
            onDoubleTap: () => _action('zoom'),
            onSecondaryTapUp: enabled
                ? (_) => WindowsBridge.call('windowMenu')
                : null,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Row(
                children: [
                  Image.asset('assets/app_logo.png', width: 16, height: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: ReplicaMetrics.fontFamily,
                        fontFamilyFallback: ReplicaMetrics.fontFallback,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: ReplicaMetrics.primary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ?trailing,
        WindowsWindowControls(enabled: enabled, maximized: maximized),
      ],
    ),
  );
}

class WindowsWindowControls extends StatelessWidget {
  const WindowsWindowControls({
    super.key,
    required this.enabled,
    required this.maximized,
  });
  final bool enabled, maximized;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 138,
    height: 32,
    child: Row(
      children: [
        _WindowsCaptionButton(
          action: 'minimize',
          label: '最小化窗口',
          enabled: enabled,
        ),
        _WindowsCaptionButton(
          action: 'zoom',
          label: maximized ? '还原窗口' : '最大化窗口',
          enabled: enabled,
          restore: maximized,
        ),
        _WindowsCaptionButton(action: 'close', label: '关闭窗口', enabled: enabled),
      ],
    ),
  );
}

class _WindowsCaptionButton extends StatefulWidget {
  const _WindowsCaptionButton({
    required this.action,
    required this.label,
    required this.enabled,
    this.restore = false,
  });
  final String action, label;
  final bool enabled, restore;
  @override
  State<_WindowsCaptionButton> createState() => _WindowsCaptionButtonState();
}

class _WindowsCaptionButtonState extends State<_WindowsCaptionButton> {
  bool hover = false, pressed = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final close = widget.action == 'close';
    final color = close && (hover || pressed)
        ? Colors.white
        : ReplicaMetrics.primary(context);
    final fill = close && (hover || pressed)
        ? (pressed ? const Color(0xffa82317) : const Color(0xffc42b1c))
        : (isDark(context) ? Colors.white : Colors.black).withValues(
            alpha: pressed
                ? .12
                : hover
                ? .075
                : 0,
          );
    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() {
          hover = false;
          pressed = false;
        }),
        child: SizedBox(
          width: 46,
          height: 32,
          child: Listener(
            onPointerDown: (_) => setState(() => pressed = true),
            onPointerUp: (_) => setState(() => pressed = false),
            onPointerCancel: (_) => setState(() => pressed = false),
            child: TextButton(
              key: ValueKey('windows-caption-${widget.action}'),
              onPressed: () {
                if (widget.enabled) {
                  WindowsBridge.call('windowAction', widget.action);
                }
              },
              onFocusChange: (value) => setState(() => focused = value),
              onHover: (value) => setState(() => hover = value),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: fill,
                overlayColor: close ? Colors.white12 : control(context),
                shape: RoundedRectangleBorder(
                  side: focused
                      ? BorderSide(color: accent(context))
                      : BorderSide.none,
                ),
                splashFactory: NoSplash.splashFactory,
              ),
              child: Semantics(
                label: widget.label,
                child: CustomPaint(
                  size: const Size(10, 10),
                  painter: _WindowsCaptionPainter(
                    widget.action,
                    widget.restore,
                    color,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowsCaptionPainter extends CustomPainter {
  const _WindowsCaptionPainter(this.action, this.restore, this.color);
  final String action;
  final bool restore;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    if (action == 'minimize') {
      canvas.drawLine(const Offset(0, 5.5), const Offset(10, 5.5), pen);
    } else if (action == 'close') {
      canvas.drawLine(const Offset(.5, .5), const Offset(9.5, 9.5), pen);
      canvas.drawLine(const Offset(9.5, .5), const Offset(.5, 9.5), pen);
    } else if (restore) {
      canvas.drawPath(
        Path()
          ..moveTo(2.5, 2.5)
          ..lineTo(2.5, .5)
          ..lineTo(9.5, .5)
          ..lineTo(9.5, 7.5)
          ..lineTo(7.5, 7.5),
        pen,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(.5, 2.5, 7, 7),
          const Radius.circular(.5),
        ),
        pen,
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(.5, .5, 9, 9),
          const Radius.circular(.5),
        ),
        pen,
      );
    }
  }

  @override
  bool shouldRepaint(_WindowsCaptionPainter oldDelegate) =>
      action != oldDelegate.action ||
      restore != oldDelegate.restore ||
      color != oldDelegate.color;
}
