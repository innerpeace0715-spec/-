import 'package:material_ui/material_ui.dart';
import 'package:saber/components/hn/hn_pen_art.dart';
import 'package:saber/components/hn/hn_pressable.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/components/toolbar/hn_pen_extras.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/data/hn/hn_pens.dart';
import 'package:saber/data/hn/hn_tuning.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:sbn/tool_id.dart';

/// 펜 설정 창(Saber HN, 삼성노트 펜 설정 창을 본뜸).
///
/// 위: 펜 그림 5개(만년필·볼펜·연필·형광펜·도형펜)
/// 가운데: 굵기, 색, 투명도, 필압, 손떨림 보정
/// 아래: 꾹 눌러 도형 만들기, 손가락 탭 실행취소
class PenModal<T extends Pen> extends StatefulWidget {
  const new({
    super.key,
    required this.getTool,
    required this.setTool,
    this.setColor,
    this.onMoreColors,
  });

  /// 지금 설정할 펜.
  final T Function() getTool;

  /// 다른 펜으로 바꾼다.
  final void Function(Pen) setTool;

  /// 색을 바꾼다(없으면 색 줄을 숨긴다).
  final ValueChanged<Color>? setColor;

  /// "색 더 보기"(전체 색상 막대 열기).
  final VoidCallback? onMoreColors;

  static const double width = 340;
  static const double _hPad = 20;
  // 좌우 여백 + 테두리 1씩
  static const double _innerWidth = width - 2 * _hPad - 2;

  @override
  State<PenModal<T>> createState() => _PenModalState<T>();
}

class _PenModalState<T extends Pen> extends State<PenModal<T>> {
  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final pen = widget.getTool();
    final colorScheme = ColorScheme.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;

