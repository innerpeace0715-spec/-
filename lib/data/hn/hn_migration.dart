import 'package:saber/data/hn/hn_tuning.dart';
import 'package:saber/data/prefs.dart';

/// Saber HN 설정 이전. 편집기를 열 때 한 번 실행된다.
///
/// v2: 안정화를 입력 필터로 옮겼으므로, 이전 판에서 저장된 펜 설정의
/// 그리기 지연(streamline)·smoothing을 새 기본값으로 되돌린다.
/// 굵기·색 같은 다른 설정은 건드리지 않는다.
Future<void> runHnMigrations() async {
  final version = stows.hnSettingsVersion;
  await version.waitUntilRead();
  if (version.value >= 2) return;

  for (final (stow, streamline) in [
    (stows.lastFountainPenOptions, HnTuning.renderStreamline),
    (stows.lastBallpointPenOptions, HnTuning.renderStreamline),
    (stows.lastHighlighterOptions, HnTuning.renderStreamline),
    (stows.lastPencilOptions, 0.1),
  ]) {
    await stow.waitUntilRead();
    stow.value
      ..streamline = streamline
      ..smoothing = 0.5;
    stow.notifyListeners();
  }
  version.value = 2;
}
