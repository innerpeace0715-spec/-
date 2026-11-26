import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/hn/hn_tuning.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';

class SizePicker extends StatefulWidget {
  const new({
    super.key,
    required this.axis,
    required this.pen,
    this.onChanged,
    this.length = largeLength,
    this.showLabel = true,
  });

  final Axis axis;
  final Pen pen;

  /// 슬라이더 길이.
  final double length;

  /// 왼쪽에 "Size / 값" 라벨을 보일지.
  final bool showLabel;

  /// 굵기가 바뀔 때마다 불린다(미리보기 갱신용).
  final VoidCallback? onChanged;

  @override
  State<SizePicker> createState() => _SizePickerState();

  static const double smallLength = 25;
  static const double largeLength = HnTuning.sizeSliderLength;

  /// 슬라이더 위치(0~1)를 굵기로 바꾼다.
  ///
  /// [HnTuning.sizeSliderExponent]가 1보다 크면 가는 굵기 쪽이 더 넓게 펼쳐져
  /// 0.1 단위 조절이 쉬워진다.
  static double sizeFromPercent(Pen pen, double percent) {
    percent = clampDouble(percent, 0, 1);
    final curved = math.pow(percent, HnTuning.sizeSliderExponent).toDouble();
    return pen.snapSize(pen.sizeMin + curved * (pen.sizeMax - pen.sizeMin));
  }

  /// [sizeFromPercent]의 역함수.
  static double percentFromSize(Pen pen, double size) {
    final range = pen.sizeMax - pen.sizeMin;
    if (range <= 0) return 0;
    final linear = clampDouble((size - pen.sizeMin) / range, 0, 1);
    return math.pow(linear, 1 / HnTuning.sizeSliderExponent).toDouble();
  }
}

/// Returns a string representation of [num] that:
/// - Has no decimal point if [num] is an integer
/// - Has one decimal point if [num] has a non-zero fractional part
String prettySize(double num) {
  final rounded = num.round();
  if ((num - rounded).abs() < 0.05) return rounded.toString();
  return num.toStringAsFixed(1);
}

