import 'package:material_ui/material_ui.dart';
import 'package:saber/components/hn/hn_pressable.dart';
import 'package:saber/data/hn/hn_tuning.dart';

class ToolbarIconButton extends StatelessWidget {
  const new({
    super.key,
    this.tooltip,
    this.selected = false,
    this.enabled = true,
    required this.onPressed,
    this.onLongPress,
    required this.padding,
    required this.child,
  });

  final String? tooltip;
  final bool selected;
  final bool enabled;
  final VoidCallback? onPressed;

  /// 길게 누르기(Saber HN: 펜 버튼은 원형 퀵메뉴 열기).
  final VoidCallback? onLongPress;

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    // Saber HN: 삼성노트처럼 평평한 아이콘. 고른 도구는 옅은 회색 바탕.
    final backgroundColor = WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled) ||
          !states.contains(WidgetState.selected)) {
        return Colors.transparent;
      }
      return colorScheme.onSurface.withValues(alpha: 0.09);
    });
    final foregroundColor = WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colorScheme.onSurface.withValues(alpha: 0.25);
      }
      if (states.contains(WidgetState.selected)) {
        return colorScheme.onSurface;
      }
      return colorScheme.onSurface.withValues(alpha: 0.72);
    });
    final buttonStyle = ButtonStyle(
      backgroundColor: backgroundColor,
      iconColor: foregroundColor,
      foregroundColor: foregroundColor,
      overlayColor: WidgetStatePropertyAll(
        colorScheme.onSurface.withValues(alpha: 0.06),
      ),
      iconSize: const WidgetStatePropertyAll(23),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(7)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    final onPressed = this.onPressed;
    final isEnabled = enabled && onPressed != null;
    return Padding(
      padding: padding,
      child: HnPressable(
        enabled: isEnabled,
        child: IconButton.filled(
          style: buttonStyle,
          onPressed: isEnabled
              ? () {
                  HnTuning.selectionHaptic();
                  onPressed();
                }
              : null,
          onLongPress: isEnabled && onLongPress != null
              ? () {
                  HnTuning.confirmHaptic();
                  onLongPress!();
                }
              : null,
          tooltip: tooltip,
          isSelected: selected,
          icon: AnimatedSwitcher(
            duration: HnTuning.pressUpDuration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: Tween(begin: 0.85, end: 1.0).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: KeyedSubtree(key: ValueKey(selected), child: child),
          ),
        ),
      ),
    );
  }
}
