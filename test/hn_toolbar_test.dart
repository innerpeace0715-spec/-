import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/hn/quick_wheel.dart';
import 'package:saber/components/toolbar/pen_modal.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  testWidgets('Saber HN: pen card and quick wheel in the editor', (
    tester,
  ) async {
    FlavorConfig.setup();
    FileManager.documentsDirectory =
        '$tmpDir/hnToolbar/${FileManager.appRootDirectoryPrefix}';
    stows.hnQuickWheelVisible.value = false;
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: Editor()));
    await tester.pumpAndSettle();
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);

    final penButton = find.byTooltip(Pen.currentPen.name).first;
    expect(state.currentTool, isA<Pen>());

    // 이미 선택된 펜을 누르면 카드가 열린다
    await tester.tap(penButton);
    await tester.pumpAndSettle();
    expect(find.byType(PenModal), findsOneWidget);
    expect(find.text('브러시 두께'), findsOneWidget);

    // 같은 버튼을 다시 누르면 닫힌다
    await tester.tap(penButton);
    await tester.pumpAndSettle();
    expect(find.byType(PenModal), findsNothing);

    // 다시 열고, 바깥(캔버스)을 누르면 닫힌다
    await tester.tap(penButton);
    await tester.pumpAndSettle();
    expect(find.byType(PenModal), findsOneWidget);
    await tester.tapAt(const Offset(1100, 1000));
    await tester.pumpAndSettle();
    expect(find.byType(PenModal), findsNothing);

    // 펜 버튼을 길게 누르면 원형 퀵메뉴가 펼쳐진다
    await tester.longPress(penButton);
    await tester.pumpAndSettle();
    expect(find.byType(HnQuickWheel), findsOneWidget);
    expect(find.byIcon(Icons.undo_rounded).hitTestable(), findsOneWidget);

    // 설정 버튼 -> 카드
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(PenModal), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
