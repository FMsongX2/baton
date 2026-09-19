// 메트로놈 화면의 박 표시 검증. 박 번호가 소리와 어긋나거나 강박마다 화면이 들썩이면
// 곁눈으로 박을 보는 용도가 무너짐.

import 'package:baton/metronome/metronome_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('이음매 직후 음수 위치는 앞 마디의 끝 박으로 접힘', () {
    // 정수 나눗셈은 0 쪽으로 잘라 -0.1초를 강박(0)으로 셈
    expect(beatIndex(-0.1, 0.5, 4), 3);
    expect(beatIndex(-0.6, 0.5, 4), 2);
    expect(beatIndex(0, 0.5, 4), 0);
    expect(beatIndex(1.6, 0.5, 4), 3);
    expect(beatIndex(2.0, 0.5, 4), 0);
  });

  testWidgets('박 점이 커져도 레이아웃 크기는 그대로임', (tester) async {
    Future<Size> sizeOf({required bool active}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: BeatDot(active: active, accent: true)),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(BeatDot));
    }

    final idle = await sizeOf(active: false);
    final hit = await sizeOf(active: true);
    expect(hit, idle, reason: '크기가 바뀌면 강박마다 아래 컨트롤이 통째로 밀림');
  });
}
