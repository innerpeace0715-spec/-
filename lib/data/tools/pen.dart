import 'dart:async';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/hn/hn_tuning.dart';
import 'package:saber/data/hn/one_euro.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/tool_id.dart';

class Pen extends Tool {
  @protected
  @visibleForTesting
  new({
    required this.name,
    required this.sizeMin,
    required this.sizeMax,
    required this.sizeStep,
    required this.icon,
    required this.options,
    required this.pressureEnabled,
    required this.color,
    required this.toolId,
  });

  new fountainPen()
    : name = t.editor.pens.fountainPen,
      sizeMin = 0.5,
      sizeMax = 25,
      sizeStep = 0.1,
      icon = fountainPenIcon,
      options = stows.lastFountainPenOptions.value,
      pressureEnabled = true,
      color = Color(stows.lastFountainPenColor.value),
      toolId = .fountainPen;

  new ballpointPen()
    : name = t.editor.pens.ballpointPen,
      sizeMin = 0.5,
      sizeMax = 25,
      sizeStep = 0.1,
      icon = ballpointPenIcon,
      options = stows.lastBallpointPenOptions.value,
      pressureEnabled = false,
      color = Color(stows.lastBallpointPenColor.value),
      toolId = .ballpointPen;

  final String name;
  final double sizeMin, sizeMax, sizeStep;
  late final int sizeStepsBetweenMinAndMax = ((sizeMax - sizeMin) / sizeStep)
      .round();
  final Object icon;

  @override
  final ToolId toolId;

  static const fountainPenIcon = FontAwesomeIcons.penFancy;
  static const ballpointPenIcon = FontAwesomeIcons.pen;

  static Stroke? currentStroke;
  Color color;
  bool pressureEnabled;
  StrokeOptions options;

  static var _currentPen = Pen.fountainPen();
  static Pen get currentPen => _currentPen;
  static set currentPen(Pen currentPen) {
    assert(
      currentPen is! Highlighter,
      'Use Highlighter.currentHighlighter instead',
    );
    assert(currentPen is! Pencil, 'Use Pencil.currentPencil instead');
    _currentPen = currentPen;
  }

  /// 획 안정화를 지원하는지. 도형펜은 도형 인식 때문에 항상 0이다.
  bool get supportsStabilization => toolId != .shapePen;

  /// 획 안정화 세기(0~1). 펜마다 따로 저장된다.
  ///
  /// 입력 점에 속도 적응형 필터([OneEuroFilter2D])를 건다. 원본처럼 그리기
  /// 단계에서 고정 세기로 평균 내지 않으므로, 빠르게 쓸 때 선이 늦게
  /// 따라오는 느낌이 적다.
  double get stabilization => stows.hnStabilizationFor(toolId)?.value ?? 0;
  set stabilization(double value) {
    value = ((value.clamp(0.0, 1.0) * 100).roundToDouble()) / 100;
    stows.hnStabilizationFor(toolId)?.value = value;
  }

  /// 압력 감도(%). 100%가 원본 기본값(thinning 0.5)이다. 범위 0~200%.
  double get pressureSensitivity => options.thinning * 200;
  set pressureSensitivity(double percent) {
    percent = percent.clamp(0, 200).roundToDouble();
    options.thinning = percent / 200;
  }

  /// 잉크 유량(0.1~1). 선의 불투명도에 곱해진다.
  double get inkFlow => stows.hnInkFlowFor(toolId)?.value ?? 1;
  set inkFlow(double value) {
    value = ((value.clamp(0.1, 1) * 100).roundToDouble()) / 100;
    stows.hnInkFlowFor(toolId)?.value = value;
  }

  /// 실제 획에 쓰일 색(잉크 유량 반영).
  Color get strokeColor {
    final flow = inkFlow;
    if (flow >= 1) return color;
    return color.withValues(alpha: color.a * flow);
  }

  /// [sizeStep] 단위로 반올림한 굵기를 [sizeMin]~[sizeMax] 안에서 돌려준다.
  ///
  /// 부동소수점 오차(예: 5.700000000000001)가 노트 파일에 남지 않도록
  /// 소수 첫째 자리 기준으로 정리한다.
  double snapSize(double size) {
    final steps = ((size - sizeMin) / sizeStep).round();
    final snapped = sizeMin + steps * sizeStep;
    final rounded = (snapped * 10).roundToDouble() / 10;
    return rounded.clamp(sizeMin, sizeMax);
  }

  /// 현재 펜 설정을 바로 저장한다.
  ///
  /// 원본은 편집기를 닫을 때만 저장해서, 앱이 강제 종료되면 설정이 사라졌다.
  void saveOptions() {
    final stow = switch (toolId) {
      .fountainPen => stows.lastFountainPenOptions,
      .ballpointPen => stows.lastBallpointPenOptions,
      .highlighter => stows.lastHighlighterOptions,
      .pencil => stows.lastPencilOptions,
      .shapePen => stows.lastShapePenOptions,
      _ => null,
    };
    if (stow == null || !identical(stow.value, options)) return;
    stow.notifyListeners();
  }

  // ── 입력 안정화 ──
  static OneEuroFilter2D? _filter;
  static final _clock = Stopwatch();
  static Duration _lastTime = Duration.zero;
  static Offset? _lastRaw;

