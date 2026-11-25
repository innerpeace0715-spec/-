import 'dart:io';

import 'package:collapsible/collapsible.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:keybinder/keybinder.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/hn/hn_popover.dart';
import 'package:saber/components/hn/quick_wheel.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/components/theming/uni_icon.dart';
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
import 'package:saber/data/tools/pencil.dart';
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
    ToolOptions.pencil: LayerLink(),
    ToolOptions.highlighter: LayerLink(),
  };
  final _penCardTapGroup = Object();

  /// 카드에 보여 줄(또는 사라지는 중인) 펜 종류.
  var _cardType = ToolOptions.pen;
  bool get _cardVisible => _penLinks.containsKey(toolOptionsType.value);

  void _onToolOptionsChanged() {
    final type = toolOptionsType.value;
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

  void _openSettingsForCurrentPen() {
    final tool = widget.currentTool;
    final Pen pen = tool is Pen ? tool : Pen.currentPen;
    if (tool != pen) widget.setTool(pen);
    toolOptionsType.value = switch (pen) {
      Highlighter() => .highlighter,
      Pencil() => .pencil,
      _ => .pen,
    };
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
            runSpacing: 8,
            children: [
              TapRegion(
                groupId: _penCardTapGroup,
                child: CompositedTransformTarget(
                  link: _penLinks[ToolOptions.pen]!,
                  child: ToolbarIconButton(
                    tooltip: Pen.currentPen.name,
                    selected: widget.currentTool == Pen.currentPen,
                    enabled: !widget.readOnly,
                    onPressed: () {
                      if (widget.currentTool == Pen.currentPen) {
                        if (toolOptionsType.value == .pen) {
                          toolOptionsType.value = .hide;
                        } else {
                          toolOptionsType.value = .pen;
                        }
                      } else {
                        toolOptionsType.value = .hide;
                        widget.setTool(Pen.currentPen);
                      }
                    },
                    onLongPress: _showQuickWheel,
                    padding: buttonPadding,
                    child: UniIcon(Pen.currentPen.icon, size: 16),
                  ),
                ),
              ),
              TapRegion(
                groupId: _penCardTapGroup,
                child: CompositedTransformTarget(
                  link: _penLinks[ToolOptions.pencil]!,
                  child: ToolbarIconButton(
                    tooltip: t.editor.pens.pencil,
                    selected: widget.currentTool == Pencil.currentPencil,
                    enabled: !widget.readOnly,
                    onPressed: () {
                      if (widget.currentTool == Pencil.currentPencil) {
                        if (toolOptionsType.value == .pencil) {
                          toolOptionsType.value = .hide;
                        } else {
                          toolOptionsType.value = .pencil;
                        }
                      } else {
                        toolOptionsType.value = .hide;
                        widget.setTool(Pencil.currentPencil);
                      }
                    },
                    onLongPress: _showQuickWheel,
                    padding: buttonPadding,
                    child: const FaIcon(Pencil.pencilIcon, size: 16),
                  ),
                ),
              ),
              TapRegion(
                groupId: _penCardTapGroup,
                child: CompositedTransformTarget(
                  link: _penLinks[ToolOptions.highlighter]!,
                  child: ToolbarIconButton(
                    tooltip: t.editor.pens.highlighter,
                    selected:
                        widget.currentTool == Highlighter.currentHighlighter,
                    enabled: !widget.readOnly,
                    onPressed: () {
                      if (widget.currentTool ==
                          Highlighter.currentHighlighter) {
                        if (toolOptionsType.value == .highlighter) {
                          toolOptionsType.value = .hide;
                        } else {
                          toolOptionsType.value = .highlighter;
                        }
                      } else {
                        toolOptionsType.value = .hide;
                        widget.setTool(Highlighter.currentHighlighter);
                      }
                    },
                    onLongPress: _showQuickWheel,
                    padding: buttonPadding,
                    child: const FaIcon(Highlighter.highlighterIcon, size: 16),
                  ),
                ),
              ),
              ValueListenableBuilder(
                valueListenable: showColorOptions,
                builder: (context, showColorOptions, child) {
                  return ToolbarIconButton(
                    tooltip: t.editor.toolbar.toggleColors,
                    selected: showColorOptions,
                    enabled: !widget.readOnly,
                    onPressed: toggleColorOptions,
                    padding: buttonPadding,
                    child: child!,
                  );
                },
                child: currentColor == null
                    ? const Icon(Icons.palette)
                    : Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: currentColor
                              .withInversion(invert)
                              .withValues(alpha: 1),
                          shape: .circle,
                          border: Border.all(
                            color: colorScheme.primary,
                            width: 2,
                          ),
                        ),
                      ),
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
                child: Icon(
                  CupertinoIcons.lasso,
                  shadows: !widget.readOnly
                      ? [
                          BoxShadow(
                            color: colorScheme.primary,
                            blurRadius: 0.1,
                            spreadRadius: 10,
                            blurStyle: BlurStyle.solid,
                          ),
                        ]
                      : null,
                ),
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
                  child: const Icon(Icons.adjust_rounded),
                ),
              ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.toggleEraser,
                selected: widget.currentTool is Eraser,
                enabled: !widget.readOnly,
                onPressed: toggleEraser,
                padding: buttonPadding,
                child: const FaIcon(FontAwesomeIcons.eraser, size: 16),
              ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.photo,
                enabled: !widget.readOnly,
                onPressed: widget.pickPhoto,
                padding: buttonPadding,
                child: const AdaptiveIcon(
                  icon: Icons.photo,
                  cupertinoIcon: CupertinoIcons.photo,
                ),
              ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.text,
                selected: widget.textEditing,
                enabled: !widget.readOnly,
                onPressed: widget.toggleTextEditing,
                padding: buttonPadding,
                child: const AdaptiveIcon(
                  icon: Icons.text_fields,
                  cupertinoIcon: CupertinoIcons.text_cursor,
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
                      child: const Icon(CupertinoIcons.hand_draw),
                    );
                  },
                ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.fullscreen,
                selected: DynamicMaterialApp.isFullscreen,
                enabled: !widget.readOnly,
                onPressed: toggleFullscreen,
                padding: buttonPadding,
                child: AdaptiveIcon(
                  icon: DynamicMaterialApp.isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  cupertinoIcon: DynamicMaterialApp.isFullscreen
                      ? CupertinoIcons.fullscreen_exit
                      : CupertinoIcons.fullscreen,
                ),
              ),
              Wrap(
                direction: isToolbarVertical ? .vertical : .horizontal,
                children: [
                  ToolbarIconButton(
                    tooltip: t.editor.toolbar.undo,
                    enabled: !widget.readOnly && widget.isUndoPossible,
                    onPressed: widget.undo,
                    padding: buttonPadding,
                    child: const AdaptiveIcon(
                      icon: Icons.undo,
                      cupertinoIcon: CupertinoIcons.arrow_uturn_left,
                    ),
                  ),
                  ToolbarIconButton(
                    tooltip: t.editor.toolbar.redo,
                    enabled: !widget.readOnly && widget.isRedoPossible,
                    onPressed: widget.redo,
                    padding: buttonPadding,
                    child: const AdaptiveIcon(
                      icon: Icons.redo,
                      cupertinoIcon: CupertinoIcons.arrow_uturn_right,
                    ),
                  ),
                ],
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
                child: const AdaptiveIcon(
                  icon: Icons.share,
                  cupertinoIcon: CupertinoIcons.share,
                ),
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
    final card = switch (_cardType) {
      .pencil => PenModal(
        getTool: () => Pencil.currentPencil,
        setTool: widget.setTool,
      ),
      .highlighter => PenModal(
        getTool: () => Highlighter.currentHighlighter,
        setTool: widget.setTool,
      ),
      _ => PenModal(getTool: () => Pen.currentPen, setTool: widget.setTool),
    };
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