class _SizePickerState extends State<SizePicker> {
  void _setState(void Function() fn) {
    setState(fn);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Flex(
      direction: widget.axis,
      mainAxisSize: .min,
      children: [
        if (widget.showLabel) ...[
          SizedBox(
            width: 34,
            child: Column(
              mainAxisSize: .min,
              children: [
                Text(
                  t.editor.penOptions.size,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.8),
                    fontSize: 10,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  prettySize(widget.pen.options.size),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4, height: 4),
        ],
        _SizeSlider(
          pen: widget.pen,
          axis: widget.axis,
          length: widget.length,
          setState: _setState,
        ),
      ],
    );
  }
}

class _SizeSlider extends StatefulWidget {
  const new({
    required this.pen,
    required this.axis,
    required this.length,
    required this.setState,
  });

  final Pen pen;
  final Axis axis;
  final double length;
  final void Function(void Function()) setState;

  @override
  State<_SizeSlider> createState() => _SizeSliderState();
}

class _SizeSliderState extends State<_SizeSlider> {
  static const _pad = HnTuning.sizeSliderTouchPadding;
  var _tapActive = false;
  var _dragActive = false;
  bool get _dragging => _tapActive || _dragActive;

  Pen get pen => widget.pen;

  double _percentOf(Offset localPosition) {
    final along = widget.axis == .horizontal
        ? localPosition.dx
        : localPosition.dy;
    return (along - _pad) / widget.length;
  }

  void _onDrag(Offset localPosition) {
    final newSize = SizePicker.sizeFromPercent(pen, _percentOf(localPosition));
    final oldSize = pen.options.size;
    if (newSize == oldSize) return;

    if (HnTuning.sizeSliderTicks && HnTuning.hapticsEnabled) {
      // 정수 굵기(형광펜은 10 단위)를 지날 때만 짧게 진동
      final tickUnit = pen.sizeMax > 50 ? 10.0 : 1.0;
      if ((newSize / tickUnit).floor() != (oldSize / tickUnit).floor()) {
        HapticFeedback.selectionClick();
      }
    }

    widget.setState(() {
      pen.options.size = newSize;
    });
  }

  void _onTapDown(Offset localPosition) {
    setState(() => _tapActive = true);
    _onDrag(localPosition);
  }

  void _onTapEnd({required bool save}) {
    if (!_tapActive) return;
    setState(() => _tapActive = false);
    if (save) pen.saveOptions();
  }

  void _onDragStart(Offset localPosition) {
    setState(() => _dragActive = true);
    _onDrag(localPosition);
  }

  void _onDragEnd() {
    setState(() => _dragActive = false);
    pen.saveOptions();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final isHorizontal = widget.axis == .horizontal;

    final painter = CustomPaint(
      size: Size(widget.length, SizePicker.smallLength),
      painter: _SizeSliderPainter(
        minSize: pen.sizeMin,
        maxSize: pen.sizeMax,
        percent: SizePicker.percentFromSize(pen, pen.options.size),
        trackColor: colorScheme.onSurface.withValues(alpha: 0.15),
        thumbColor: colorScheme.primary,
        knobColor: colorScheme.surface,
        knobBorderColor: colorScheme.primary,
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _onTapDown(d.localPosition),
      onTapUp: (_) => _onTapEnd(save: true),
      onTapCancel: () => _onTapEnd(save: false),
      onHorizontalDragStart: isHorizontal
          ? (d) => _onDragStart(d.localPosition)
          : null,
      onHorizontalDragUpdate: isHorizontal
          ? (d) => _onDrag(d.localPosition)
          : null,
      onHorizontalDragEnd: isHorizontal ? (_) => _onDragEnd() : null,
      onHorizontalDragCancel: isHorizontal ? _onDragEnd : null,
      onVerticalDragStart: isHorizontal
          ? null
          : (d) => _onDragStart(d.localPosition),
      onVerticalDragUpdate: isHorizontal
          ? null
          : (d) => _onDrag(d.localPosition),
      onVerticalDragEnd: isHorizontal ? null : (_) => _onDragEnd(),
      onVerticalDragCancel: isHorizontal ? null : _onDragEnd,
      child: Padding(
        // 손가락·펜으로 잡기 쉽게 터치 영역을 넓힌다.
        padding: const .all(_pad),
        child: AnimatedScale(
          scale: _dragging ? 1.04 : 1,
          duration: _dragging
              ? HnTuning.pressDownDuration
              : HnTuning.pressUpDuration,
          curve: _dragging ? HnTuning.pressDownCurve : HnTuning.pressUpCurve,
          child: RotatedBox(quarterTurns: isHorizontal ? 0 : 1, child: painter),
        ),
      ),
    );
  }
}

class _SizeSliderPainter extends CustomPainter {
  new({
    required this.minSize,
    required this.maxSize,
    required this.percent,
    required this.trackColor,
    required this.thumbColor,
    required this.knobColor,
    required this.knobBorderColor,
  });

  final double minSize;
  final double maxSize;

  /// 슬라이더 위의 위치(0~1).
  final double percent;
  final Color trackColor;
  final Color thumbColor;
  final Color knobColor;
  final Color knobBorderColor;

  @override
  void paint(Canvas canvas, Size size) {
    // 쐐기 모양 트랙: 왼쪽이 가늘고 오른쪽이 두껍다.
    final trackHeight = size.height * 0.7;
    final top = (size.height - trackHeight) / 2;
    final leftHeight = math.max(2.0, trackHeight * minSize / maxSize);

    Path wedge(double rightX) {
      final rightHeight =
          leftHeight + (trackHeight - leftHeight) * (rightX / size.width);
      return Path()
        ..moveTo(0, size.height / 2 - leftHeight / 2)
        ..lineTo(rightX, size.height / 2 - rightHeight / 2)
        ..lineTo(rightX, size.height / 2 + rightHeight / 2)
        ..lineTo(0, size.height / 2 + leftHeight / 2)
        ..close();
    }

    final trackRect = Rect.fromLTWH(0, top, size.width, trackHeight);
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(trackRect, Radius.circular(trackHeight / 2)),
    );
    canvas.drawPath(wedge(size.width), Paint()..color = trackColor);
    final thumbX = size.width * percent;
    canvas.drawPath(wedge(thumbX), Paint()..color = thumbColor);
    canvas.restore();

    // 손잡이
    final knobRadius = size.height * 0.42;
    final knobX = clampDouble(thumbX, knobRadius, size.width - knobRadius);
    final center = Offset(knobX, size.height / 2);
    canvas.drawCircle(
      center.translate(0, 1),
      knobRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(center, knobRadius, Paint()..color = knobColor);
    canvas.drawCircle(
      center,
      knobRadius,
      Paint()
        ..color = knobBorderColor
        ..style = .stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SizeSliderPainter oldDelegate) {
    return oldDelegate.minSize != minSize ||
        oldDelegate.maxSize != maxSize ||
        oldDelegate.percent != percent ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.thumbColor != thumbColor ||
        oldDelegate.knobColor != knobColor ||
        oldDelegate.knobBorderColor != knobBorderColor;
  }
}
