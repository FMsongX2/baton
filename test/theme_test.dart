// 테마 색 대비. 조작줄을 숨겼을 때 재생 중임을 알리는 유일한 표시가 액센트 색이라
// 밝은 연습실과 어두운 무대 양쪽에서 읽혀야 함. WCAG 4.5:1을 기준으로 둠.

import 'package:baton/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 두 색의 명도 대비비. 큰 쪽이 분자.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    final theme = batonTheme(brightness);
    final scheme = theme.colorScheme;
    final name = brightness == Brightness.dark ? '다크' : '라이트';

    test('$name: 액센트가 배경에서 읽힘', () {
      expect(contrast(scheme.primary, theme.scaffoldBackgroundColor), greaterThanOrEqualTo(4.5));
      expect(contrast(scheme.primary, scheme.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(scheme.primary, scheme.surfaceContainerLowest), greaterThanOrEqualTo(4.5));
    });

    test('$name: 강박 표시가 배경에서 구분됨', () {
      // 채워진 도형이라 3:1 기준. 강박과 보통 박을 색으로 구분함
      expect(contrast(scheme.secondary, scheme.surfaceContainerHighest), greaterThanOrEqualTo(3.0));
    });

    test('$name: 액센트 위의 글씨가 읽힘', () {
      // 어두운 액센트에 어두운 onPrimary가 남으면 FilledButton 글씨가 통째로 사라짐
      expect(contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(4.5));
    });
  }

  test('무대용 액센트는 다크 전용이고 라이트에서는 쓰지 않음', () {
    expect(batonTheme(Brightness.dark).colorScheme.primary, kAccent);
    expect(batonTheme(Brightness.light).colorScheme.primary, kAccentInk);
  });
}
