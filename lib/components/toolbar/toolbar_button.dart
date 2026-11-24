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
    required this.padding,
    required this.child,
  });

  final String? tooltip;
  final bool selected;
  final bool enabled;
  final VoidCallback? onPressed;

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final backgroundColor = WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled) ||
          !states.contains(WidgetState.selected)) {
        return Colors.transparent;
      }
      return colorScheme.primary;
    });
    final foregroundColor = WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colorScheme.onSurface.withValues(alpha: 0.4);
      }
      if (states.contains(WidgetState.selected)) {
        return colorScheme.onPrimary;
      }
      return colorScheme.primary;
    });
    final buttonStyle = ButtonStyle(
      backgroundColor: backgroundColor,
      iconColor: foregroundColor,
      foregroundColor: foregroundColor,
      iconSize: const WidgetStatePropertyAll(20),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
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
