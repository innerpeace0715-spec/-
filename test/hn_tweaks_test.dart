import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/hn/hn_popover.dart';
import 'package:saber/components/hn/hn_tap_gestures.dart';
import 'package:saber/components/hn/quick_wheel.dart';
import 'package:saber/components/toolbar/hn_pen_extras.dart';
import 'package:saber/components/toolbar/pen_modal.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/hn/hn_tuning.dart';
import 'package:saber/data/hn/one_euro.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:sbn/tool_id.dart';

void main() {
  setUpAll(FlavorConfig.setup);

  group('Saber HN: size', () {
    test('pens use 0.1 steps without float noise', () {
      final pen = Pen.fountainPen();
      expect(pen.sizeStep, 0.1);
      for (var i = 0; i <= 1000; i++) {
        final size = SizePicker.sizeFromPercent(pen, i / 1000);
        expect(size, inInclusiveRange(pen.sizeMin, pen.sizeMax));
        // 소수 첫째 자리까지만 있어야 한다
        expect((size * 10).roundToDouble() / 10, size);
      }
      expect(SizePicker.sizeFromPercent(pen, 0), pen.sizeMin);
      expect(SizePicker.sizeFromPercent(pen, 1), pen.sizeMax);
      expect(SizePicker.sizeFromPercent(pen, -1), pen.sizeMin);
      expect(SizePicker.sizeFromPercent(pen, 2), pen.sizeMax);
    });

    test('percent <-> size round trip', () {
      for (final pen in [Pen.ballpointPen(), Pencil(), Highlighter()]) {
        for (final size in [pen.sizeMin, 2.0, 5.0, 12.3, pen.sizeMax]) {
          final snapped = pen.snapSize(size);
          final p = SizePicker.percentFromSize(pen, snapped);
          expect(SizePicker.sizeFromPercent(pen, p), closeTo(snapped, 1e-9));
        }
      }
    });

    test('thin sizes get more slider room', () {
      final pen = Pen.fountainPen();
      // 0.5~5 구간이 슬라이더의 40% 이상을 차지해야 한다(원본은 약 17%).
      expect(SizePicker.percentFromSize(pen, 5), greaterThan(0.4));
    });

    test('snapSize clamps and rounds', () {
      final pen = Pen.fountainPen();
      expect(pen.snapSize(5.7000000000000002), 5.7);
      expect(pen.snapSize(0), pen.sizeMin);
      expect(pen.snapSize(999), pen.sizeMax);
      final hl = Highlighter();
      expect(hl.snapSize(33.3), 33);
    });

    test('old saved sizes stay inside the new ranges', () {
      // 원본 범위: 펜 1~25, 연필 1~15, 형광펜 10~100
      expect(Pen.fountainPen().sizeMin, lessThanOrEqualTo(1));
      expect(Pencil().sizeMin, lessThanOrEqualTo(1));
      expect(Highlighter().sizeMin, lessThanOrEqualTo(10));
      expect(Highlighter().sizeMax, 100);
    });
  });

  group('Saber HN: stabilization (input filter)', () {
    test('strength is stored per pen and clamped', () {
      final pen = Pen.fountainPen();
      pen.stabilization = 0.7;
      expect(pen.stabilization, 0.7);
      expect(Pencil().stabilization, isNot(0.7));
      pen.stabilization = 5;
      expect(pen.stabilization, 1);
      pen.stabilization = -1;
      expect(pen.stabilization, 0);
      pen.stabilization = 0.35;
    });

    test('0 means no filter', () {
      expect(oneEuroForStrength(0), isNull);
      expect(oneEuroForStrength(0.3), isNotNull);
    });

    // 천천히 그은 직선에 손떨림(±1.5px)을 섞었을 때
    double jitterAfter(double strength) {
      final f = oneEuroForStrength(strength);
      var sum = 0.0;
      for (var i = 0; i < 240; i++) {
        final noise = ((i * 7919) % 13 - 6) / 4; // -1.5 ~ 1.5
        var p = Offset(i * 0.25, 100 + noise); // 60px/s @240Hz
        if (f != null) p = f.filter(p, 1 / 240);
        if (i > 20) sum += (p.dy - 100).abs();
      }
      return sum / 219;
    }

    test('removes slow hand jitter, more with higher strength', () {
      final none = jitterAfter(0);
      final mid = jitterAfter(0.35);
      final high = jitterAfter(0.9);
      expect(mid, lessThan(none * 0.7));
      expect(high, lessThan(mid));
    });

    test('fast strokes barely lag', () {
      final f = oneEuroForStrength(0.35)!;
      Offset p = .zero;
      // 1500px/s 직선
      for (var i = 0; i < 60; i++) {
        p = f.filter(Offset(i * 6.25, 0), 1 / 240);
      }
      expect(59 * 6.25 - p.dx, lessThan(6));
    });

    test('render lag is lower than upstream for new strokes only', () {
      expect(Pen.fountainPenOptions.streamline, HnTuning.renderStreamline);
      expect(HnTuning.renderStreamline, lessThan(0.5));
      // 옛 노트(sl 없음)는 원본 기본값 0.5로 그대로 그려진다
      expect(StrokeOptions.fromJson({}).streamline, 0.5);
      expect(Pen.fountainPenOptions.toJson()['sl'], HnTuning.renderStreamline);
      expect(Pen.pencilOptions.streamline, 0.1);
    });

    test('shape pen does not support stabilization or hold-to-shape', () {
      expect(ShapePen().supportsStabilization, isFalse);
      expect(ShapePen().supportsHoldShape, isFalse);
      expect(Pen.fountainPen().supportsStabilization, isTrue);
      expect(Pen.fountainPen().supportsHoldShape, isTrue);
    });
  });

  group('Saber HN: hold to shape', () {
    testWidgets('pausing at the end of a circle turns it into a circle', (
      tester,
    ) async {
      stows.hnHoldToShape.value = true;
      final pen = Pen.ballpointPen();
      pen.stabilization = 0;
      final page = EditorPage();
      const c = Offset(200, 200);
      Offset at(double t) =>
          c + Offset(math.cos(t * 2 * math.pi), math.sin(t * 2 * math.pi)) * 80;
      pen.onDragStart(at(0), page, 0, null);
      for (var i = 1; i <= 64; i++) {
        pen.onDragUpdate(at(i / 64), null);
      }
      expect(Pen.holdShapeNotifier.value, isNull);
      // 펜을 멈추고 기다린다
      await tester.pump(
        HnTuning.holdShapeDelay + const Duration(milliseconds: 50),
      );
      expect(Pen.holdShapeNotifier.value, isNotNull);
      final stroke = pen.onDragEnd();
      expect(stroke, isA<CircleStroke>());
      expect(Pen.holdShapeNotifier.value, isNull);
      pen.stabilization = 0.35;
    });

    testWidgets('moving again cancels; disabled setting does nothing', (
      tester,
    ) async {
      final pen = Pen.ballpointPen();
      pen.stabilization = 0;
      final page = EditorPage();
      stows.hnHoldToShape.value = true;
      pen.onDragStart(.zero, page, 0, null);
      // 인식기는 64점 이상이 필요하다(실제 S펜은 초당 240점 정도)
      for (var i = 1; i <= 80; i++) {
        pen.onDragUpdate(Offset(i * 2.5, math.sin(i) * 1.5), null);
      }
      await tester.pump(
        HnTuning.holdShapeDelay + const Duration(milliseconds: 50),
      );
      expect(Pen.holdShapeNotifier.value, isNotNull); // 직선
      pen.onDragUpdate(const Offset(200, 80), null);
      expect(Pen.holdShapeNotifier.value, isNull);
      final s1 = pen.onDragEnd()!;
      expect(s1, isNot(isA<CircleStroke>()));

      stows.hnHoldToShape.value = false;
      pen.onDragStart(.zero, page, 0, null);
      for (var i = 1; i <= 20; i++) {
        pen.onDragUpdate(Offset(i * 10, 0), null);
      }
      await tester.pump(HnTuning.holdShapeDelay * 2);
      expect(Pen.holdShapeNotifier.value, isNull);
      pen.onDragEnd();
      stows.hnHoldToShape.value = true;
      pen.stabilization = 0.35;
    });
  });

  group('Saber HN: finger tap gestures', () {
    Future<(int, int)> run(
      WidgetTester tester,
      Future<void> Function(Offset center) gesture,
    ) async {
      var undo = 0, redo = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HnTapGestures(
            enabled: true,
            onUndo: () => undo++,
            onRedo: () => redo++,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await gesture(const Offset(300, 300));
      await tester.pump();
      return (undo, redo);
    }

    Future<void> tapWith(
      WidgetTester tester,
      int fingers, {
      Offset move = .zero,
    }) async {
      final gs = <TestGesture>[];
      for (var i = 0; i < fingers; i++) {
        gs.add(
          await tester.startGesture(
            Offset(300.0 + i * 60, 300),
            pointer: 10 + i,
          ),
        );
      }
      await tester.pump(const Duration(milliseconds: 60));
      if (move != .zero) {
        for (final g in gs) {
          await g.moveBy(move);
        }
      }
      for (final g in gs) {
        await g.up();
      }
    }

    testWidgets('two fingers undo, three redo', (tester) async {
      expect(await run(tester, (_) => tapWith(tester, 2)), (1, 0));
      expect(await run(tester, (_) => tapWith(tester, 3)), (0, 1));
    });

    testWidgets('one finger, pinch/drag, or slow press does nothing', (
      tester,
    ) async {
      expect(await run(tester, (_) => tapWith(tester, 1)), (0, 0));
      expect(
        await run(tester, (_) => tapWith(tester, 2, move: const Offset(40, 0))),
        (0, 0),
      );
      expect(
        await run(tester, (_) async {
          // 0.6초 동안 누르고 있었던 두 손가락(이벤트 시각으로 판단)
          final a = TestPointer(1);
          final b = TestPointer(2);
          await tester.sendEventToBinding(
            a.down(const Offset(300, 300), timeStamp: Duration.zero),
          );
          await tester.sendEventToBinding(
            b.down(const Offset(360, 300), timeStamp: Duration.zero),
          );
          await tester.sendEventToBinding(
            a.up(timeStamp: const Duration(milliseconds: 600)),
          );
          await tester.sendEventToBinding(
            b.up(timeStamp: const Duration(milliseconds: 600)),
          );
        }),
        (0, 0),
      );
    });
  });

  group('Saber HN: SpringCurve', () {
    test('starts at 0 and ends at 1', () {
      for (final z in [0.5, 0.85, 1.0, 1.5]) {
        final c = SpringCurve(dampingRatio: z);
        expect(c.transform(0), 0);
        expect(c.transform(1), 1);
        // 중간에도 크게 튀지 않아야 한다
        for (var i = 1; i < 100; i++) {
          expect(c.transform(i / 100), inInclusiveRange(-0.01, 1.2));
        }
      }
    });
  });

  group('Saber HN: pen settings card', () {
    Future<void> pump(
      WidgetTester tester,
      Pen pen, {
      double height = 900,
    }) async {
      tester.view.physicalSize = Size(1000, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PenModal(getTool: () => pen, setTool: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder sliderLabeled(String label) => find.descendant(
      of: find.widgetWithText(HnLabeledSlider, label),
      matching: find.byType(Slider),
    );

    testWidgets('fountain pen shows all rows without overflow', (tester) async {
      final pen = Pen.fountainPen();
      pen.options = pen.options.copyWith();
      Pen.currentPen = pen;
      await pump(tester, pen);
      expect(tester.takeException(), isNull);
      expect(find.text('굵기'), findsOneWidget);
      expect(find.text('필압 반응'), findsOneWidget);
      expect(find.text('투명도'), findsOneWidget);
      expect(find.text('손떨림 보정'), findsOneWidget);
      expect(find.byType(SizePicker), findsOneWidget);
      expect(find.byType(StrokePreview), findsOneWidget);
      expect(find.byType(FavoriteSizes), findsOneWidget);
    });

    testWidgets('ballpoint hides pressure; shape pen hides stabilization', (
      tester,
    ) async {
      final ballpoint = Pen.ballpointPen();
      Pen.currentPen = ballpoint;
      await pump(tester, ballpoint);
      expect(find.text('필압 반응'), findsNothing);
      expect(find.text('손떨림 보정'), findsOneWidget);

      final shape = ShapePen();
      Pen.currentPen = shape;
      await pump(tester, shape);
      expect(find.text('손떨림 보정'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the size slider jumps to that size', (tester) async {
      final pen = Pen.fountainPen();
      pen.options = pen.options.copyWith(size: 5);
      Pen.currentPen = pen;
      await pump(tester, pen);

      final rect = tester.getRect(find.byType(SizePicker));
      await tester.tapAt(Offset(rect.right - 14, rect.center.dy));
      await tester.pumpAndSettle();
      expect(pen.options.size, greaterThan(20));
      expect((pen.options.size * 10).roundToDouble() / 10, pen.options.size);
    });

    testWidgets('favorite size: tap applies, long press saves', (tester) async {
      final pen = Pen.fountainPen();
      pen.options = pen.options.copyWith(size: 7.3);
      Pen.currentPen = pen;
      await pump(tester, pen);

      final favs = find.descendant(
        of: find.byType(FavoriteSizes),
        matching: find.byType(GestureDetector),
      );
      expect(favs, findsNWidgets(3));
      await tester.longPress(favs.at(0));
      await tester.pumpAndSettle();
      await tester.tap(favs.at(1));
      await tester.pumpAndSettle();
      expect(pen.options.size, isNot(7.3));
      await tester.tap(favs.at(0));
      await tester.pumpAndSettle();
      expect(pen.options.size, 7.3);
    });

    testWidgets('sliders change stabilization, pressure and opacity', (
      tester,
    ) async {
      final pen = Pen.fountainPen();
      pen.options = pen.options.copyWith();
      Pen.currentPen = pen;
      await pump(tester, pen);

      Future<void> tapEnd(String label, {required bool right}) async {
        final r = tester.getRect(sliderLabeled(label));
        await tester.tapAt(
          Offset(right ? r.right - 12 : r.left + 12, r.center.dy),
        );
        await tester.pumpAndSettle();
      }

      await tapEnd('손떨림 보정', right: true);
      expect(pen.stabilization, 1);
      await tapEnd('손떨림 보정', right: false);
      expect(pen.stabilization, 0);
      pen.stabilization = 0.35;

      await tapEnd('필압 반응', right: false);
      expect(pen.options.thinning, lessThan(0.05));
      await tapEnd('필압 반응', right: true);
      expect(pen.options.thinning, greaterThan(0.95));

      await tapEnd('투명도', right: true);
      expect(pen.inkFlow, lessThan(0.15));
      expect(pen.strokeColor.a, closeTo(pen.color.a * pen.inkFlow, 0.01));
      await tapEnd('투명도', right: false);
      expect(pen.inkFlow, 1);
      expect(pen.strokeColor, pen.color);
    });
  });

  group('Saber HN: quick wheel', () {
    Future<GlobalKey<HnQuickWheelState>> pump(
      WidgetTester tester, {
      required Tool Function() tool,
      required ValueChanged<Tool> setTool,
      ValueChanged<Color>? setColor,
      VoidCallback? undo,
    }) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey<HnQuickWheelState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => HnQuickWheel(
                key: key,
                currentTool: tool(),
                setTool: (t) {
                  setTool(t);
                  setState(() {});
                },
                setColor: (c) {
                  setColor?.call(c);
                  setState(() {});
                },
                undo: undo ?? () {},
                redo: () {},
                canUndo: true,
                canRedo: false,
                openSettings: () {},
                onHide: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return key;
    }

    testWidgets('mini bubble expands; outside tap collapses', (tester) async {
      Tool current = Pen.fountainPen();
      final key = await pump(
        tester,
        tool: () => current,
        setTool: (t) => current = t,
      );
      expect(find.byIcon(Icons.undo_rounded).hitTestable(), findsNothing);
      key.currentState!.expand();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.undo_rounded).hitTestable(), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.undo_rounded).hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('undo button and swipe to switch pens', (tester) async {
      Tool current = Pen.fountainPen();
      Pen.currentPen = current as Pen;
      var undone = 0;
      final key = await pump(
        tester,
        tool: () => current,
        setTool: (t) => current = t,
        undo: () => undone++,
      );
      key.currentState!.expand();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.undo_rounded));
      await tester.pumpAndSettle();
      expect(undone, 1);

      // 가운데를 왼쪽으로 두 칸 밀면 만년필 -> 볼펜 -> 연필
      final center = tester.getCenter(find.byIcon(Icons.swap_horiz_rounded));
      await tester.dragFrom(
        center,
        const Offset(-HnTuning.wheelCarouselStep * 2 - 4, 0),
      );
      await tester.pumpAndSettle();
      expect((current as Pen).toolId, ToolId.pencil);
      expect(tester.takeException(), isNull);
    });

    testWidgets('size dial and color ring', (tester) async {
      final pen = Pen.ballpointPen();
      pen.options = pen.options.copyWith(size: 3);
      Tool current = pen;
      Color? picked;
      final key = await pump(
        tester,
        tool: () => current,
        setTool: (t) => current = t,
        setColor: (c) => picked = c,
      );
      key.currentState!.expand();
      await tester.pumpAndSettle();

      // 왼쪽 굵기 점 -> 다이얼
      final wheel = tester.getRect(find.byType(HnPopover));
      await tester.tapAt(Offset(wheel.center.dx - 102, wheel.center.dy));
      await tester.pumpAndSettle();
      expect(find.textContaining('굵기 ·'), findsOneWidget);
      // 다이얼 오른쪽 아래 끝(시계 방향 끝) 근처를 누르면 최대 굵기에 가깝다
      final end =
          wheel.center + Offset.fromDirection(0.25 * 3.14159 * 1.0, 104);
      await tester.tapAt(end);
      await tester.pumpAndSettle();
      expect(pen.options.size, greaterThan(20));
      // 가운데를 누르면 돌아간다
      await tester.tapAt(wheel.center);
      await tester.pumpAndSettle();
      expect(find.textContaining('굵기 ·'), findsNothing);

      // 오른쪽 색 점 -> 색상 링 -> 맨 위 색 선택
      await tester.tapAt(Offset(wheel.center.dx + 102, wheel.center.dy));
      await tester.pumpAndSettle();
      await tester.tapAt(Offset(wheel.center.dx, wheel.center.dy - 102));
      await tester.pumpAndSettle();
      expect(picked, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });
}
