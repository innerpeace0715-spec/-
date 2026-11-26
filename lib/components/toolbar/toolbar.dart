import 'dart:io';

import 'package:collapsible/collapsible.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:keybinder/keybinder.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/hn/hn_popover.dart';
import 'package:saber/components/hn/hn_pressable.dart';
import 'package:saber/components/hn/quick_wheel.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/components/toolbar/export_bar.dart';
import 'package:saber/components/toolbar/pen_modal.dart';
import 'package:saber/components/toolbar/selection_bar.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/components/toolbar/toolbar_button.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/hn/hn_tuning.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/i18n/strings.g.dart';

class Toolbar extends StatefulWidget {
  const new({
    super.key,
    required this.readOnly,
    required this.setTool,
    required this.currentTool,
    required this.setColor,
    required this.quillFocus,
    required this.textEditing,
    required this.toggleTextEditing,
    required this.undo,
    required this.isUndoPossible,
    required this.redo,
    required this.isRedoPossible,
    required this.toggleFingerDrawing,
    required this.pickPhoto,
    required this.paste,
    required this.duplicateSelection,
    required this.deleteSelection,
    required this.exportAsSba,
    required this.exportAsPdf,
    required this.exportAsPng,
  });

  final bool readOnly;

  final ValueChanged<Tool> setTool;
  final Tool currentTool;
  final ValueChanged<Color> setColor;

  final ValueNotifier<QuillStruct?> quillFocus;
  final bool textEditing;
  final VoidCallback toggleTextEditing;

  final VoidCallback undo;
  final bool isUndoPossible;
  final VoidCallback redo;
  final bool isRedoPossible;

  final VoidCallback toggleFingerDrawing;

  final VoidCallback pickPhoto;

  final VoidCallback paste;

  final VoidCallback duplicateSelection;
  final VoidCallback deleteSelection;

  final Future Function(BuildContext)? exportAsSba;
  final Future Function(BuildContext)? exportAsPdf;
  final Future Function(BuildContext)? exportAsPng;

  @override
  State<Toolbar> createState() => _ToolbarState();

  static const _buttonPaddingHorizontal = EdgeInsets.symmetric(horizontal: 6);
  static const _buttonPaddingVertical = EdgeInsets.symmetric(vertical: 6);
}

class _ToolbarState extends State<Toolbar> {
  ValueNotifier<bool> showExportOptions = ValueNotifier(false);
  ValueNotifier<bool> showColorOptions = ValueNotifier(false);
  ValueNotifier<ToolOptions> toolOptionsType = ValueNotifier(ToolOptions.hide);

  // ── Saber HN: 펜 설정 카드 ──
  final _penCardPortal = OverlayPortalController();
  final _penLinks = {
    ToolOptions.pen: LayerLink(),
    ToolOptions.highlighter: LayerLink(),
  };
  final _penCardTapGroup = Object();

  /// 카드에 보여 줄(또는 사라지는 중인) 펜 종류.
  var _cardType = ToolOptions.pen;
  bool get _cardVisible => _penLinks.containsKey(toolOptionsType.value);

  void _onToolOptionsChanged() {
    final type = toolOptionsType.value;
    if (type == .pencil) {
      toolOptionsType.value = .pen;
      return;
    }
    if (_penLinks.containsKey(type)) {
      _cardType = type;
      if (!_penCardPortal.isShowing) _penCardPortal.show();
    }
    if (mounted) setState(() {});
  }

  // ── Saber HN: 원형 퀵메뉴 ──
  final _wheelPortal = OverlayPortalController();
  final _wheelKey = GlobalKey<HnQuickWheelState>();

  void _syncWheelPortal() {
    if (stows.hnQuickWheelVisible.value) {
      if (!_wheelPortal.isShowing) _wheelPortal.show();
    } else {
      if (_wheelPortal.isShowing) _wheelPortal.hide();
    }
  }

