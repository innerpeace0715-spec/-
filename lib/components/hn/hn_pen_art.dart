import 'package:material_ui/material_ui.dart';
import 'package:saber/data/hn/hn_tuning.dart';
import 'package:sbn/tool_id.dart';

/// 삼성노트처럼 펜 모양을 그린 아이콘(Saber HN).
///
/// 펜촉이 위를 향한 세로 펜이다. [selected]이면 위로 살짝 올라온다.
class HnPenArt extends StatelessWidget {
  const new({
    super.key,
    required this.toolId,
    required this.color,
    this.selected = false,
    this.width = 34,
    this.height = 92,
  });

  final ToolId toolId;
  final Color color;
  final bool selected;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.brightnessOf(context) == .dark;
    return SizedBox(
      width: width,
      height: height,
      child: AnimatedSlide(
        offset: Offset(0, selected ? -0.1 : 0.06),
        duration: HnTuning.popoverEnterDuration,
        curve: HnTuning.pressUpCurve,
        child: CustomPaint(
          painter: _PenArtPainter(
            toolId: toolId,
            ink: color.withAlpha(255),
            body: dark ? const Color(0xFF3A3B3F) : Colors.white,
            outline: dark ? const Color(0xFF55575C) : const Color(0xFFD9DADF),
            metal: dark ? const Color(0xFF9EA2AA) : const Color(0xFFB9BDC6),
            shadow: selected ? 0.22 : 0.12,
          ),
        ),
      ),
    );
  }
}

class _PenArtPainter extends CustomPainter {
  new({
    required this.toolId,
    required this.ink,
    required this.body,
    required this.outline,
    required this.metal,
    required this.shadow,
  });

  final ToolId toolId;
  final Color ink, body, outline, metal;
  final double shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final bodyW = w * 0.56;
    final bodyTop = h * 0.42;

    // 그림자
    final shadowPath = Path()
      ..addRRect(
        RRect.fromLTRBR(
          cx - bodyW / 2,
          bodyTop,
          cx + bodyW / 2,
          h + 8,
          Radius.circular(bodyW / 2.4),
        ),
      );
    canvas.drawShadow(
      shadowPath,
      Colors.black.withValues(alpha: shadow),
      4,
      false,
    );

    final outlinePaint = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    void fillAndOutline(Path path, Color fill) {
      canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(path, outlinePaint);
    }

    // 몸통
    final isHighlighter = toolId == .highlighter;
    final bodyRect = RRect.fromLTRBAndCorners(
      cx - bodyW / 2,
      bodyTop,
      cx + bodyW / 2,
      h + 8,
      topLeft: const Radius.circular(3),
      topRight: const Radius.circular(3),
    );
    fillAndOutline(
      Path()..addRRect(bodyRect),
      isHighlighter ? Color.lerp(body, ink, 0.22)! : body,
    );

    // 색 띠
    final bandH = h * 0.07;
    canvas.drawRect(
      Rect.fromLTWH(cx - bodyW / 2, bodyTop + h * 0.06, bodyW, bandH),
      Paint()..color = ink,
    );

    switch (toolId) {
      case .fountainPen:
        // 어깨
        fillAndOutline(
          Path()
            ..moveTo(cx - bodyW / 2, bodyTop)
            ..lineTo(cx - bodyW * 0.34, bodyTop - h * 0.07)
            ..lineTo(cx + bodyW * 0.34, bodyTop - h * 0.07)
            ..lineTo(cx + bodyW / 2, bodyTop)
            ..close(),
          Color.lerp(body, metal, 0.35)!,
        );
        // 펜촉(금속)
        final nibBase = bodyTop - h * 0.07;
        final nib = Path()
          ..moveTo(cx - bodyW * 0.34, nibBase)
          ..quadraticBezierTo(
            cx - bodyW * 0.36,
            nibBase - h * 0.2,
            cx,
            h * 0.03,
          )
          ..quadraticBezierTo(
            cx + bodyW * 0.36,
            nibBase - h * 0.2,
            cx + bodyW * 0.34,
            nibBase,
          )
          ..close();
        fillAndOutline(nib, metal);
        // 슬릿과 숨구멍
        canvas.drawLine(
          Offset(cx, h * 0.05),
          Offset(cx, nibBase - h * 0.1),
          Paint()
            ..color = outline
            ..strokeWidth = 1,
        );
        canvas.drawCircle(
          Offset(cx, nibBase - h * 0.09),
          w * 0.05,
          Paint()..color = ink,
        );
      case .pencil:
        // 나무 깎인 부분
        fillAndOutline(
          Path()
            ..moveTo(cx - bodyW / 2, bodyTop)
            ..lineTo(cx - bodyW * 0.12, h * 0.12)
            ..lineTo(cx + bodyW * 0.12, h * 0.12)
            ..lineTo(cx + bodyW / 2, bodyTop)
            ..close(),
          const Color(0xFFEBCB9D),
        );
        // 심
        canvas.drawPath(
          Path()
            ..moveTo(cx - bodyW * 0.12, h * 0.12)
            ..lineTo(cx, h * 0.02)
            ..lineTo(cx + bodyW * 0.12, h * 0.12)
            ..close(),
          Paint()..color = ink,
        );
      case .highlighter:
        // 넓은 납작 촉
        fillAndOutline(
          Path()
            ..moveTo(cx - bodyW / 2, bodyTop)
            ..lineTo(cx - bodyW * 0.36, h * 0.2)
            ..lineTo(cx + bodyW * 0.36, h * 0.2)
            ..lineTo(cx + bodyW / 2, bodyTop)
            ..close(),
          Color.lerp(body, metal, 0.2)!,
        );
        canvas.drawPath(
          Path()
            ..moveTo(cx - bodyW * 0.3, h * 0.2)
            ..lineTo(cx - bodyW * 0.3, h * 0.1)
            ..lineTo(cx + bodyW * 0.3, h * 0.05)
            ..lineTo(cx + bodyW * 0.3, h * 0.2)
            ..close(),
          Paint()..color = ink.withValues(alpha: 0.85),
        );
      case .ballpointPen:
      case .shapePen:
      default:
        // 원뿔 촉
        fillAndOutline(
          Path()
            ..moveTo(cx - bodyW / 2, bodyTop)
            ..lineTo(cx - bodyW * 0.12, h * 0.1)
            ..lineTo(cx + bodyW * 0.12, h * 0.1)
            ..lineTo(cx + bodyW / 2, bodyTop)
            ..close(),
          Color.lerp(body, metal, 0.25)!,
        );
        canvas.drawPath(
          Path()
            ..moveTo(cx - bodyW * 0.12, h * 0.1)
            ..lineTo(cx, h * 0.04)
            ..lineTo(cx + bodyW * 0.12, h * 0.1)
            ..close(),
          Paint()..color = ink,
        );
        if (toolId == .shapePen) {
          // 몸통에 작은 도형 표시
          final y = bodyTop + h * 0.25;
          final r = bodyW * 0.22;
          canvas.drawPath(
            Path()
              ..moveTo(cx, y - r)
              ..lineTo(cx + r, y + r * 0.8)
              ..lineTo(cx - r, y + r * 0.8)
              ..close(),
            Paint()
              ..color = ink
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4,
          );
        }
    }
  }

  @override
  bool shouldRepaint(covariant _PenArtPainter old) =>
      old.toolId != toolId ||
      old.ink != ink ||
      old.body != body ||
      old.shadow != shadow;
}
