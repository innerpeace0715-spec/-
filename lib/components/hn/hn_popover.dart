import 'package:material_ui/material_ui.dart';
import 'package:saber/data/hn/hn_tuning.dart';

/// 떠 있는 카드가 나타나고 사라지는 애니메이션.
///
/// [visible]이 true가 되면 [alignment] 쪽에서 스프링처럼 커지며 나타나고,
/// false가 되면 빠르게 줄어들며 사라진 뒤 [onDismissed]를 부른다.
class HnPopover extends StatefulWidget {
  const new({
    super.key,
    required this.visible,
    required this.child,
    this.alignment = Alignment.topLeft,
    this.onDismissed,
  });

  final bool visible;
  final Widget child;
  final Alignment alignment;
  final VoidCallback? onDismissed;

  @override
  State<HnPopover> createState() => _HnPopoverState();
}

class _HnPopoverState extends State<HnPopover>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: HnTuning.popoverEnterDuration,
    reverseDuration: HnTuning.popoverExitDuration,
  );
  late final _scale = CurvedAnimation(
    parent: _controller,
    curve: HnTuning.popoverEnterCurve,
    reverseCurve: Curves.easeInCubic,
  );
  late final _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.5, curve: Curves.easeOut),
    reverseCurve: Curves.easeIn,
  );

  @override
  void initState() {
    super.initState();
    if (widget.visible) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant HnPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse().whenComplete(() {
        if (mounted && !widget.visible) widget.onDismissed?.call();
      });
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    _fade.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(
          scale: 0.86 + 0.14 * _scale.value,
          alignment: widget.alignment,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
