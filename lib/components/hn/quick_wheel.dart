import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/hn/hn_popover.dart';
import 'package:saber/components/hn/hn_pressable.dart';
import 'package:saber/components/theming/uni_icon.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/data/hn/hn_tuning.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/tool_id.dart';

/// 화면에 떠 있는 원형 퀵메뉴(Saber HN).
///
/// - 접힌 상태: 작은 동그라미(현재 펜). 끌어서 옮기고, 누르면 펼쳐진다.
/// - 펼친 상태: 가운데 펜, 둘레에 실행취소·다시실행·굵기·색·설정·숨기기.
///   - 가운데 펜을 좌우로 밀면 펜 종류가 바뀐다.
///   - 굵기 점을 누르면 둘레를 돌려 굵기를 바꾸는 다이얼로 바뀐다.
///   - 색 점을 누르면 둘레에 색상 링이 나온다.
class HnQuickWheel extends StatefulWidget {
  const new({
    super.key,
    required this.currentTool,
    required this.setTool,
    required this.setColor,
    required this.undo,
    required this.redo,
    required this.canUndo,
    required this.canRedo,
    required this.openSettings,
    required this.onHide,
  });

  final Tool currentTool;
  final ValueChanged<Tool> setTool;
  final ValueChanged<Color> setColor;
  final VoidCallback undo, redo;
  final bool canUndo, canRedo;

  /// 현재 펜의 설정 카드를 연다.
  final VoidCallback openSettings;

  /// 퀵메뉴를 화면에서 숨긴다.
  final VoidCallback onHide;

  @override
  State<HnQuickWheel> createState() => HnQuickWheelState();
}

enum _WheelMode { main, size, color }

/// 펜 넘기기 순서.
const _penOrder = [
  ToolId.fountainPen,
  ToolId.ballpointPen,
  ToolId.pencil,
  ToolId.highlighter,
  ToolId.shapePen,
];

Object _iconOf(ToolId id) => switch (id) {
  .fountainPen => Pen.fountainPenIcon,
  .ballpointPen => Pen.ballpointPenIcon,
  .pencil => Pencil.pencilIcon,
  .highlighter => Highlighter.highlighterIcon,
  .shapePen => ShapePen.shapePenIcon,
  _ => Pen.fountainPenIcon,
};

String _nameOf(ToolId id) => switch (id) {
  .fountainPen => t.editor.pens.fountainPen,
  .ballpointPen => t.editor.pens.ballpointPen,
  .pencil => t.editor.pens.pencil,
  .highlighter => t.editor.pens.highlighter,
  .shapePen => t.editor.pens.shapePen,
  _ => '',
};

/// [id]에 해당하는 펜 객체(이미 쓰던 것이 있으면 그대로).
Pen _penFor(ToolId id) => switch (id) {
  .fountainPen =>
    Pen.currentPen.toolId == .fountainPen ? Pen.currentPen : Pen.fountainPen(),
  .ballpointPen =>
    Pen.currentPen.toolId == .ballpointPen
        ? Pen.currentPen
        : Pen.ballpointPen(),
  .pencil => Pencil.currentPencil,
  .highlighter => Highlighter.currentHighlighter,
  .shapePen => Pen.currentPen is ShapePen ? Pen.currentPen : ShapePen(),
  _ => Pen.currentPen,
};

Color _opaque(Color c) => c.withAlpha(255);

class HnQuickWheelState extends State<HnQuickWheel> {
  var _expanded = false;
  var _mode = _WheelMode.main;

  /// 화면 비율 좌표(0~1)로 된 중심 위치.
  late var _pos = Offset(
    stows.hnQuickWheelX.value.clamp(0.0, 1.0),
    stows.hnQuickWheelY.value.clamp(0.0, 1.0),
  );

  // 펜 넘기기 상태
  double? _carouselStartIndex;
  var _carouselDx = 0.0;
  int get _carouselIndex =>
      (_carouselStartIndex! - _carouselDx / HnTuning.wheelCarouselStep)
          .round()
          .clamp(0, _penOrder.length - 1);

