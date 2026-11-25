import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/tool_id.dart';

/// 펜 고르기 화면·원형 메뉴에서 쓰는 펜 순서.
const hnPenOrder = [
  ToolId.fountainPen,
  ToolId.ballpointPen,
  ToolId.pencil,
  ToolId.highlighter,
  ToolId.shapePen,
];

String hnPenName(ToolId id) => switch (id) {
  .fountainPen => t.editor.pens.fountainPen,
  .ballpointPen => t.editor.pens.ballpointPen,
  .pencil => t.editor.pens.pencil,
  .highlighter => t.editor.pens.highlighter,
  .shapePen => t.editor.pens.shapePen,
  _ => '',
};

/// [id]에 해당하는 펜 객체(이미 쓰던 것이 있으면 그대로).
Pen hnPenFor(ToolId id) => switch (id) {
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
