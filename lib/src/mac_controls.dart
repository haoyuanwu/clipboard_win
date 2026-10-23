part of 'app.dart';

/// Values transcribed from ClipboardLayout, ClipboardTheme and the SwiftUI scenes.
abstract final class ReplicaMetrics {
  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.3.2',
  );
  static const mainSize = Size(440, 640);
  static const popoverSize = Size(390, 520);
  static const transferSize = Size(350, 520);
  static const detailSize = Size(420, 420);
  static const panelSize = Size(390, 440);
  static const inset = 16.0, cardGap = 12.0, cardRadius = 16.0;
  static const titleHeight = 52.0, filterHeight = 42.0;
  static const fontFamily = 'Segoe UI';
  static const fontFallback = ['Microsoft YaHei UI', 'Microsoft YaHei'];
  static const lightCategory = [
    Color(0xff1a5ce0),
    Color(0xff007557),
    Color(0xff8f2bc2),
    Color(0xffad5e08),
    Color(0xff334ad4),
  ];
  static const darkCategory = [
    Color(0xffa8b5c7),
    Color(0xff87baad),
    Color(0xffb89ec4),
    Color(0xffc7b08a),
    Color(0xff94adcc),
  ];
  static Color page(BuildContext c) =>
      isDark(c) ? const Color(0xff1f2229) : Colors.white;
  static Color primary(BuildContext c) =>
      isDark(c) ? const Color(0xfff0f2f7) : const Color(0xff1a1f26);
  static Color cardPrimary(BuildContext c) =>
      isDark(c) ? const Color(0xfff5f7fc) : Colors.black;
  static Color cardSecondary(BuildContext c) =>
      isDark(c) ? const Color(0xfff0f2f7) : const Color(0xff1f242b);
  static Color border(BuildContext c) =>
      (isDark(c) ? Colors.white : Colors.black).withValues(alpha: .12);
  static Color successFill(BuildContext c) =>
      isDark(c) ? const Color(0xff1f4536) : const Color(0xffe0f7eb);
  static Color successText(BuildContext c) =>
      isDark(c) ? const Color(0xff96f0ba) : const Color(0xff0f5c38);
  static Color action(BuildContext c) =>
      isDark(c) ? const Color(0xff73b8ff) : const Color(0xff1f5ce0);
  static Color actionText(BuildContext c) =>
      isDark(c) ? const Color(0xff0d1729) : Colors.white;
}

class MacWindowControls extends StatefulWidget {
  const MacWindowControls({
    super.key,
    required this.enabled,
    this.transfer = false,
  });
  final bool enabled, transfer;
  @override
  State<MacWindowControls> createState() => _MacWindowControlsState();
}

class _MacWindowControlsState extends State<MacWindowControls> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: SizedBox(
      width: 78,
      height: widget.transfer ? 44 : 46,
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 8),
        child: Row(
          children: [
            _button(
              context,
              const Color(0xffff5f57),
              '关闭窗口',
              CupertinoIcons.xmark,
              'close',
            ),
            _button(
              context,
              const Color(0xfffebc2e),
              '最小化窗口',
              CupertinoIcons.minus,
              'minimize',
            ),
            _button(
              context,
              const Color(0xff28c840),
              '缩放窗口',
              CupertinoIcons.plus,
              'zoom',
            ),
          ],
        ),
      ),
    ),
  );
  Widget _button(
    BuildContext c,
    Color color,
    String label,
    IconData icon,
    String action,
  ) => SizedBox(
    width: 20,
    height: 24,
    child: Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled
              ? () => WindowsBridge.call('windowAction', action)
              : () {},
          child: Center(
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.black.withValues(alpha: .12),
                  width: .5,
                ),
              ),
              child: hovered
                  ? Icon(
                      icon,
                      size: 8,
                      color: Colors.black.withValues(alpha: .60),
                    )
                  : null,
            ),
          ),
        ),
      ),
    ),
  );
}

class ToolButton extends StatelessWidget {
  const ToolButton(
    this.icon,
    this.label,
    this.onPressed, {
    super.key,
    this.selected = false,
    this.size = 32,
    this.iconSize = 14,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final double size, iconSize;
  final Color? color;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      selected: selected,
      label: label,
      button: true,
      child: SizedBox(
        width: size,
        height: size,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            fixedSize: Size.square(size),
            minimumSize: Size.zero,
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: color ?? accent(context),
            disabledForegroundColor: (color ?? accent(context)).withValues(
              alpha: .5,
            ),
            backgroundColor: selected ? control(context) : Colors.transparent,
            overlayColor: control(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            splashFactory: NoSplash.splashFactory,
          ),
          child: Icon(icon, size: iconSize),
        ),
      ),
    ),
  );
}