    final divider = Divider(
      height: 20,
      thickness: 1,
      color: colorScheme.onSurface.withValues(alpha: 0.07),
    );

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: PenModal.width,
        constraints: BoxConstraints(maxHeight: screenHeight * 0.82),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: colorScheme.onSurface.withValues(alpha: 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const .fromLTRB(PenModal._hPad, 6, PenModal._hPad, 10),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              // ── 펜 고르기 ──
              _PenRow(
                current: pen,
                onPick: (id) {
                  if (id == pen.toolId) return;
                  HnTuning.selectionHaptic();
                  widget.setTool(hnPenFor(id));
                  _refresh();
                },
              ),
              Center(
                child: Text(
                  pen.name,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
              divider,

              // ── 굵기 ──
              _LabelRow(label: '굵기', value: prettySize(pen.options.size)),
              Center(
                child: SizePicker(
                  axis: .horizontal,
                  pen: pen,
                  onChanged: _refresh,
                  showLabel: false,
                  length:
                      PenModal._innerWidth -
                      2 * HnTuning.sizeSliderTouchPadding,
                ),
              ),
              Row(
                children: [
                  FavoriteSizes(
                    axis: .horizontal,
                    pen: pen,
                    onChanged: _refresh,
                  ),
                  const Spacer(),
                  StrokePreview(pen: pen),
                ],
              ),

              // ── 색 ──
              if (widget.setColor != null) ...[
                divider,
                _Palette(
                  current: pen.color.withAlpha(255),
                  onPick: (c) {
                    HnTuning.selectionHaptic();
                    widget.setColor!(c);
                    _refresh();
                  },
                  onMore: widget.onMoreColors,
                ),
              ],
              divider,

              // ── 세부 설정 ──
              HnLabeledSlider(
                label: '투명도',
                valueText: '${((1 - pen.inkFlow) * 100).round()}%',
                value: 1 - pen.inkFlow,
                min: 0,
                max: 0.9,
                divisions: 18,
                tooltip: '선이 비치는 정도. 새로 긋는 선부터 적용됩니다.',
                onChanged: (v) {
                  pen.inkFlow = 1 - v;
                  _refresh();
                },
              ),
              if (pen.pressureEnabled)
                HnLabeledSlider(
                  label: '필압 반응',
                  valueText: '${pen.pressureSensitivity.round()}%',
                  value: pen.pressureSensitivity,
                  min: 0,
                  max: 200,
                  divisions: 40,
                  tooltip: '세게 누를수록 굵어지는 정도. 0%면 일정한 굵기.',
                  onChanged: (v) {
                    pen.pressureSensitivity = v;
                    _refresh();
                  },
                  onChangeEnd: (_) => pen.saveOptions(),
                ),
              if (pen.supportsStabilization)
                HnLabeledSlider(
                  label: '손떨림 보정',
                  valueText: '${(pen.stabilization * 100).round()}%',
                  value: pen.stabilization,
                  min: HnTuning.stabilizationMin,
                  max: HnTuning.stabilizationMax,
                  divisions: HnTuning.stabilizationDivisions,
                  tooltip: stabilizationTooltip,
                  onChanged: (v) {
                    pen.stabilization = v;
                    _refresh();
                  },
                ),
              divider,
              if (pen.supportsHoldShape)
                _SwitchRow(
                  label: '꾹 눌러 도형 만들기',
                  description: '선을 긋고 펜을 잠깐 멈추면 직선·원·사각형으로',
                  value: stows.hnHoldToShape.value,
                  onChanged: (v) {
                    stows.hnHoldToShape.value = v;
                    _refresh();
                  },
                ),
              _SwitchRow(
                label: '손가락 탭으로 실행취소',
                description: '두 손가락 탭 = 실행취소, 세 손가락 탭 = 다시실행',
                value: stows.hnTapGestures.value,
                onChanged: (v) {
                  stows.hnTapGestures.value = v;
                  _refresh();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 펜 그림 줄. 고른 펜은 위로 올라온다.
class _PenRow extends StatelessWidget {
  const new({required this.current, required this.onPick});

  final Pen current;
  final ValueChanged<ToolId> onPick;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        height: 74,
        child: Row(
          mainAxisAlignment: .spaceEvenly,
          crossAxisAlignment: .start,
          children: [
            for (final id in hnPenOrder)
              Tooltip(
                message: hnPenName(id),
                waitDuration: const Duration(milliseconds: 500),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(id),
                  child: Padding(
                    padding: const .only(top: 12, left: 6, right: 6),
                    child: HnPenArt(
                      toolId: id,
                      selected: id == current.toolId,
                      color: id == current.toolId
                          ? current.color
                          : hnPenFor(id).color,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 색상 팔레트 + 더 보기.
class _Palette extends StatelessWidget {
  const new({required this.current, required this.onPick, this.onMore});

  final Color current;
  final ValueChanged<Color> onPick;
  final VoidCallback? onMore;

  static List<Color> get colors {
    final list = <Color>[];
    for (final c in ColorBar.colorPresets) {
      if (list.length >= 13) break;
      if (!list.contains(c.color)) list.add(c.color);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    const size = 30.0;
    return Wrap(
      spacing: 9,
      runSpacing: 10,
      children: [
        for (final color in colors)
          HnPressable(
            scale: 0.85,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onPick(color),
              child: AnimatedContainer(
                duration: HnTuning.pressUpDuration,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(
                    color: color.toARGB32() == current.toARGB32()
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.14),
                    width: color.toARGB32() == current.toARGB32() ? 3 : 1,
                  ),
                ),
              ),
            ),
          ),
        if (onMore != null)
          Tooltip(
            message: '색 더 보기',
            child: HnPressable(
              scale: 0.85,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onMore,
                child: Container(
                  width: size,
                  height: size,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        Colors.red,
                        Colors.yellow,
                        Colors.green,
                        Colors.cyan,
                        Colors.blue,
                        Colors.purple,
                        Colors.red,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LabelRow extends StatelessWidget {
  const new({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurface.withValues(alpha: 0.7),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const new({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label, description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        HnTuning.selectionHaptic();
        onChanged(!value);
      },
      child: Padding(
        padding: const .symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14)),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 0.85,
              child: Switch(
                value: value,
                onChanged: (v) {
                  HnTuning.selectionHaptic();
                  onChanged(v);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 라벨·값이 위에 있고 아래에 얇은 슬라이더가 있는 행.
class HnLabeledSlider extends StatelessWidget {
  const new({
    super.key,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.onChangeEnd,
    this.tooltip,
  });

  final String label;
  final String valueText;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    Widget labelRow = _LabelRow(label: label, value: valueText);
    if (tooltip != null) {
      labelRow = Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: labelRow,
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        labelRow,
        SizedBox(
          height: 38,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.onSurface.withValues(alpha: 0.1),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              thumbShape: const _RingThumb(),
              tickMarkShape: SliderTickMarkShape.noTickMark,
              trackShape: const RoundedRectSliderTrackShape(),
              padding: const .symmetric(horizontal: 11),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: (v) {
                if ((v - value).abs() < 1e-6) return;
                HnTuning.selectionHaptic();
                onChanged(v);
              },
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
      ],
    );
  }
}

/// 흰 원에 테두리가 있는 손잡이(삼성노트 슬라이더처럼).
class _RingThumb extends SliderComponentShape {
  const new();

  static const _radius = 10.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(_radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final r = _radius * (1 + 0.15 * activationAnimation.value);
    canvas.drawCircle(
      center.translate(0, 1),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(center, r, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = sliderTheme.activeTrackColor ?? Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }
}
