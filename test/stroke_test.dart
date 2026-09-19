// 획 직렬화·지우개 히트 테스트·필압 렌더 검증. 필기는 사용자가 만든 데이터라 왕복에서 깨지면 복구 불가.

import 'dart:ui' show Size;

import 'package:baton/reader/annotation/stroke.dart';
import 'package:baton/reader/annotation/stroke_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('직렬화 왕복에서 좌표·도구·필압이 보존됨', () {
    final s = Stroke(
      tool: StrokeTool.highlighter,
      color: 0x80FFEB3B,
      width: 0.004,
      points: const [Offset(0.1, 0.2), Offset(0.3, 0.4)],
      pressures: const [0.5, 0.9],
    );
    final back = Stroke.fromJson(s.toJson());
    expect(back.tool, StrokeTool.highlighter);
    expect(back.color, 0x80FFEB3B);
    expect(back.width, closeTo(0.004, 1e-12));
    expect(back.points, const [Offset(0.1, 0.2), Offset(0.3, 0.4)]);
    expect(back.pressures, const [0.5, 0.9]);
  });

  test('필압 없는 획도 왕복함', () {
    final s = Stroke(
      tool: StrokeTool.pen,
      color: 0xFF000000,
      width: 0.002,
      points: const [Offset(0, 0)],
    );
    final back = Stroke.fromJson(s.toJson());
    expect(back.pressures, isNull);
    expect(back.points.length, 1);
  });

  test('좌표가 홀수 개면 마지막 값을 버리고 복원함', () {
    final back = Stroke.fromJson({
      't': 0,
      'c': 0,
      'w': 0.001,
      'p': [0.1, 0.2, 0.3],
    });
    expect(back.points, const [Offset(0.1, 0.2)]);
  });

  test('히트 테스트는 선분에 가까운 점만 잡음', () {
    final s = Stroke(
      tool: StrokeTool.pen,
      color: 0xFF000000,
      width: 0.002,
      points: const [Offset(0.0, 0.0), Offset(1.0, 0.0)],
    );
    expect(s.hitTest(const Offset(0.5, 0.005), 0.01), isTrue, reason: '선분 바로 위');
    expect(s.hitTest(const Offset(0.5, 0.05), 0.01), isFalse, reason: '멀리 떨어짐');
    expect(s.hitTest(const Offset(-0.005, 0.0), 0.01), isTrue, reason: '끝점 근처');
    expect(s.hitTest(const Offset(-0.5, 0.0), 0.01), isFalse, reason: '선분 연장선이지만 밖');
  });

  test('점 하나짜리 획도 히트 테스트가 동작함', () {
    final s = Stroke(
      tool: StrokeTool.pen,
      color: 0,
      width: 0.002,
      points: const [Offset(0.5, 0.5)],
    );
    expect(s.hitTest(const Offset(0.505, 0.5), 0.01), isTrue);
    expect(s.hitTest(const Offset(0.6, 0.5), 0.01), isFalse);
  });

  test('빈 획은 아무것도 잡지 않음', () {
    final s = Stroke(tool: StrokeTool.pen, color: 0, width: 0.002, points: const []);
    expect(s.hitTest(const Offset(0.5, 0.5), 1.0), isFalse);
  });

  test('1을 넘는 옛 필압은 1로 접어 그려 굵기가 설정을 넘지 않음', () {
    Stroke line(double p) => Stroke(
      tool: StrokeTool.pen,
      color: 0,
      width: 0.01,
      points: [for (var i = 0; i <= 10; i++) Offset(0.1 + i * 0.08, 0.5)],
      pressures: List.filled(11, p),
    );
    const page = Size(1000, 1000);
    final full = strokePath(line(1.0), page).getBounds();
    final raw = strokePath(line(4.2), page).getBounds();
    expect(raw.height, closeTo(full.height, 1e-6));
  });
}
