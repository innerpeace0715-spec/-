import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/hn/hn_tuning.dart';

/// 두 손가락 탭 = 실행취소, 세 손가락 탭 = 다시실행 (Saber HN).
///
/// 굿노트·노타빌리티에서 가장 많이 쓰는 제스처다. [Listener]만 쓰므로
/// 확대·이동 제스처를 막지 않는다. 손가락이 거의 움직이지 않고 짧게
/// 눌렀다 뗐을 때만 동작한다. S펜이 닿으면 그 동작은 무시한다.
class HnTapGestures extends StatefulWidget {
  const new({
    super.key,
    required this.enabled,
    required this.onUndo,
    required this.onRedo,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onUndo, onRedo;
  final Widget child;

  @override
  State<HnTapGestures> createState() => _HnTapGesturesState();
}

class _HnTapGesturesState extends State<HnTapGestures> {
  final _downPositions = <int, Offset>{};
  Duration _start = Duration.zero;
  var _maxCount = 0;
  var _invalid = false;

  void _onDown(PointerDownEvent e) {
    if (!widget.enabled) return;
    if (e.kind != PointerDeviceKind.touch) {
      _invalid = true;
      return;
    }
    if (_downPositions.isEmpty) {
      _start = e.timeStamp;
      _maxCount = 0;
      _invalid = false;
    }
    _downPositions[e.pointer] = e.position;
    if (_downPositions.length > _maxCount) _maxCount = _downPositions.length;
  }

  void _onMove(PointerMoveEvent e) {
    final start = _downPositions[e.pointer];
    if (start == null) return;
    if ((e.position - start).distance > HnTuning.tapGestureMaxMove) {
      _invalid = true;
    }
  }

  void _onUp(PointerEvent e, {required bool cancelled}) {
    if (_downPositions.remove(e.pointer) == null) return;
    if (cancelled) _invalid = true;
    if (_downPositions.isNotEmpty) return;

    // 이벤트 시각(timeStamp)으로 판단한다.
    final quick = e.timeStamp - _start <= HnTuning.tapGestureMaxDuration;
    if (_invalid || !quick || !widget.enabled) return;
    if (_maxCount == 2) {
      HnTuning.selectionHaptic();
      widget.onUndo();
    } else if (_maxCount == 3) {
      HnTuning.selectionHaptic();
      widget.onRedo();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: (e) => _onUp(e, cancelled: false),
      onPointerCancel: (e) => _onUp(e, cancelled: true),
      child: widget.child,
    );
  }
}
