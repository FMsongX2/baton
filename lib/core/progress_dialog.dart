// 작업이 끝날 때까지 닫히지 않는 진행 대화상자. 가져오기·백업처럼 도중에 끊으면 안 되는 작업에 씀.
// 끝나면 맨 위 라우트가 아니라 이 대화상자 라우트만 치움.

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 진행 대화상자를 띄운 채 job을 돌리고, 끝나면 성공·실패와 무관하게 그 대화상자만 닫음.
/// job의 결과와 예외를 그대로 넘김. 뒤로가기는 PopScope로 막음.
/// showDialog는 라우트를 돌려주지 않고, 빌더에서 잡으면 첫 프레임 전에 끝난 작업이 닫을 대상을 모름.
/// 그래서 라우트를 직접 만들어 밀고, 그 라우트를 붙잡아 두었다가 치움.
Future<T> runWithProgress<T>(BuildContext context, String label, Future<T> Function() job) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: kGapL),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    ),
  );
  unawaited(navigator.push(route));
  try {
    return await job();
  } finally {
    if (route.isCurrent) {
      navigator.pop();
    } else if (route.isActive) {
      navigator.removeRoute(route);
    }
  }
}
