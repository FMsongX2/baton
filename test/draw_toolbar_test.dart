// 필기 도구줄 배치. 폰 세로 폭에서도 실행취소·다시 실행이 처음 화면 안에 보이는지를 고정함.

import 'package:baton/reader/draw_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('폭 360 화면에서도 실행취소·다시 실행이 밀지 않고 보임', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawToolbar(
            tool: ReaderTool.pen,
            color: kPenColors.first,
            width: kPenWidths.first,
            stylusOnly: false,
            canUndo: true,
            canRedo: true,
            onTool: (_) {},
            onColor: (_) {},
            onWidth: (_) {},
            onStylusOnly: () {},
            onUndo: () {},
            onRedo: () {},
          ),
        ),
      ),
    );
    for (final label in ['실행취소', '다시 실행']) {
      final rect = tester.getRect(find.byTooltip(label));
      expect(rect.left, greaterThanOrEqualTo(0), reason: label);
      expect(rect.right, lessThanOrEqualTo(360), reason: label);
    }
  });
}
