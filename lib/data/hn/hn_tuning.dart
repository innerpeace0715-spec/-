import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Saber HN(행님 개조판)의 체감 관련 값을 한곳에 모은 파일.
///
/// 써 보고 강도를 조정할 때는 이 파일의 숫자만 바꾸면 된다.
abstract final class HnTuning {
  // ───────────────────────── 획 안정화 ─────────────────────────

  /// 안정화 슬라이더 범위(0~100%)와 눈금 수(5% 단위).
  static const double stabilizationMin = 0;
  static const double stabilizationMax = 1;
  static const stabilizationDivisions = 20;

  /// 그리기 단계의 지연(perfect_freehand streamline). 떨림은 입력 필터가 잡으므로
  /// 낮게 둔다. 원본 기본값은 0.5.
  static const renderStreamline = 0.2;

  /// 획 끝에서 이 시간 동안 멈춰 있으면 도형으로 인식한다.
  static const holdShapeDelay = Duration(milliseconds: 550);

  /// "멈춤"으로 볼 움직임 허용치(페이지 좌표).
  static const double holdShapeStillDistance = 4;

  /// 도형 인식 후 이만큼 움직이면 취소.
  static const double holdShapeCancelDistance = 14;

  // ───────────────────────── 굵기 ─────────────────────────

  /// 굵기 슬라이더 길이(논리 픽셀). 원본은 150.
  static const double sizeSliderLength = 220;

  /// 굵기 슬라이더 위아래로 더하는 터치 여유(논리 픽셀).
  static const double sizeSliderTouchPadding = 12;

  /// 굵기 슬라이더의 곡률. 1이면 직선, 2면 앞쪽(가는 굵기)을 더 세밀하게.
  static const double sizeSliderExponent = 2;

  /// 굵기 슬라이더를 끌 때 정수 굵기를 지날 때마다 미세 진동.
  static const sizeSliderTicks = true;

  // ───────────────────────── 누름 반응 ─────────────────────────

  /// 버튼을 누를 때 줄어드는 비율.
  static const pressScale = 0.94;

  /// 누를 때 줄어드는 시간.
  static const pressDownDuration = Duration(milliseconds: 90);

  /// 손을 뗄 때 돌아오는 시간.
  static const pressUpDuration = Duration(milliseconds: 220);

  static const Curve pressDownCurve = Curves.easeOutCubic;

  /// 돌아올 때 아주 살짝 튕기는 스프링.
  static const Curve pressUpCurve = SpringCurve(dampingRatio: 0.6);

  // ───────────────────────── 여닫기 ─────────────────────────

  /// 툴바 옵션 줄(펜 옵션, 색상 등)이 열리고 닫히는 시간. 원본은 240ms 직선 감속.
  static const panelDuration = Duration(milliseconds: 340);

  /// 툴바 옵션 줄의 스프링 곡선.
  static const Curve panelCurve = SpringCurve(dampingRatio: 0.85);

  /// 바텀시트가 열리고 닫히는 시간.
  static const sheetEnterDuration = Duration(milliseconds: 380);
  static const sheetExitDuration = Duration(milliseconds: 240);
  static const Curve sheetEnterCurve = SpringCurve(dampingRatio: 0.9);
  static const Curve sheetExitCurve = Curves.easeInCubic;

  static AnimationStyle get sheetAnimationStyle => const AnimationStyle(
    duration: sheetEnterDuration,
    reverseDuration: sheetExitDuration,
    curve: sheetEnterCurve,
    reverseCurve: sheetExitCurve,
  );

  /// 펜 설정 카드가 뜨고 사라지는 시간·곡선.
  static const popoverEnterDuration = Duration(milliseconds: 360);
  static const popoverExitDuration = Duration(milliseconds: 150);
  static const Curve popoverEnterCurve = SpringCurve(dampingRatio: 0.72);

  /// 원형 퀵메뉴 크기.
  static const double wheelDiameter = 272;
  static const double wheelMiniDiameter = 58;

  /// 원형 메뉴 펜 넘기기: 이만큼(논리 픽셀) 밀 때마다 펜 하나씩.
  static const double wheelCarouselStep = 46;

  /// 마지막 페이지 아래로 더 내릴 수 있는 여백(화면 높이 비율).
  static const extraScrollBelowPages = 0.5;

  /// 손가락 탭 제스처(두 손가락=실행취소, 세 손가락=다시실행) 판정 기준.
  static const tapGestureMaxDuration = Duration(milliseconds: 280);
  static const double tapGestureMaxMove = 18;

  // ───────────────────────── 진동 ─────────────────────────

  /// 모든 진동을 한 번에 끄려면 false.
  static const hapticsEnabled = true;

  /// 도구 선택·토글 때.
  static void selectionHaptic() {
    if (!hapticsEnabled) return;
    HapticFeedback.selectionClick();
  }

  /// 즐겨찾기 굵기 저장처럼 "확정" 느낌이 필요할 때.
  static void confirmHaptic() {
    if (!hapticsEnabled) return;
    HapticFeedback.mediumImpact();
  }
}

/// 감쇠 스프링 응답을 0→1 곡선으로 쓴 것.
///
/// [dampingRatio]가 1 이상이면 넘치지 않고, 1보다 작을수록 끝에서 살짝 튕긴다.
/// 곡선의 끝값이 정확히 1이 되도록 보정한다.
class SpringCurve extends Curve {
  const new({this.dampingRatio = 0.8, this.stiffness = 8.5});

  /// 감쇠비 ζ.
  final double dampingRatio;

  /// 곡선 구간(0~1) 동안의 고유 진동수 ω₀. 클수록 빨리 자리 잡는다.
  final double stiffness;

  double _raw(double t) {
    final z = dampingRatio;
    final w0 = stiffness;
    if (z < 1) {
      final wd = w0 * math.sqrt(1 - z * z);
      final envelope = math.exp(-z * w0 * t);
      return 1 -
          envelope * (math.cos(wd * t) + (z * w0 / wd) * math.sin(wd * t));
    } else {
      // 임계 감쇠
      return 1 - math.exp(-w0 * t) * (1 + w0 * t);
    }
  }

  @override
  double transformInternal(double t) {
    // t=1에서 정확히 1이 되도록 끝값으로 나눈다.
    return _raw(t) / _raw(1);
  }
}
