import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/hn/hn_pressable.dart';
import 'package:saber/components/toolbar/hn_pen_extras.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/data/hn/hn_tuning.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/i18n/strings.g.dart';

/// 펜 설정 카드(Saber HN).
///
/// 툴바 아래에 떠서 열리는 카드로, 브러시 두께·압력 감도·잉크 유량·안정화를
/// 세로로 정리해 보여 준다.
class PenModal<T extends Pen> extends StatefulWidget {
  const new({super.key, required this.getTool, required this.setTool});

  /// Gets the current/last-used tool of type [T],
  /// e.g. [Pen.currentPen] or [Highlighter.currentHighlighter].
  final T Function() getTool;

  /// Sets a pen to be the current pen.
  final void Function(Pen) setTool;

  static const double width = 320;
  // 좌우 여백 20씩 + 테두리 1씩
  static const double _innerWidth = width - 2 * 20 - 2;

  @override
  State<PenModal<T>> createState() => _PenModalState<T>();
}

class _PenModalState<T extends Pen> extends State<PenModal<T>> {
  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final pen = widget.getTool();
    final colorScheme = ColorScheme.of(context);
    final textTheme = TextTheme.of(context);

    final divider = Divider(
      height: 24,
      thickness: 1,
      color: colorScheme.onSurface.withValues(alpha: 0.08),
    );

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: PenModal.width,
        padding: const .fromLTRB(20, 16, 20, 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: colorScheme.onSurface.withValues(alpha: 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            // 제목 + 펜 종류
            Row(
              children: [
                Expanded(
                  child: Text(
                    pen.name,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: .ellipsis,
                  ),
                ),
                if (pen is! Highlighter && pen is! Pencil) ...[
                  _PenSelector(
                    isSelected: Pen.currentPen.icon == Pen.fountainPenIcon,
                    onPressed: () => setState(() {
                      HnTuning.selectionHaptic();
                      widget.setTool(Pen.fountainPen());
                    }),
                    tooltip: t.editor.pens.fountainPen,
                    icon: SvgPicture.asset(
                      'assets/images/scribble_fountain.svg',
                      width: 26,
                      height: 26 / 508 * 374,
                      theme: SvgTheme(
                        currentColor: Pen.currentPen.icon == Pen.fountainPenIcon
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                  _PenSelector(
                    isSelected: Pen.currentPen.icon == Pen.ballpointPenIcon,
                    onPressed: () => setState(() {
                      HnTuning.selectionHaptic();
                      widget.setTool(Pen.ballpointPen());
                    }),
                    tooltip: t.editor.pens.ballpointPen,
                    icon: SvgPicture.asset(
                      'assets/images/scribble_ballpoint.svg',
                      width: 26,
                      height: 26 / 508 * 374,
                      theme: SvgTheme(
                        currentColor:
                            Pen.currentPen.icon == Pen.ballpointPenIcon
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                  _PenSelector(
                    isSelected: Pen.currentPen.icon == ShapePen.shapePenIcon,
                    onPressed: () => setState(() {
                      HnTuning.selectionHaptic();
                      widget.setTool(ShapePen());
                    }),
                    tooltip: t.editor.pens.shapePen,
                    icon: const FaIcon(ShapePen.shapePenIcon, size: 18),
                  ),
                ],
              ],
            ),
            divider,

            // 브러시 두께
            _LabelRow(label: '브러시 두께', value: prettySize(pen.options.size)),
            const SizedBox(height: 2),
            Center(
              child: SizePicker(
                axis: .horizontal,
                pen: pen,
                onChanged: _refresh,
                showLabel: false,
                length:
                    PenModal._innerWidth - 2 * HnTuning.sizeSliderTouchPadding,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                FavoriteSizes(axis: .horizontal, pen: pen, onChanged: _refresh),
                const Spacer(),
                StrokePreview(pen: pen),
              ],
            ),
            const SizedBox(height: 8),

            // 압력 감도
            if (pen.pressureEnabled)
              HnLabeledSlider(
                label: '압력 감도',
                valueText: '${pen.pressureSensitivity.round()}%',
                value: pen.pressureSensitivity,
                min: 0,
                max: 200,
                divisions: 40,
                tooltip: '필압에 따라 굵기가 변하는 정도. 0%면 일정한 굵기.',
                onChanged: (v) {
                  pen.pressureSensitivity = v;
                  _refresh();
                },
                onChangeEnd: (_) => pen.saveOptions(),
              ),

            // 잉크 유량
            HnLabeledSlider(
              label: '잉크 유량',
              valueText: '${(pen.inkFlow * 100).round()}%',
              value: pen.inkFlow,
              min: 0.1,
              max: 1,
              divisions: 18,
              tooltip: '선의 진하기(불투명도). 새로 긋는 선부터 적용됩니다.',
              onChanged: (v) {
                pen.inkFlow = v;
                _refresh();
              },
            ),

            // 안정화
            if (pen.supportsStabilization)
              HnLabeledSlider(
                label: '안정화',
                valueText: '${(pen.stabilization * 100).round()}%',
                value: pen.stabilization.clamp(
                  HnTuning.stabilizationMin,
                  HnTuning.stabilizationMax,
                ),
                min: HnTuning.stabilizationMin,
                max: HnTuning.stabilizationMax,
                divisions: HnTuning.stabilizationDivisions,
                tooltip: stabilizationTooltip,
                onChanged: (v) {
                  pen.stabilization = v;
                  _refresh();
                },
                onChangeEnd: (_) => pen.saveOptions(),
              ),
          ],
        ),
      ),
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
            color: colorScheme.onSurface.withValues(alpha: 0.75),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
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
          height: 40,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.onSurface.withValues(alpha: 0.1),
              thumbColor: colorScheme.primary,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 9,
                elevation: 1,
              ),
              tickMarkShape: SliderTickMarkShape.noTickMark,
              trackShape: const RoundedRectSliderTrackShape(),
              padding: const .symmetric(horizontal: 10),
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

class const _PenSelector({
  required final bool isSelected,
  required final void Function() onPressed,
  required final String tooltip,
  required final Widget icon,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return HnPressable(
      child: IconButton(
        onPressed: onPressed,
        isSelected: isSelected,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          foregroundColor: isSelected
              ? colorScheme.primary
              : colorScheme.onSurface,
          backgroundColor: isSelected
              ? colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          shape: const CircleBorder(),
        ),
        tooltip: tooltip,
        icon: icon,
      ),
    );
  }
}