  void _showQuickWheel({bool expand = true}) {
    stows.hnQuickWheelVisible.value = true;
    _syncWheelPortal();
    if (expand) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _wheelKey.currentState?.expand();
      });
    }
  }

  void _toggleQuickWheel() {
    if (stows.hnQuickWheelVisible.value) {
      stows.hnQuickWheelVisible.value = false;
      _syncWheelPortal();
    } else {
      _showQuickWheel();
    }
  }

  /// 펜 버튼이 맡는 도구(만년필·볼펜·연필·도형펜). 형광펜은 따로.
  static bool _isPenLike(Tool tool) => tool is Pen && tool is! Highlighter;
  Pen _lastPenLike = Pen.currentPen;
  Pen get _penLike {
    final tool = widget.currentTool;
    if (_isPenLike(tool)) _lastPenLike = tool as Pen;
    return _lastPenLike;
  }

  /// 펜 설정 창에 보여 줄 펜.
  Pen get _cardPen {
    final tool = widget.currentTool;
    if (tool is Pen) return tool;
    return _cardType == .highlighter
        ? Highlighter.currentHighlighter
        : _penLike;
  }

  void _openSettingsForCurrentPen() {
    final tool = widget.currentTool;
    final Pen pen = tool is Pen ? tool : _penLike;
    if (tool != pen) widget.setTool(pen);
    toolOptionsType.value = pen is Highlighter ? .highlighter : .pen;
  }

  @override
  void initState() {
    _assignKeybindings();

    toolOptionsType.addListener(_onToolOptionsChanged);
    stows.hnQuickWheelVisible.addListener(_syncWheelPortal);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncWheelPortal();
    });

    DynamicMaterialApp.addFullscreenListener(_setState);

    super.initState();
  }

  void _setState() => setState(() {});

  Keybinding? _ctrlF;
  Keybinding? _ctrlE;
  Keybinding? _ctrlC;
  Keybinding? _ctrlShiftS;
  Keybinding? _f11;
  Keybinding? _ctrlV;
  void _assignKeybindings() {
    _ctrlF = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyF),
    ], inclusive: true);
    _ctrlE = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyE),
    ], inclusive: true);
    _ctrlC = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyC),
    ], inclusive: true);
    _ctrlShiftS = Keybinding([
      KeyCode.ctrl,
      KeyCode.shift,
      KeyCode.from(LogicalKeyboardKey.keyS),
    ], inclusive: true);
    _f11 = Keybinding([KeyCode.from(LogicalKeyboardKey.f11)], inclusive: true);
    _ctrlV = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyV),
    ], inclusive: true);

    Keybinder.bind(_ctrlF!, widget.toggleFingerDrawing);
    Keybinder.bind(_ctrlE!, toggleEraser);
    Keybinder.bind(_ctrlC!, toggleColorOptions);
    Keybinder.bind(_ctrlShiftS!, toggleExportBar);
    Keybinder.bind(_f11!, toggleFullscreen);
    Keybinder.bind(_ctrlV!, widget.paste);
  }

  void _removeKeybindings() {
    if (_ctrlF != null) Keybinder.remove(_ctrlF!);
    if (_ctrlE != null) Keybinder.remove(_ctrlE!);
    if (_ctrlC != null) Keybinder.remove(_ctrlC!);
    if (_ctrlShiftS != null) Keybinder.remove(_ctrlShiftS!);
    if (_f11 != null) Keybinder.remove(_f11!);
    if (_ctrlV != null) Keybinder.remove(_ctrlV!);
  }

  void toggleEraser() {
    toolOptionsType.value = .hide;
    widget.setTool(Eraser()); // this toggles eraser
  }

  void toggleColorOptions() {
    showColorOptions.value = !showColorOptions.value;
  }

  void toggleExportBar() {
    showExportOptions.value = !showExportOptions.value;
  }

  void toggleFullscreen() async {
    DynamicMaterialApp.setFullscreen(
      !DynamicMaterialApp.isFullscreen,
      updateSystem: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    final brightness = Theme.brightnessOf(context);
    final invert = stows.editorAutoInvert.value && brightness == .dark;

    final isToolbarVertical =
        stows.editorToolbarAlignment.value == .left ||
        stows.editorToolbarAlignment.value == .right;

    final buttonPadding = isToolbarVertical
        ? Toolbar._buttonPaddingVertical
        : Toolbar._buttonPaddingHorizontal;

    final currentColor = switch (widget.currentTool) {
      final Pen pen => pen.color,
      final Select select => select.getDominantStrokeColor(),
      _ => null,
    };

    if (widget.currentTool == Select.currentSelect) {
      // Enable selection bar only when selection is done
      toolOptionsType.value = Select.currentSelect.doneSelecting
          ? .select
          : .hide;
    }

    final bars = <Widget>[
      ValueListenableBuilder(
        valueListenable: showExportOptions,
        builder: (context, showExportOptions, child) {
          return Collapsible(
            axis: isToolbarVertical ? .horizontal : .vertical,
            maintainState: true,
            duration: HnTuning.panelDuration,
            curve: HnTuning.panelCurve,
            fade: true,
            collapsed: !showExportOptions,
            child: child!,
          );
        },
        child: ExportBar(
          axis: isToolbarVertical ? .vertical : .horizontal,
          toggleExportBar: toggleExportBar,
          exportAsSba: widget.exportAsSba,
          exportAsPdf: widget.exportAsPdf,
          exportAsPng: widget.exportAsPng,
        ),
      ),
      ValueListenableBuilder(
        valueListenable: toolOptionsType,
        builder: (context, toolOptionsType, _) {
          return Collapsible(
            axis: isToolbarVertical ? .horizontal : .vertical,
            maintainState: true,
            duration: HnTuning.panelDuration,
            curve: HnTuning.panelCurve,
            fade: true,
            // 펜 설정은 떠 있는 카드로 보여 주므로 여기서는 접는다.
            collapsed: toolOptionsType != .select,
            child: switch (toolOptionsType) {
              .hide || .pen || .highlighter || .pencil => const SizedBox.square(
                dimension: SizePicker.smallLength,
              ),
              .select => SelectionBar(
                duplicateSelection: widget.duplicateSelection,
                deleteSelection: widget.deleteSelection,
              ),
            },
          );
        },
      ),
      ValueListenableBuilder(
        valueListenable: showColorOptions,
        builder: (context, showColorOptions, child) {
          return Collapsible(
            axis: isToolbarVertical ? .horizontal : .vertical,
            maintainState: true,
            duration: HnTuning.panelDuration,
            curve: HnTuning.panelCurve,
            fade: true,
            collapsed: !showColorOptions,
            child: child!,
          );
        },
        child: ColorBar(
          axis: isToolbarVertical ? .vertical : .horizontal,
          setColor: widget.setColor,
          currentColor: currentColor,
          invert: invert,
        ),
      ),
      ValueListenableBuilder(
        valueListenable: widget.quillFocus,
        builder: (context, quill, _) {
          final baseButtonStyle =
              IconButtonTheme.of(context).style ?? const ButtonStyle();

          final iconTheme = QuillIconTheme(
            iconButtonUnselectedData: IconButtonData(
              style: baseButtonStyle.copyWith(
                backgroundColor: WidgetStateProperty.all(Colors.transparent),
                foregroundColor: WidgetStateProperty.all(colorScheme.primary),
              ),
            ),
            iconButtonSelectedData: IconButtonData(
              style: baseButtonStyle.copyWith(
                backgroundColor: WidgetStateProperty.all(colorScheme.primary),
                foregroundColor: WidgetStateProperty.all(colorScheme.onPrimary),
              ),
            ),
          );
          return Collapsible(
            axis: isToolbarVertical ? .horizontal : .vertical,
            maintainState: false,
            duration: HnTuning.panelDuration,
            curve: HnTuning.panelCurve,
            fade: true,
            collapsed: !widget.textEditing || quill == null,
            child: quill != null
                ? QuillSimpleToolbar(
                    controller: quill.controller,
                    config: QuillSimpleToolbarConfig(
                      axis: isToolbarVertical ? .vertical : .horizontal,
                      buttonOptions: QuillSimpleToolbarButtonOptions(
                        base: QuillToolbarBaseButtonOptions(
                          iconTheme: iconTheme,
                        ),
                      ),
                      // scrollable on Android and iOS
                      multiRowsDisplay: !Platform.isAndroid && !Platform.isIOS,
                      showUndo: false,
                      showRedo: false,
                      showFontSize: false,
                      showFontFamily: false,
                      showClearFormat: false,
                    ),
                  )
                : const SizedBox.shrink(),
          );
        },
      ),
      Center(
        child: Padding(
          padding: const .all(8),
          child: Wrap(
            direction: isToolbarVertical ? .vertical : .horizontal,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 6,
            children: [
              // ── 삼성노트 순서: 텍스트 · 펜 · 형광펜 · 지우개 · 올가미 ──
              ToolbarIconButton(
                tooltip: t.editor.toolbar.text,
                selected: widget.textEditing,
                enabled: !widget.readOnly,
                onPressed: widget.toggleTextEditing,
                padding: buttonPadding,
                child: const Icon(Symbols.keyboard),
              ),
              TapRegion(
                groupId: _penCardTapGroup,
                child: CompositedTransformTarget(
                  link: _penLinks[ToolOptions.pen]!,
                  child: ToolbarIconButton(
                    tooltip: _penLike.name,
                    selected: _isPenLike(widget.currentTool),
                    enabled: !widget.readOnly,
                    onPressed: () {
                      if (_isPenLike(widget.currentTool)) {
                        toolOptionsType.value = toolOptionsType.value == .pen
                            ? .hide
                            : .pen;
                      } else {
                        toolOptionsType.value = .hide;
                        widget.setTool(_penLike);
                      }
                    },
                    onLongPress: _showQuickWheel,
                    padding: buttonPadding,
                    child: Icon(switch (_penLike.toolId) {
                      .pencil => Symbols.stylus_pencil,
                      .ballpointPen => Symbols.ink_pen,
                      .shapePen => Symbols.draw_abstract,
                      _ => Symbols.stylus_fountain_pen,
                    }),
                  ),
                ),
              ),
              TapRegion(
                groupId: _penCardTapGroup,
                child: CompositedTransformTarget(
                  link: _penLinks[ToolOptions.highlighter]!,
                  child: ToolbarIconButton(
                    tooltip: t.editor.pens.highlighter,
                    selected: widget.currentTool is Highlighter,
                    enabled: !widget.readOnly,
                    onPressed: () {
                      if (widget.currentTool is Highlighter) {
                        toolOptionsType.value =
                            toolOptionsType.value == .highlighter
                            ? .hide
                            : .highlighter;
                      } else {
                        toolOptionsType.value = .hide;
                        widget.setTool(Highlighter.currentHighlighter);
                      }
                    },
                    onLongPress: _showQuickWheel,
                    padding: buttonPadding,
                    child: const Icon(Symbols.ink_highlighter),
                  ),
                ),
              ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.toggleEraser,
                selected: widget.currentTool is Eraser,
                enabled: !widget.readOnly,
                onPressed: toggleEraser,
                padding: buttonPadding,
                child: const Icon(Symbols.ink_eraser),
              ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.select,
                selected: widget.currentTool is Select,
                enabled: !widget.readOnly,
                onPressed: () {
                  toolOptionsType.value = .hide;
                  widget.setTool(Select.currentSelect);
                },
                padding: buttonPadding,
                child: const Icon(Symbols.lasso_select),
              ),
              _ToolbarDivider(vertical: isToolbarVertical),

              // ── 빠른 색 3개 ──
              for (var i = 0; i < 3; i++)
                _QuickColorDot(
                  index: i,
                  currentColor: currentColor,
                  invert: invert,
                  enabled: !widget.readOnly && currentColor != null,
                  padding: buttonPadding,
                  onPick: widget.setColor,
                  onOpenPalette: toggleColorOptions,
                ),
              _ToolbarDivider(vertical: isToolbarVertical),

              // ── 실행취소 · 다시실행 ──
              ToolbarIconButton(
                tooltip: t.editor.toolbar.undo,
                enabled: !widget.readOnly && widget.isUndoPossible,
                onPressed: widget.undo,
                padding: buttonPadding,
                child: const Icon(Icons.undo),
              ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.redo,
                enabled: !widget.readOnly && widget.isRedoPossible,
                onPressed: widget.redo,
                padding: buttonPadding,
                child: const Icon(Icons.redo),
              ),
              _ToolbarDivider(vertical: isToolbarVertical),

              // ── 나머지 ──
              ToolbarIconButton(
                tooltip: t.editor.toolbar.photo,
                enabled: !widget.readOnly,
                onPressed: widget.pickPhoto,
                padding: buttonPadding,
                child: const Icon(Symbols.image),
              ),
              ToolbarIconButton(
                tooltip: t.editor.pens.laserPointer,
                selected:
                    widget.currentTool == LaserPointer.currentLaserPointer,
                enabled: true, // even in read-only mode
                onPressed: () {
                  toolOptionsType.value = .hide;
                  widget.setTool(LaserPointer.currentLaserPointer);
                },
                padding: buttonPadding,
                child: const Icon(Symbols.stylus_laser_pointer),
              ),
              ValueListenableBuilder(
                valueListenable: stows.hnQuickWheelVisible,
                builder: (context, visible, _) => ToolbarIconButton(
                  tooltip: '원형 퀵메뉴',
                  selected: visible,
                  enabled: !widget.readOnly,
                  onPressed: _toggleQuickWheel,
                  padding: buttonPadding,
                  child: const Icon(Symbols.adjust),
                ),
              ),
              if (!stows.hideFingerDrawingToggle.value)
                ValueListenableBuilder(
                  valueListenable: stows.editorFingerDrawing,
                  builder: (context, value, child) {
                    return ToolbarIconButton(
                      tooltip: t.editor.toolbar.toggleFingerDrawing,
                      selected: value,
                      enabled: !widget.readOnly,
                      onPressed: widget.toggleFingerDrawing,
                      padding: buttonPadding,
                      child: const Icon(Symbols.pan_tool),
                    );
                  },
                ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.fullscreen,
                selected: DynamicMaterialApp.isFullscreen,
                enabled: !widget.readOnly,
                onPressed: toggleFullscreen,
                padding: buttonPadding,
                child: Icon(
                  DynamicMaterialApp.isFullscreen
                      ? Symbols.fullscreen_exit
                      : Symbols.fullscreen,
                ),
              ),
              ValueListenableBuilder(
                valueListenable: showExportOptions,
                builder: (context, showExportOptions, child) {
                  return ToolbarIconButton(
                    tooltip: t.editor.toolbar.export,
                    selected: showExportOptions,
                    enabled: !widget.readOnly,
                    onPressed: toggleExportBar,
                    padding: buttonPadding,
                    child: child!,
                  );
                },
                child: const Icon(Symbols.share),
              ),
            ],
          ),
        ),
      ),
    ];

    final Widget toolbar = Flex(
      direction: isToolbarVertical ? .horizontal : .vertical,
      textDirection: switch (stows.editorToolbarAlignment.value) {
        .left => .rtl,
        .right => .ltr,
        _ => null,
      },
      verticalDirection: switch (stows.editorToolbarAlignment.value) {
        .down => .down,
        .up => .up,
        _ => .down,
      },
      children: bars,
    );

    return OverlayPortal(
      controller: _wheelPortal,
      overlayChildBuilder: _buildQuickWheel,
      child: OverlayPortal(
        controller: _penCardPortal,
        overlayChildBuilder: _buildPenCard,
        child: toolbar,
      ),
    );
  }

  Widget _buildPenCard(BuildContext context) {
    final link = _penLinks[_cardType]!;
    final (
      target,
      follower,
      offset,
    ) = switch (stows.editorToolbarAlignment.value) {
      .up => (Alignment.bottomLeft, Alignment.topLeft, const Offset(-4, 10)),
      .down => (Alignment.topLeft, Alignment.bottomLeft, const Offset(-4, -10)),
      .left => (Alignment.topRight, Alignment.topLeft, const Offset(10, -4)),
      .right => (Alignment.topLeft, Alignment.topRight, const Offset(-10, -4)),
    };
    final card = PenModal(
      getTool: () => _cardPen,
      setTool: widget.setTool,
      setColor: widget.setColor,
      onMoreColors: () {
        toolOptionsType.value = .hide;
        if (!showColorOptions.value) toggleColorOptions();
      },
    );
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: link,
        targetAnchor: target,
        followerAnchor: follower,
        offset: offset,
        showWhenUnlinked: false,
        child: TapRegion(
          groupId: _penCardTapGroup,
          onTapOutside: (_) {
            if (_cardVisible) toolOptionsType.value = .hide;
          },
          child: HnPopover(
            visible: _cardVisible,
            alignment: follower,
            onDismissed: () {
              if (!_cardVisible) _penCardPortal.hide();
            },
            child: card,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickWheel(BuildContext context) {
    return Positioned.fill(
      child: HnQuickWheel(
        key: _wheelKey,
        currentTool: widget.currentTool,
        setTool: widget.setTool,
        setColor: widget.setColor,
        undo: widget.undo,
        redo: widget.redo,
        canUndo: widget.isUndoPossible,
        canRedo: widget.isRedoPossible,
        openSettings: _openSettingsForCurrentPen,
        onHide: () {
          stows.hnQuickWheelVisible.value = false;
          _syncWheelPortal();
        },
      ),
    );
  }

  @override
  void dispose() {
    DynamicMaterialApp.removeFullscreenListener(_setState);
    DynamicMaterialApp.setFullscreen(false, updateSystem: true);
    toolOptionsType.removeListener(_onToolOptionsChanged);
    stows.hnQuickWheelVisible.removeListener(_syncWheelPortal);

    _removeKeybindings();
    super.dispose();
  }
}

enum ToolOptions { hide, pen, highlighter, pencil, select }

/// 툴바 그룹 사이의 얇은 구분선.
class _ToolbarDivider extends StatelessWidget {
  const new({required this.vertical});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final color = ColorScheme.of(context).onSurface.withValues(alpha: 0.12);
    return Padding(
      padding: vertical
          ? const .symmetric(vertical: 6)
          : const .symmetric(horizontal: 6),
      child: SizedBox(
        width: vertical ? 22 : 1,
        height: vertical ? 1 : 22,
        child: ColoredBox(color: color),
      ),
    );
  }
}

/// 툴바의 빠른 색(삼성노트처럼 3개).
///
/// 누르면 그 색으로, 이미 고른 색을 다시 누르면 전체 색상 막대를 연다.
/// 길게 누르면 지금 색으로 바꿔 저장한다.
class _QuickColorDot extends StatelessWidget {
  const new({
    required this.index,
    required this.currentColor,
    required this.invert,
    required this.enabled,
    required this.padding,
    required this.onPick,
    required this.onOpenPalette,
  });

  final int index;
  final Color? currentColor;
  final bool invert;
  final bool enabled;
  final EdgeInsets padding;
  final ValueChanged<Color> onPick;
  final VoidCallback onOpenPalette;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return ValueListenableBuilder(
      valueListenable: stows.hnQuickColors,
      builder: (context, colors, _) {
        final color = Color(
          (index < colors.length ? int.tryParse(colors[index]) : null) ??
              Colors.black.toARGB32(),
        );
        final selected =
            currentColor != null &&
            currentColor!.withAlpha(255).toARGB32() == color.toARGB32();
        return Padding(
          padding: padding,
          child: Tooltip(
            message: '빠른 색 ${index + 1} · 길게 눌러 지금 색으로 바꾸기',
            waitDuration: const Duration(seconds: 1),
            child: HnPressable(
              enabled: enabled,
              scale: 0.85,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: !enabled
                    ? null
                    : () {
                        HnTuning.selectionHaptic();
                        if (selected) {
                          onOpenPalette();
                        } else {
                          onPick(color);
                        }
                      },
                onLongPress: !enabled || currentColor == null
                    ? null
                    : () {
                        HnTuning.confirmHaptic();
                        final list = List.of(colors);
                        while (list.length < 3) {
                          list.add(Colors.black.toARGB32().toString());
                        }
                        list[index] = currentColor!
                            .withAlpha(255)
                            .toARGB32()
                            .toString();
                        stows.hnQuickColors.value = list;
                      },
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: AnimatedContainer(
                      duration: HnTuning.pressUpDuration,
                      curve: Curves.easeOutCubic,
                      width: selected ? 26 : 24,
                      height: selected ? 26 : 24,
                      decoration: BoxDecoration(
                        color: color.withInversion(invert),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? colorScheme.onSurface.withValues(alpha: 0.8)
                              : colorScheme.onSurface.withValues(alpha: 0.12),
                          width: selected ? 2.5 : 1,
                        ),
                      ),
                      child: selected
                          ? Icon(
                              Icons.expand_more_rounded,
                              size: 16,
                              color: color.computeLuminance() > 0.5
                                  ? Colors.black87
                                  : Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