/// Shared translucent frost. Backgrounds blur; text and controls stay sharp.
class GlassActivityScope extends InheritedWidget {
  const GlassActivityScope({
    super.key,
    required this.active,
    required super.child,
  });
  final bool active;
  static bool activeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GlassActivityScope>()
          ?.active ??
      true;
  @override
  bool updateShouldNotify(GlassActivityScope oldWidget) =>
      active != oldWidget.active;
}

class MacGlassSurface extends StatelessWidget {
  const MacGlassSurface({
    super.key,
    required this.child,
    this.transfer = false,
    this.radius = 18,
    this.strip = false,
  });
  final Widget child;
  final bool transfer, strip;
  final double radius;
  static const blurSigma = 28.0;
  @override
  Widget build(BuildContext context) {
    final dark = isDark(context), opaque = MediaQuery.highContrastOf(context);
    final active = GlassActivityScope.activeOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: opaque ? ReplicaMetrics.page(context) : null,
                  gradient: opaque
                      ? null
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: dark
                              ? [
                                  const Color(0xff353c48).withValues(
                                    alpha: strip
                                        ? .42
                                        : active
                                        ? .76
                                        : .58,
                                  ),
                                  const Color(0xff1d222c).withValues(
                                    alpha: strip
                                        ? .36
                                        : active
                                        ? .70
                                        : .52,
                                  ),
                                ]
                              : [
                                  Colors.white.withValues(
                                    alpha: strip
                                        ? .46
                                        : active
                                        ? .72
                                        : .54,
                                  ),
                                  const Color(0xffedf1f7).withValues(
                                    alpha: strip
                                        ? .38
                                        : active
                                        ? .64
                                        : .46,
                                  ),
                                ],
                        ),
                ),
              ),
            ),
          ),
          child,
          if (!strip)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: dark ? .18 : .55),
                      width: .75,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FrostedDialog extends StatelessWidget {
  const FrostedDialog({
    super.key,
    required this.child,
    this.insetPadding = const EdgeInsets.all(10),
  });
  final Widget child;
  final EdgeInsets insetPadding;
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    insetPadding: insetPadding,
    child: MacGlassSurface(
      radius: WindowStyleScope.isWindows(context) ? 8 : 16,
      child: child,
    ),
  );
}

class MacCategoryButton extends StatefulWidget {
  const MacCategoryButton({
    super.key,
    required this.kind,
    required this.selected,
    required this.onTap,
  });
  final EntryKind? kind;
  final bool selected;
  final VoidCallback onTap;
  @override
  State<MacCategoryButton> createState() => _MacCategoryButtonState();
}

class _MacCategoryButtonState extends State<MacCategoryButton> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final dark = isDark(context),
        index = widget.kind == null ? 0 : widget.kind!.index + 1;
    final tint = (dark
        ? ReplicaMetrics.darkCategory
        : ReplicaMetrics.lightCategory)[index];
    final fill = dark
        ? tint.withValues(
            alpha: hover
                ? .30
                : widget.selected
                ? .20
                : .07,
          )
        : widget.selected
        ? tint
        : tint.withValues(alpha: hover ? .18 : .09);
    return Padding(
      padding: EdgeInsets.only(right: widget.kind == EntryKind.video ? 0 : 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: Tooltip(
          message: widget.kind?.label ?? '全部',
          child: Semantics(
            selected: widget.selected,
            child: SizedBox(
              height: 28,
              child: TextButton(
                onPressed: widget.onTap,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  splashFactory: NoSplash.splashFactory,
                  foregroundColor: !dark && widget.selected
                      ? Colors.white
                      : ReplicaMetrics.primary(context),
                  backgroundColor: fill,
                  overlayColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: TextStyle(
                    fontFamily: ReplicaMetrics.fontFamily,
                    fontFamilyFallback: ReplicaMetrics.fontFallback,
                    fontSize: 11,
                    height: 1,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      child: Icon(
                        widget.kind?.icon ?? CupertinoIcons.square_grid_2x2,
                        size: 12,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      widget.kind?.label ?? '全部',
                      maxLines: 1,
                      softWrap: false,
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

/// Keep the native backdrop in step with the Flutter theme and accessibility.
class NativeGlassHost extends StatefulWidget {
  const NativeGlassHost({
    super.key,
    required this.child,
    required this.enabled,
  });
  final Widget child;
  final bool enabled;
  @override
  State<NativeGlassHost> createState() => _NativeGlassHostState();
}

class _NativeGlassHostState extends State<NativeGlassHost> {
  (bool, bool)? appearance;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = (isDark(context), MediaQuery.highContrastOf(context));
    if (appearance == next) return;
    appearance = next;
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          WindowsBridge.call('glassAppearance', {
            'dark': next.$1,
            'opaque': next.$2,
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
