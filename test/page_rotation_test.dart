// 회전 좌표 변환 검증. 필기와 악보가 따로 돌면 사용자가 손으로 적은 것이 엉뚱한 자리에 남고
// PDF는 이미 회전된 뒤라 되돌릴 수 없음.

import 'package:baton/reader/annotation/stroke.dart';
import 'package:baton/score/page_rotation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('시계방향 90도는 좌상단을 우상단으로 보냄', () {
    expect(rotateNormalized(const Offset(0, 0), 1), const Offset(1, 0));
    expect(rotateNormalized(const Offset(1, 0), 1), const Offset(1, 1));
    expect(rotateNormalized(const Offset(1, 1), 1), const Offset(0, 1));
    expect(rotateNormalized(const Offset(0, 1), 1), const Offset(0, 0));
  });

  test('180도는 대각으로 뒤집음', () {
    expect(rotateNormalized(const Offset(0, 0), 2), const Offset(1, 1));
    expect(rotateNormalized(const Offset(0.25, 0.75), 2), const Offset(0.75, 0.25));
  });

  test('270도는 90도의 역방향', () {
    const p = Offset(0.3, 0.8);
    final cw = rotateNormalized(p, 1);
    expect(rotateNormalized(cw, 3), p);
  });

  test('네 번 돌리면 제자리', () {
    const p = Offset(0.13, 0.62);
    var q = p;
    for (var i = 0; i < 4; i++) {
      q = rotateNormalized(q, 1);
    }
    expect(q.dx, closeTo(p.dx, 1e-12));
    expect(q.dy, closeTo(p.dy, 1e-12));
  });

  test('0회전과 4의 배수는 그대로', () {
    const p = Offset(0.4, 0.6);
    expect(rotateNormalized(p, 0), p);
    expect(rotateNormalized(p, 4), p);
    expect(rotateNormalized(p, 8), p);
  });

  test('회전한 점은 항상 0~1 안에 있음', () {
    for (final t in [0, 1, 2, 3]) {
      for (final p in const [Offset(0, 0), Offset(1, 1), Offset(0.5, 0.2), Offset(0, 1)]) {
        final r = rotateNormalized(p, t);
        expect(r.dx, inInclusiveRange(0, 1));
        expect(r.dy, inInclusiveRange(0, 1));
      }
    }
  });

  Stroke sample() => Stroke(
    tool: StrokeTool.pen,
    color: 0xFF000000,
    width: 0.004,
    points: const [Offset(0, 0), Offset(0.5, 0.25)],
    pressures: const [0.4, 0.8],
  );

  test('획의 모든 점이 함께 돌고 필압은 보존됨', () {
    final r = rotateStroke(sample(), 1, 1.0);
    expect(r.points, const [Offset(1, 0), Offset(0.75, 0.5)]);
    expect(r.pressures, const [0.4, 0.8]);
    expect(r.color, 0xFF000000);
  });

  test('90도 회전은 굵기를 종횡비로 보정함', () {
    // A4 세로(폭/높이 약 0.707)를 눕히면 기준 폭이 넓어져 같은 비율이 더 굵어 보임
    final r = rotateStroke(sample(), 1, 0.707);
    expect(r.width, closeTo(0.004 * 0.707, 1e-12));
  });

  test('180도 회전은 기준 폭이 그대로라 굵기를 건드리지 않음', () {
    final r = rotateStroke(sample(), 2, 0.707);
    expect(r.width, 0.004);
  });

  test('90도를 두 번 돌린 굵기는 180도와 같음', () {
    const aspect = 0.707;
    // 90도 두 번이면 폭이 원래대로 돌아오므로 보정도 상쇄되어야 함
    final once = rotateStroke(sample(), 1, aspect);
    final twice = rotateStroke(once, 1, 1 / aspect);
    expect(twice.width, closeTo(0.004, 1e-12));
    expect(twice.points.first.dx, closeTo(1, 1e-12));
    expect(twice.points.first.dy, closeTo(1, 1e-12));
  });
}
