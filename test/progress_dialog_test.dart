// 진행 대화상자 수명 검증. 뒤로가기로 닫히거나 끝날 때 맨 위를 pop하면 밑의 화면(홈·리더)이 닫히므로
// 작업 도중에는 남아 있고, 끝나면 자기 라우트만 사라지는지 고정해 둠.

import 'dart:async';

import 'package:baton/core/progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 안드로이드 시스템 뒤로가기를 흉내 냄.
Future<void> systemBack(WidgetTester tester) async {
  final message = const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    message,
    (_) {},
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  late BuildContext pageContext;

  /// 홈 위에 화면 하나를 올린 상태를 만듦. 진행 대화상자는 그 화면에서 띄움.
  Future<void> openPage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('home')));
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (ctx) {
              pageContext = ctx;
              return const Scaffold(body: Text('page'));
            },
          ),
        );
    await tester.pumpAndSettle();
  }

  testWidgets('뒤로가기로 닫히지 않고, 끝나면 대화상자만 닫힘', (tester) async {
    await openPage(tester);
    final done = Completer<int>();
    final result = runWithProgress(pageContext, '도는 중', () => done.future);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('도는 중'), findsOneWidget);

    await systemBack(tester);
    expect(find.text('도는 중'), findsOneWidget, reason: '작업 도중에는 닫히지 않음');
    expect(find.text('page'), findsOneWidget);

    done.complete(7);
    expect(await result, 7);
    await tester.pumpAndSettle();
    expect(find.text('도는 중'), findsNothing);
    expect(find.text('page'), findsOneWidget, reason: '밑의 화면은 그대로 남음');
  });

  testWidgets('작업이 실패해도 대화상자만 닫고 예외를 넘김', (tester) async {
    await openPage(tester);
    final done = Completer<int>();
    final result = runWithProgress(pageContext, '도는 중', () => done.future);
    await tester.pump(const Duration(milliseconds: 300));

    done.completeError(StateError('실패'));
    await expectLater(result, throwsStateError);
    await tester.pumpAndSettle();
    expect(find.text('도는 중'), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });
}
