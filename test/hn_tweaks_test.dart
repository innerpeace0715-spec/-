import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/toolbar/hn_pen_extras.dart';
import 'package:saber/components/toolbar/pen_modal.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/hn/hn_tuning.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/shape_pen.dart';

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

  group('Saber HN: pen options bar', () {
    Future<void> pump(
      WidgetTester tester,
      Pen pen, {
      double width = 1200,
    }) async {
      tester.view.physicalSize = Size(width, 400);
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

    testWidgets('renders without overflow, even on a narrow screen', (
      tester,
    ) async {
      for (final width in [1200.0, 600.0]) {
        final pen = Pen.fountainPen();
        pen.options = pen.options.copyWith();
        Pen.currentPen = pen;
        await pump(tester, pen, width: width);
        expect(tester.takeException(), isNull);
        expect(find.byType(SizePicker), findsOneWidget);
        expect(find.byType(StrokePreview), findsOneWidget);
        expect(find.byType(FavoriteSizes), findsOneWidget);
        expect(find.byType(StabilizationPicker), findsOneWidget);
      }
    });

    testWidgets('no stabilization slider for the shape pen', (tester) async {
      final pen = ShapePen();
      Pen.currentPen = pen;
      await pump(tester, pen);
      expect(find.byType(StabilizationPicker), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the size slider jumps to that size', (tester) async {
      final pen = Pen.fountainPen();
      pen.options = pen.options.copyWith(size: 5);
      Pen.currentPen = pen;
      await pump(tester, pen);

      final slider = find.byType(SizePicker);
      final rect = tester.getRect(slider);
      // 오른쪽 끝 근처를 누르면 최대 굵기에 가까워진다
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

      // 첫 칸에 현재 굵기(7.3) 저장
      await tester.longPress(favs.at(0));
      await tester.pumpAndSettle();

      // 다른 칸을 눌러 굵기 변경
      await tester.tap(favs.at(1));
      await tester.pumpAndSettle();
      expect(pen.options.size, isNot(7.3));

      // 첫 칸을 누르면 저장해 둔 7.3으로 돌아온다
      await tester.tap(favs.at(0));
      await tester.pumpAndSettle();
      expect(pen.options.size, 7.3);
    });

    testWidgets('stabilization slider changes streamline', (tester) async {
      final pen = Pen.ballpointPen();
      pen.options = pen.options.copyWith();
      Pen.currentPen = pen;
      await pump(tester, pen);

      final slider = find.descendant(
        of: find.byType(StabilizationPicker),
        matching: find.byType(Slider),
      );
      await tester.tapAt(tester.getTopRight(slider) + const Offset(-10, 18));
      await tester.pumpAndSettle();
      expect(pen.options.streamline, greaterThan(0.75));
      await tester.tapAt(tester.getTopLeft(slider) + const Offset(10, 18));
      await tester.pumpAndSettle();
      expect(pen.options.streamline, lessThan(0.15));
    });
  });
}