  // ── 꾹 누르면 도형으로(draw and hold) ──
  /// 도형 인식 대기 중인지/인식되었는지 알리는 알림. 편집기가 다시 그린다.
  static final holdShapeNotifier = ValueNotifier<RecognizedUnistroke?>(null);
  static Timer? _holdTimer;
  static Offset? _holdAnchor;
  static EditorPage? _page;

  static void _setHoldShape(RecognizedUnistroke? shape) {
    if (holdShapeNotifier.value == shape) return;
    holdShapeNotifier.value = shape;
    // 캔버스는 ShapePen.detectedShape를 미리보기로 그린다.
    ShapePen.detectedShape = shape;
    _page?.redrawStrokes();
  }

  /// 이 펜이 꾹 눌러 도형 만들기를 지원하는지(도형펜은 따로 처리).
  bool get supportsHoldShape => toolId != .shapePen && toolId != .highlighter;

  static void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdAnchor = null;
    if (holdShapeNotifier.value != null) _setHoldShape(null);
  }

  void _trackHold(Offset position) {
    if (!supportsHoldShape || !stows.hnHoldToShape.value) return;
    final anchor = _holdAnchor;
    final detected = holdShapeNotifier.value != null;
    final tolerance = detected
        ? HnTuning.holdShapeCancelDistance
        : HnTuning.holdShapeStillDistance;
    if (anchor != null && (position - anchor).distance <= tolerance) return;

    // 움직였으므로 다시 기다린다(이미 인식됐으면 취소).
    if (detected) _setHoldShape(null);
    _holdAnchor = position;
    _holdTimer?.cancel();
    _holdTimer = Timer(HnTuning.holdShapeDelay, () {
      final stroke = currentStroke;
      if (stroke == null || stroke.length < 4) return;
      final shape = stroke.detectShape();
      if (shape == null || shape.name == null) return;
      HnTuning.confirmHaptic();
      _setHoldShape(shape);
    });
  }

  void onDragStart(
    Offset position,
    EditorPage page,
    int pageIndex,
    double? pressure,
  ) {
    _filter = supportsStabilization ? oneEuroForStrength(stabilization) : null;
    _clock
      ..reset()
      ..start();
    _lastTime = Duration.zero;
    _lastRaw = null;
    _cancelHold();
    _page = page;

    currentStroke = Stroke(
      color: strokeColor,
      pressureEnabled: pressureEnabled,
      options: options.copyWith(isComplete: false),
      pageIndex: pageIndex,
      page: page,
      toolId: toolId,
    );
    onDragUpdate(position, pressure);
  }

  void onDragUpdate(Offset position, double? pressure) {
    _lastRaw = position;
    final filter = _filter;
    if (filter != null) {
      final now = _clock.elapsed;
      final dt = (now - _lastTime).inMicroseconds / 1e6;
      _lastTime = now;
      position = filter.filter(position, dt > 0 ? dt : 1 / 240);
    }
    currentStroke?.addPoint(position, pressure);
    _trackHold(_lastRaw!);
  }

  Stroke? onDragEnd() {
    final stroke = currentStroke;
    currentStroke = null;
    final heldShape = holdShapeNotifier.value;
    _cancelHold();
    if (stroke == null) return null;

    // 필터 때문에 끝점이 펜촉보다 약간 뒤에 있으면 실제 끝점까지 이어 준다.
    final raw = _lastRaw;
    if (_filter != null && raw != null && !stroke.isEmpty) {
      final last = stroke.lastPosition;
      if (last != null && (raw - last).distance > 0.3) {
        stroke.addPoint(raw);
      }
    }
    _filter = null;
    _lastRaw = null;

    stroke
      ..options.isComplete = true
      ..markPolygonNeedsUpdating();

    if (heldShape != null) {
      return ShapePen.applyShape(stroke, heldShape) ?? stroke;
    }
    return stroke;
  }

  /// The default stroke options.
  ///
  /// Note that these are different to the default options in [StrokeOptions]
  /// e.g. [StrokeOptions.defaultSize] for historical reasons
  /// (i.e. [StrokeOptions.toJson] does not include default values.)
  static final defaultOptions = StrokeOptions(size: 5);

  /// Saber HN: 손떨림은 입력 필터가 잡으므로 그리기 단계의 지연(streamline)은
  /// 낮춘다. 기본값 0.5 대신 [HnTuning.renderStreamline].
  static StrokeOptions get fountainPenOptions =>
      defaultOptions.copyWith(streamline: HnTuning.renderStreamline);
  static StrokeOptions get ballpointPenOptions =>
      defaultOptions.copyWith(streamline: HnTuning.renderStreamline);
  static StrokeOptions get shapePenOptions =>
      defaultOptions.copyWith(smoothing: 0, streamline: 0);
  static StrokeOptions get highlighterOptions =>
      defaultOptions.copyWith(size: 50, streamline: HnTuning.renderStreamline);
  static StrokeOptions get pencilOptions => defaultOptions.copyWith(
    streamline: 0.1,
    start: StrokeEndOptions.start(taperEnabled: true, customTaper: 1),
    end: StrokeEndOptions.end(taperEnabled: true, customTaper: 1),
  );
}
