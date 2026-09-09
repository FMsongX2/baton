// 좌표 변환 검증. 여기가 어긋나면 필기가 악보와 다른 자리에 찍히고 저장까지 되어 되돌릴 수 없음.

import 'dart:ui';

import 'package:baton/reader/annotation/page_coords.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rect = Rect.fromLTWH(100, 50, 400, 800);

  test('페이지 안의 점이 0~1로 정규화됨', () {
    expect(toNormalized(const Offset(100, 50), rect), const Offset(0, 0));
    expect(toNormalized(const Offset(500, 850), rect), const Offset(1, 1));
    expect(toNormalized(const Offset(300, 450), rect), const Offset(0.5, 0.5));
  });

  test('페이지 밖은 가장자리로 붙어 획이 끊기지 않음', () {
    expect(toNormalized(const Offset(-999, -999), rect), const Offset(0, 0));
    expect(toNormalized(const Offset(9999, 9999), rect), const Offset(1, 1));
    expect(toNormalized(const Offset(300, 9999), rect), const Offset(0.5, 1));
  });

  test('크기가 0인 사각형에도 죽지 않음', () {
    expect(toNormalized(const Offset(5, 5), Rect.zero), Offset.zero);
  });

  test('정규 좌표에서 뷰어 좌표로 되돌아옴', () {
    const n = Offset(0.25, 0.75);
    final v = toDocument(n, rect);
    expect(v, const Offset(200, 650));
    expect(toNormalized(v, rect), n);
  });

  test('확대되어 사각형이 커져도 같은 정규 좌표가 나옴', () {
    const zoomed = Rect.fromLTWH(-200, -400, 1600, 3200);
    final a = toNormalized(const Offset(300, 450), rect);
    final b = toNormalized(toDocument(a, zoomed), zoomed);
    expect(b.dx, closeTo(a.dx, 1e-9));
    expect(b.dy, closeTo(a.dy, 1e-9));
  });

  test('점이 속한 페이지를 찾음', () {
    final rects = {
      0: const Rect.fromLTWH(0, 0, 100, 200),
      1: const Rect.fromLTWH(0, 210, 100, 200),
    };
    expect(pageAt(rects, const Offset(50, 100)), 0);
    expect(pageAt(rects, const Offset(50, 300)), 1);
    expect(pageAt(rects, const Offset(50, 205)), isNull, reason: '페이지 사이 여백');
    expect(pageAt(rects, const Offset(500, 100)), isNull);
    expect(pageAt(const {}, Offset.zero), isNull);
  });
}