  Pen get _pen {
    final tool = widget.currentTool;
    return tool is Pen ? tool : Pen.currentPen;
  }

  bool get _penIsActive => widget.currentTool is Pen;

  /// 펼치기.
  void expand() => _setExpanded(true);

  void _setExpanded(bool expanded) {
    if (_expanded == expanded) return;
    HnTuning.selectionHaptic();
    setState(() {
      _expanded = expanded;
      if (!expanded) _mode = .main;
    });
  }

  void _setMode(_WheelMode mode) {
    HnTuning.selectionHaptic();
    setState(() => _mode = mode);
  }

  void _savePosition() {
    stows.hnQuickWheelX.value = _pos.dx;
    stows.hnQuickWheelY.value = _pos.dy;
  }

  Offset _clampCenter(Offset c, Size screen, double radius) {
    const margin = 8.0;
    double clampAxis(double v, double max) {
      final lo = radius + margin;
      final hi = max - radius - margin;
      if (hi < lo) return max / 2;
      return v.clamp(lo, hi);
    }

    return Offset(
      clampAxis(c.dx, screen.width),
      clampAxis(c.dy, screen.height),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        final raw = Offset(_pos.dx * screen.width, _pos.dy * screen.height);
        const d = HnTuning.wheelDiameter;
        const m = HnTuning.wheelMiniDiameter;
        final miniCenter = _clampCenter(raw, screen, m / 2);
        final wheelCenter = _clampCenter(raw, screen, d / 2);

        return Stack(
          children: [
            // 펼쳤을 때 바깥을 누르면 접힌다
            if (_expanded)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setExpanded(false),
                  onPanStart: (_) => _setExpanded(false),
                ),
              ),

            // 접힌 동그라미
            Positioned(
              left: miniCenter.dx - m / 2,
              top: miniCenter.dy - m / 2,
              width: m,
              height: m,
              child: IgnorePointer(
                ignoring: _expanded,
                child: AnimatedScale(
                  scale: _expanded ? 0.4 : 1,
                  duration: HnTuning.pressUpDuration,
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _expanded ? 0 : 1,
                    duration: const Duration(milliseconds: 140),
                    child: _MiniBubble(
                      pen: _pen,
                      active: _penIsActive,
                      onTap: () => _setExpanded(true),
                      onDrag: (delta) => setState(() {
                        final p = miniCenter + delta;
                        _pos = Offset(
                          (p.dx / screen.width).clamp(0.0, 1.0),
                          (p.dy / screen.height).clamp(0.0, 1.0),
                        );
                      }),
                      onDragEnd: _savePosition,
                    ),
                  ),
                ),
              ),
            ),

            // 펼친 원형 메뉴
            Positioned(
              left: wheelCenter.dx - d / 2,
              top: wheelCenter.dy - d / 2,
              width: d,
              height: d,
              child: IgnorePointer(
                ignoring: !_expanded,
                child: HnPopover(
                  visible: _expanded,
                  alignment: Alignment.center,
                  child: _buildWheel(context),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWheel(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    const d = HnTuning.wheelDiameter;

    final Widget content = switch (_mode) {
      .main => _buildMain(context),
      .size => _SizeDial(
        key: const ValueKey('size'),
        pen: _pen,
        onChanged: () => setState(() {}),
        onBack: () => _setMode(.main),
      ),
      .color => _ColorRing(
        key: const ValueKey('color'),
        current: _opaque(_pen.color),
        onPick: (color) {
          HnTuning.selectionHaptic();
          if (!_penIsActive) widget.setTool(_pen);
          widget.setColor(color);
          setState(() => _mode = .main);
        },
        onBack: () => _setMode(.main),
      ),
    };

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 바탕 원판
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.surface,
              border: Border.all(
                color: colorScheme.onSurface.withValues(alpha: 0.06),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween(begin: 0.92, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: content,
          ),
        ),
        // 펜 넘기기 중에 위쪽에 펜들이 호를 그리며 나타난다
        if (_carouselStartIndex != null)
          Positioned(
            left: 0,
            right: 0,
            top: -86,
            height: 120,
            child: IgnorePointer(
              child: _CarouselArc(
                position:
                    _carouselStartIndex! -
                    _carouselDx / HnTuning.wheelCarouselStep,
                selected: _carouselIndex,
                color: _opaque(_pen.color),
                width: d,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMain(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    const d = HnTuning.wheelDiameter;
    const c = d / 2;
    const ringRadius = 102.0;
    const itemSize = 46.0;

    Widget at(double degrees, Widget child) {
      final rad = degrees * math.pi / 180;
      return Positioned(
        left: c + ringRadius * math.cos(rad) - itemSize / 2,
        top: c + ringRadius * math.sin(rad) - itemSize / 2,
        width: itemSize,
        height: itemSize,
        child: child,
      );
    }

    final pen = _pen;
    final dotSize = 4 + 18 * SizePicker.percentFromSize(pen, pen.options.size);

    return Stack(
      key: const ValueKey('main'),
      children: [
        at(
          -135,
          _RingButton(
            tooltip: t.editor.toolbar.undo,
            enabled: widget.canUndo,
            onTap: widget.undo,
            child: const Icon(Icons.undo_rounded),
          ),
        ),
        at(
          -45,
          _RingButton(
            tooltip: t.editor.toolbar.redo,
            enabled: widget.canRedo,
            onTap: widget.redo,
            child: const Icon(Icons.redo_rounded),
          ),
        ),
        at(
          180,
          _RingButton(
            tooltip: '굵기 ${prettySize(pen.options.size)}',
            onTap: () => _setMode(.size),
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: colorScheme.onSurface,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        at(
          0,
          _RingButton(
            tooltip: '색',
            onTap: () => _setMode(.color),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _opaque(pen.color),
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.onSurface.withValues(alpha: 0.15),
                ),
              ),
            ),
          ),
        ),
        at(
          125,
          _RingButton(
            tooltip: '펜 설정',
            onTap: () {
              _setExpanded(false);
              widget.openSettings();
            },
            child: const Icon(Icons.tune_rounded, size: 22),
          ),
        ),
        at(
          55,
          _RingButton(
            tooltip: '퀵메뉴 숨기기',
            onTap: () {
              _setExpanded(false);
              widget.onHide();
            },
            child: const Icon(Icons.visibility_off_outlined, size: 20),
          ),
        ),

        // 가운데 펜: 누르면 접기, 좌우로 밀면 펜 바꾸기
        Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _setExpanded(false),
            onHorizontalDragStart: (_) => setState(() {
              _carouselStartIndex = math
                  .max(0, _penOrder.indexOf(pen.toolId))
                  .toDouble();
              _carouselDx = 0;
            }),
            onHorizontalDragUpdate: (details) {
              final before = _carouselIndex;
              setState(() => _carouselDx += details.delta.dx);
              if (_carouselIndex != before) HnTuning.selectionHaptic();
            },
            onHorizontalDragEnd: (_) {
              final id = _penOrder[_carouselIndex];
              setState(() => _carouselStartIndex = null);
              if (id != pen.toolId || !_penIsActive) {
                HnTuning.confirmHaptic();
                widget.setTool(_penFor(id));
              }
            },
            onHorizontalDragCancel: () =>
                setState(() => _carouselStartIndex = null),
            child: Container(
              width: 124,
              height: 124,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.55,
                ),
              ),
              child: Column(
                mainAxisAlignment: .center,
                children: [
                  AnimatedSwitcher(
                    duration: HnTuning.pressUpDuration,
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: UniIcon(
                      _iconOf(pen.toolId),
                      key: ValueKey(pen.toolId),
                      size: 40,
                      color: _penIsActive
                          ? _opaque(pen.color)
                          : colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _nameOf(pen.toolId),
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  Icon(
                    Icons.swap_horiz_rounded,
                    size: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 접힌 상태의 작은 동그라미.
class _MiniBubble extends StatelessWidget {
  const new({
    required this.pen,
    required this.active,
    required this.onTap,
    required this.onDrag,
    required this.onDragEnd,
  });

  final Pen pen;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return HnPressable(
      scale: 0.9,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onPanUpdate: (d) => onDrag(d.delta),
        onPanEnd: (_) => onDragEnd(),
        child: Tooltip(
          message: '퀵메뉴 (끌어서 이동)',
          waitDuration: const Duration(seconds: 1),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.surface,
              border: Border.all(
                color: colorScheme.onSurface.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: UniIcon(
                _iconOf(pen.toolId),
                size: 22,
                color: active
                    ? _opaque(pen.color)
                    : colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingButton extends StatelessWidget {
  const new({
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.enabled = true,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 700),
      child: HnPressable(
        enabled: enabled,
        scale: 0.88,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () {
                  HnTuning.selectionHaptic();
                  onTap();
                }
              : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            ),
            child: IconTheme.merge(
              data: IconThemeData(
                color: enabled
                    ? colorScheme.onSurface
                    : colorScheme.onSurface.withValues(alpha: 0.25),
              ),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// 펜 넘기기 중에 위에 뜨는 펜들의 호.
class _CarouselArc extends StatelessWidget {
  const new({
    required this.position,
    required this.selected,
    required this.color,
    required this.width,
  });

  /// 실수 위치(0~4 사이를 연속적으로 움직임).
  final double position;
  final int selected;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    const radius = 180.0;
    const stepDegrees = 26.0;
    final cx = width / 2;
    const cy = 180.0 + 30;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < _penOrder.length; i++)
          () {
            final offset = i - position.clamp(-0.4, _penOrder.length - 0.6);
            final rad = (-90 + offset * stepDegrees) * math.pi / 180;
            final isSel = i == selected;
            final scale = (1.25 - 0.25 * offset.abs()).clamp(0.6, 1.25);
            final opacity = (1 - 0.3 * offset.abs()).clamp(0.0, 1.0);
            return Positioned(
              left: cx + radius * math.cos(rad) - 24,
              top: cy + radius * math.sin(rad) - 24,
              width: 48,
              height: 48,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.surface,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isSel ? 0.2 : 0.08,
                          ),
                          blurRadius: isSel ? 12 : 6,
                        ),
                      ],
                    ),
                    child: Center(
                      child: UniIcon(
                        _iconOf(_penOrder[i]),
                        size: 20,
                        color: isSel
                            ? color
                            : colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }
}

/// 둘레를 돌려 굵기를 바꾸는 다이얼.
class _SizeDial extends StatefulWidget {
  const new({
    super.key,
    required this.pen,
    required this.onChanged,
    required this.onBack,
  });

  final Pen pen;
  final VoidCallback onChanged;
  final VoidCallback onBack;

  /// 다이얼이 시작하는 각도(왼쪽 아래)와 도는 범위.
  static const startDegrees = 135.0;
  static const sweepDegrees = 270.0;

  @override
  State<_SizeDial> createState() => _SizeDialState();
}

class _SizeDialState extends State<_SizeDial> {
  static const _d = HnTuning.wheelDiameter;
  static const _innerRadius = 62.0;

  void _update(Offset local) {
    final v = local - const Offset(_d / 2, _d / 2);
    if (v.distance < _innerRadius * 0.6) return;
    final deg = math.atan2(v.dy, v.dx) * 180 / math.pi;
    var rel = (deg - _SizeDial.startDegrees) % 360;
    if (rel < 0) rel += 360;
    double t;
    if (rel <= _SizeDial.sweepDegrees) {
      t = rel / _SizeDial.sweepDegrees;
    } else {
      // 아래쪽 빈 구간: 가까운 끝으로
      t = rel < _SizeDial.sweepDegrees + (360 - _SizeDial.sweepDegrees) / 2
          ? 1
          : 0;
    }
    final pen = widget.pen;
    final newSize = SizePicker.sizeFromPercent(pen, t);
    final oldSize = pen.options.size;
    if (newSize == oldSize) return;
    final tickUnit = pen.sizeMax > 50 ? 10.0 : 1.0;
    if (HnTuning.hapticsEnabled &&
        (newSize / tickUnit).floor() != (oldSize / tickUnit).floor()) {
      HapticFeedback.selectionClick();
    }
    pen.options.size = newSize;
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final pen = widget.pen;
    final t = SizePicker.percentFromSize(pen, pen.options.size);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => _update(d.localPosition),
      onPanUpdate: (d) => _update(d.localPosition),
      onPanEnd: (_) => pen.saveOptions(),
      onTapUp: (d) {
        final v = d.localPosition - const Offset(_d / 2, _d / 2);
        if (v.distance < _innerRadius) {
          widget.onBack();
        } else {
          _update(d.localPosition);
          pen.saveOptions();
        }
      },
      child: CustomPaint(
        painter: _SizeDialPainter(
          t: t,
          track: colorScheme.onSurface.withValues(alpha: 0.1),
          active: colorScheme.primary,
          knob: colorScheme.surface,
        ),
        child: Stack(
          children: [
            Center(
              child: Container(
                width: _innerRadius * 2,
                height: _innerRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: .center,
                  children: [
                    Text(
                      prettySize(pen.options.size),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      '굵기 · 눌러서 돌아가기',
                      style: TextStyle(
                        fontSize: 9,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SizeDialPainter extends CustomPainter {
  new({
    required this.t,
    required this.track,
    required this.active,
    required this.knob,
  });

  final double t;
  final Color track, active, knob;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const radius = 104.0;
    const start = _SizeDial.startDegrees * math.pi / 180;
    const sweep = _SizeDial.sweepDegrees * math.pi / 180;

    // 쐐기처럼 점점 두꺼워지는 트랙(눈금 점)
    const ticks = 40;
    for (var i = 0; i <= ticks; i++) {
      final f = i / ticks;
      final a = start + sweep * f;
      final p = center + Offset(math.cos(a), math.sin(a)) * radius;
      canvas.drawCircle(p, 2 + 6 * f, Paint()..color = f <= t ? active : track);
    }

    // 손잡이
    final a = start + sweep * t;
    final p = center + Offset(math.cos(a), math.sin(a)) * radius;
    canvas.drawCircle(
      p + const Offset(0, 1),
      13,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(p, 13, Paint()..color = knob);
    canvas.drawCircle(
      p,
      13,
      Paint()
        ..color = active
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SizeDialPainter old) =>
      old.t != t || old.track != track || old.active != active;
}

/// 둘레에 색을 늘어놓은 링.
class _ColorRing extends StatelessWidget {
  const new({
    super.key,
    required this.current,
    required this.onPick,
    required this.onBack,
  });

  final Color current;
  final ValueChanged<Color> onPick;
  final VoidCallback onBack;

  static List<Color> get colors {
    final list = <Color>[];
    for (final c in ColorBar.colorPresets) {
      if (list.length >= 12) break;
      if (!list.contains(c.color)) list.add(c.color);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    const d = HnTuning.wheelDiameter;
    const c = d / 2;
    const r = 102.0;
    final palette = colors;
    final step = 360 / palette.length;

    return Stack(
      children: [
        for (var i = 0; i < palette.length; i++)
          () {
            final rad = (-90 + step * i) * math.pi / 180;
            final color = palette[i];
            final selected = color.toARGB32() == current.toARGB32();
            const s = 34.0;
            return Positioned(
              left: c + r * math.cos(rad) - s / 2,
              top: c + r * math.sin(rad) - s / 2,
              width: s,
              height: s,
              child: HnPressable(
                scale: 0.85,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(color),
                  child: AnimatedContainer(
                    duration: HnTuning.pressUpDuration,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      border: Border.all(
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.onSurface.withValues(alpha: 0.15),
                        width: selected ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }(),
        Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBack,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.55,
                ),
              ),
              child: Column(
                mainAxisAlignment: .center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: current,
                      border: Border.all(
                        color: colorScheme.onSurface.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '눌러서 돌아가기',
                    style: TextStyle(
                      fontSize: 9,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
