import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/hn/hn_tuning.dart';

/// 누르는 동안 살짝 작아졌다가, 손을 떼면 스프링처럼 돌아오는 감싸개.
///
/// 제스처를 가로채지 않는다([Listener]만 쓴다). 그래서 안쪽 버튼의
/// onPressed·툴팁·길게 누르기가 그대로 동작한다.
class HnPressable extends StatefulWidget {
  const new({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = HnTuning.pressScale,
  });

  final Widget child;
  final bool enabled;
  final double scale;

  @override
  State<HnPressable> createState() => _HnPressableState();
}

class _HnPressableState extends State<HnPressable> {
  var _pressed = false;

  void _set(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final pressed = widget.enabled && _pressed;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        // 마우스 오른쪽 버튼 등은 무시
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons != kPrimaryButton) {
          return;
        }
        _set(true);
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: pressed ? widget.scale : 1,
        duration: pressed
            ? HnTuning.pressDownDuration
            : HnTuning.pressUpDuration,
        curve: pressed ? HnTuning.pressDownCurve : HnTuning.pressUpCurve,
        child: widget.child,
      ),
    );
  }
}
