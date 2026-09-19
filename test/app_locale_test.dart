// 한국어 전용 앱의 언어 설정. 기기 언어가 영어여도 Material·Cupertino 기본 문구가 한국어로 나와야 함.
// 설정이 빠지면 툴팁·선택 툴바가 영어 기본값(DefaultMaterialLocalizations)으로 떨어짐.

import 'package:baton/main.dart' show BatonApp;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('기기 언어가 영어여도 기본 문구가 한국어', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    // BatonApp 전체를 띄우면 DB·오디오가 필요하므로 언어 설정만 떼어 같은 조건으로 띄움
    late MaterialApp app;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          app = const BatonApp().build(context) as MaterialApp;
          return const SizedBox();
        },
      ),
    );

    late MaterialLocalizations material;
    late CupertinoLocalizations cupertino;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: app.localizationsDelegates,
        supportedLocales: app.supportedLocales,
        locale: app.locale,
        home: Builder(
          builder: (context) {
            material = MaterialLocalizations.of(context);
            cupertino = CupertinoLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(material.backButtonTooltip, '뒤로');
    expect(material.deleteButtonTooltip, '삭제');
    expect(cupertino.pasteButtonLabel, '붙여넣기');
  });
}
