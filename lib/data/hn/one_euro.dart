import 'dart:math' as math;
import 'dart:ui';

/// 속도에 따라 세기가 바뀌는 손떨림 보정 필터(One Euro filter).
///
/// Casiez 외(2012), "1€ Filter: A Simple Speed-based Low-pass Filter for
/// Noisy Input in Interactive Systems". 천천히 움직일 때는 떨림을 강하게
/// 잡고, 빠르게 움직일 때는 거의 그대로 따라가서 지연(선이 늦게 따라옴)을
/// 줄인다. 고정 세기 평균(perfect_freehand의 streamline)보다 자연스럽다.
class OneEuroFilter2D {
  new({required this.minCutoff, required this.beta, this.derivateCutoff = 1});

  /// 가장 느릴 때의 차단 주파수(Hz). 낮을수록 떨림을 더 강하게 잡는다.
  final double minCutoff;

  /// 속도가 빨라질 때 차단 주파수를 올리는 비율. 클수록 빠른 획에서 지연이 적다.
  final double beta;

  /// 속도 추정에 쓰는 차단 주파수(Hz).
  final double derivateCutoff;

  Offset? _x;
  Offset _dx = Offset.zero;

  static double _alpha(double cutoff, double dt) {
    final tau = 1 / (2 * math.pi * cutoff);
    return 1 / (1 + tau / dt);
  }

  void reset() {
    _x = null;
    _dx = Offset.zero;
  }

  /// [dtSeconds]는 직전 점과의 시간 간격(초).
  Offset filter(Offset raw, double dtSeconds) {
    final prev = _x;
    if (prev == null) {
      _x = raw;
      return raw;
    }
    final dt = dtSeconds.clamp(1 / 1000, 1 / 20);

    // 속도(픽셀/초)를 걸러서 추정
    final rawDx = (raw - prev) / dt;
    final aD = _alpha(derivateCutoff, dt);
    _dx = Offset.lerp(_dx, rawDx, aD)!;

    final cutoff = minCutoff + beta * _dx.distance;
    final a = _alpha(cutoff, dt);
    final filtered = Offset.lerp(prev, raw, a)!;
    _x = filtered;
    return filtered;
  }
}

/// 안정화 세기(0~1)를 필터 값으로 바꾼다.
///
/// 0이면 필터를 쓰지 않는다. 세기가 올라갈수록 느린 획의 떨림을 더 잡는다.
OneEuroFilter2D? oneEuroForStrength(double strength) {
  if (strength <= 0.001) return null;
  // 약 12Hz(거의 보정 없음) ~ 0.7Hz(매우 강함), 지수적으로
  final minCutoff = 12 * math.pow(0.7 / 12, strength).toDouble();
  // 빠른 획에서는 세기와 상관없이 잘 따라오도록
  final beta = 0.03 - 0.02 * strength;
  return OneEuroFilter2D(minCutoff: minCutoff, beta: beta);
}
