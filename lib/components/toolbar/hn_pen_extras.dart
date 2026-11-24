import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/hn/hn_pressable.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/data/hn/hn_tuning.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:stow_plain/stow_plain.dart';

/// 현재 펜 설정(굵기·안정화·필압·색)으로 그린 미리보기 선.
///
/// 일부러 손떨림처럼 살짝 흔들린 점들을 넣어서, 안정화 값을 바꾸면
/// 선이 얼마나 매끈해지는지 바로 보이게 한다.
class StrokePreview extends StatelessWidget {
  const new({super.key, required this.pen});

  final Pen pen;

  static const width = 84.0;
  static const height = 40.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    var color = pen.color;
    if (pen is Highlighter) {
      color = color.withAlpha(Highlighter.alpha);
    }
    return Tooltip(
      message: '미리보기',
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: _StrokePreviewPainter(
            size: pen.options.size,
            stabilization: pen.options.streamline,
            smoothing: pen.options.smoothing,
            thinning: pen.options.thinning,
            pressureEnabled: pen.pressureEnabled,
            taperStart: pen.options.start.taperEnabled,
            taperEnd: pen.options.end.taperEnabled,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _StrokePreviewPainter extends CustomPainter {
  new({
    required this.size,
    required this.stabilization,
    required this.smoothing,
    required this.thinning,
    required this.pressureEnabled,
    required this.taperStart,
    required this.taperEnd,
    required this.color,
  });

  final double size;
  final double stabilization;
  final double smoothing;
  final double thinning;
  final bool pressureEnabled;
  final bool taperStart, taperEnd;
  final Color color;

  /// 매번 같은 모양이 나오도록 고정된 의사 난수.
  static double _noise(int i) {
    final v = math.sin(i * 12.9898 + 78.233) * 43758.5453;
    return (v - v.floorToDouble()) * 2 - 1;
  }

  @override
  void paint(Canvas canvas, Size canvasSize) {
    // 실제 굵기가 칸에 다 들어가지 않으면 축소해서 보여 준다.
    final maxDrawable = canvasSize.height * 0.55;
    final scale = size > maxDrawable ? maxDrawable / size : 1.0;

    const n = 48;
    final margin = 10 + size * scale / 2;
    final w = canvasSize.width - margin * 2;
    // 굵은 선(형광펜)은 곡선을 납작하게 해서 띠처럼 보이게 한다
    final h = math.max(1.5, canvasSize.height * 0.28 - size * scale * 0.35);
    final cy = canvasSize.height / 2;
    final points = <PointVector>[
      for (var i = 0; i <= n; i++)
        () {
          final t = i / n;
          final x = margin + w * t + _noise(i) * 0.9;
          final y = cy - math.sin(t * math.pi * 2) * h + _noise(i + 97) * 1.4;
          // 필압 펜은 가운데에서 세게, 양끝에서 약하게
          final pressure = 0.35 + 0.45 * math.sin(t * math.pi);
          return PointVector(x / scale, y / scale, pressure);
        }(),
    ];

    final outline = getStroke(
      points,
      options: StrokeOptions(
        size: size,
        thinning: thinning,
        smoothing: smoothing,
        streamline: stabilization,
        simulatePressure: false,
        start: StrokeEndOptions.start(taperEnabled: taperStart),
        end: StrokeEndOptions.end(taperEnabled: taperEnd),
        isComplete: true,
      )..thinning = pressureEnabled ? thinning : 0,
    );
    if (outline.isEmpty) return;

    final path = Path()..addPolygon(outline, true);
    canvas.save();
    canvas.scale(scale);
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StrokePreviewPainter old) =>
      old.size != size ||
      old.stabilization != stabilization ||
      old.smoothing != smoothing ||
      old.thinning != thinning ||
      old.pressureEnabled != pressureEnabled ||
      old.taperStart != taperStart ||
      old.taperEnd != taperEnd ||
      old.color != color;
}

/// 즐겨찾기 굵기 버튼 3개. 누르면 적용, 길게 누르면 현재 굵기로 저장.
class FavoriteSizes extends StatefulWidget {
  const new({
    super.key,
    required this.axis,
    required this.pen,
    required this.onChanged,
  });

  final Axis axis;
  final Pen pen;
  final VoidCallback onChanged;

  @override
  State<FavoriteSizes> createState() => _FavoriteSizesState();
}

class _FavoriteSizesState extends State<FavoriteSizes> {
  /// 방금 저장한 칸(잠깐 강조 표시용).
  int? _justSaved;

  PlainStow<List<String>>? get _stow =>
      stows.hnFavoriteSizesFor(widget.pen.toolId);

  List<double> get _sizes {
    final stow = _stow;
    final raw = stow?.value ?? const ['1.5', '3', '6'];
    return [
      for (var i = 0; i < 3; i++)
        widget.pen.snapSize(
          double.tryParse(i < raw.length ? raw[i] : '') ??
              widget.pen.options.size,
        ),
    ];
  }

  void _apply(double size) {
    HnTuning.selectionHaptic();
    widget.pen.options.size = size;
    widget.pen.saveOptions();
    widget.onChanged();
  }

  void _save(int index) {
    final stow = _stow;
    if (stow == null) return;
    final sizes = _sizes;
    sizes[index] = widget.pen.snapSize(widget.pen.options.size);
    stow.value = [for (final s in sizes) prettySize(s)];
    HnTuning.confirmHaptic();
    setState(() => _justSaved = index);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted && _justSaved == index) setState(() => _justSaved = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sizes = _sizes;
    final maxSize = sizes.fold<double>(1, math.max);
    return Flex(
      direction: widget.axis,
      mainAxisSize: .min,
      spacing: 4,
      children: [
        for (var i = 0; i < sizes.length; i++)
          _FavoriteSizeButton(
            size: sizes[i],
            maxSize: maxSize,
            color: widget.pen is Highlighter
                ? widget.pen.color.withAlpha(255)
                : widget.pen.color,
            selected: (sizes[i] - widget.pen.options.size).abs() < 0.05,
            justSaved: _justSaved == i,
            onTap: () => _apply(sizes[i]),
            onLongPress: () => _save(i),
          ),
      ],
    );
  }
}

class _FavoriteSizeButton extends StatelessWidget {
  const new({
    required this.size,
    required this.maxSize,
    required this.color,
    required this.selected,
    required this.justSaved,
    required this.onTap,
    required this.onLongPress,
  });

  final double size, maxSize;
  final Color color;
  final bool selected, justSaved;
  final VoidCallback onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    // 점 크기: 굵기 비율을 살리되 너무 작거나 크지 않게
    final dot = 4 + 14 * math.sqrt(size / maxSize);
    return Tooltip(
      message: '굵기 ${prettySize(size)} · 길게 눌러 현재 굵기 저장',
      waitDuration: const Duration(milliseconds: 600),
      child: HnPressable(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: onLongPress,
          child: AnimatedContainer(
            duration: HnTuning.pressUpDuration,
            curve: Curves.easeOutCubic,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: justSaved
                  ? colorScheme.primary.withValues(alpha: 0.25)
                  : selected
                  ? colorScheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              border: Border.all(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.2),
                width: selected ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

/// 획 안정화 슬라이더.
class StabilizationPicker extends StatelessWidget {
  const new({
    super.key,
    required this.axis,
    required this.pen,
    required this.onChanged,
  });

  final Axis axis;
  final Pen pen;
  final VoidCallback onChanged;

  static const tooltip = '획 안정화: 높을수록 선이 매끈해지지만, 선이 펜촉보다 조금 늦게 따라옵니다.';

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final value = pen.stabilization.clamp(
      HnTuning.stabilizationMin,
      HnTuning.stabilizationMax,
    );
    final percent = (value * 100).round();

    final slider = SizedBox(
      width: 140,
      height: 36,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          tickMarkShape: SliderTickMarkShape.noTickMark,
        ),
        child: Slider(
          value: value,
          min: HnTuning.stabilizationMin,
          max: HnTuning.stabilizationMax,
          divisions: HnTuning.stabilizationDivisions,
          onChanged: (v) {
            if ((v - pen.stabilization).abs() < 0.001) return;
            HnTuning.selectionHaptic();
            pen.stabilization = v;
            onChanged();
          },
          onChangeEnd: (_) => pen.saveOptions(),
        ),
      ),
    );

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Flex(
        direction: axis,
        mainAxisSize: .min,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              mainAxisSize: .min,
              children: [
                Text(
                  '안정화',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.8),
                    fontSize: 10,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$percent',
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          RotatedBox(quarterTurns: axis == .horizontal ? 0 : 1, child: slider),
        ],
      ),
    );
  }
}
