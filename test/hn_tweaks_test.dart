import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/hn/hn_popover.dart';
import 'package:saber/components/hn/quick_wheel.dart';
import 'package:saber/components/toolbar/hn_pen_extras.dart';
import 'package:saber/components/toolbar/pen_modal.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/hn/hn_tuning.dart';
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

  group('Saber HN: stabilization', () {
    test('setter clamps and keeps smoothing in range', () {
      final pen = Pen.fountainPen();
      pen.options = pen.options.copyWith();

      pen.stabilization = 0.7;
      expect(pen.options.streamline, 0.7);
      expect(pen.options.smoothing, 0.7);

      pen.stabilization = 0;
      expect(pen.options.streamline, 0);
      expect(pen.options.smoothing, HnTuning.smoothingMin);

      pen.stabilization = 5;
      expect(pen.options.streamline, HnTuning.stabilizationMax);
    });

    test('default pen options are unchanged (old notes render the same)', () {
      expect(
        Pen.fountainPenOptions.streamline,
        StrokeOptions.defaultStreamline,
      );
      expect(Pen.fountainPenOptions.smoothing, StrokeOptions.defaultSmoothing);
      expect(Pen.pencilOptions.streamline, 0.1);
      // 기본값이면 노트 파일에 sl/sm이 저장되지 않는다
      final json = Pen.fountainPenOptions.toJson();
      expect(json.containsKey('sl'), isFalse);
      expect(json.containsKey('sm'), isFalse);
    });

    test('changed stabilization is saved in the stroke json', () {
      final pen = Pen.ballpointPen();
      pen.options = pen.options.copyWith();
      pen.stabilization = 0.8;
      final json = pen.options.toJson();
      expect(json['sl'], 0.8);
      final restored = StrokeOptions.fromJson(json);
      expect(restored.streamline, 0.8);
    });

    test('shape pen does not support stabilization', () {
      expect(ShapePen().supportsStabilization, isFalse);
      expect(Pen.fountainPen().supportsStabilization, isTrue);
      expect(Highlighter().supportsStabilization, isTrue);
      expect(Pencil().supportsStabilization, isTrue);
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
      expect(find.text('브러시 두께'), findsOneWidget);
      expect(find.text('압력 감도'), findsOneWidget);
      expect(find.text('잉크 유량'), findsOneWidget);
      expect(find.text('안정화'), findsOneWidget);
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
      expect(find.text('압력 감도'), findsNothing);
      expect(find.text('안정화'), findsOneWidget);

      final shape = ShapePen();
      Pen.currentPen = shape;
      await pump(tester, shape);
      expect(find.text('안정화'), findsNothing);
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

    testWidgets('sliders change stabilization, pressure and ink flow', (
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

      await tapEnd('안정화', right: true);
      expect(pen.options.streamline, greaterThan(0.8));
      await tapEnd('안정화', right: false);
      expect(pen.options.streamline, lessThan(0.1));

      await tapEnd('압력 감도', right: false);
      expect(pen.options.thinning, lessThan(0.05));
      await tapEnd('압력 감도', right: true);
      expect(pen.options.thinning, greaterThan(0.95));

      await tapEnd('잉크 유량', right: false);
      expect(pen.inkFlow, lessThan(0.15));
      expect(pen.strokeColor.a, closeTo(pen.color.a * pen.inkFlow, 0.01));
      await tapEnd('잉크 유량', right: true);
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
