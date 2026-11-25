import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/hn/hn_tuning.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pencil.dart';
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

  /// 획 안정화 정도(0~0.9). perfect_freehand의 streamline과 같다.
  double get stabilization => options.streamline;
  set stabilization(double value) {
    value = value.clamp(HnTuning.stabilizationMin, HnTuning.stabilizationMax);
    value = (value * 100).roundToDouble() / 100;
    options.streamline = value;
    options.smoothing = value.clamp(
      HnTuning.smoothingMin,
      HnTuning.smoothingMax,
    );
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

  void onDragStart(
    Offset position,
    EditorPage page,
    int pageIndex,
    double? pressure,
  ) {
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
    currentStroke?.addPoint(position, pressure);
  }

  Stroke? onDragEnd() {
    final stroke = currentStroke;
    currentStroke = null;
    if (stroke == null) return null;

    return stroke
      ..options.isComplete = true
      ..markPolygonNeedsUpdating();
  }

  /// The default stroke options.
  ///
  /// Note that these are different to the default options in [StrokeOptions]
  /// e.g. [StrokeOptions.defaultSize] for historical reasons
  /// (i.e. [StrokeOptions.toJson] does not include default values.)
  static final defaultOptions = StrokeOptions(size: 5);

  static StrokeOptions get fountainPenOptions => defaultOptions.copyWith();
  static StrokeOptions get ballpointPenOptions => defaultOptions.copyWith();
  static StrokeOptions get shapePenOptions =>
      defaultOptions.copyWith(smoothing: 0, streamline: 0);
  static StrokeOptions get highlighterOptions =>
      defaultOptions.copyWith(size: 50);
  static StrokeOptions get pencilOptions => defaultOptions.copyWith(
    streamline: 0.1,
    start: StrokeEndOptions.start(taperEnabled: true, customTaper: 1),
    end: StrokeEndOptions.end(taperEnabled: true, customTaper: 1),
  );
}
