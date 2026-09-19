// 쪽 회전이 끝나면 화면 수명과 무관하게 라이브러리 칸에 알리는지 검증. 회전 도중 화면을 떠나도
// 노드를 건드리지 않으면 칸이 같은 경로의 옛 표지를 계속 보여 줌.

import 'dart:async';
import 'dart:io';

import 'package:baton/cloud/api_client.dart';
import 'package:baton/cloud/coin_wallet.dart';
import 'package:baton/core/db/database.dart';
import 'package:baton/core/providers.dart';
import 'package:baton/core/storage/paths.dart';
import 'package:baton/library/library_repo.dart';
import 'package:baton/score/score_repo.dart';
import 'package:baton/score/score_settings_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 회전을 신호가 올 때까지 붙잡아 두는 저장소. 회전 도중 화면을 닫으려고 씀.
class _GatedRotateRepo extends ScoreRepo {
  /// 받은 DB에 회전만 붙잡는 저장소를 만듦.
  _GatedRotateRepo(super.db);

  /// 완료하면 붙잡아 둔 회전이 끝남.
  final gate = Completer<void>();

  /// 신호가 오면 PDF는 건드리지 않고 끝남.
  @override
  Future<void> rotatePage(int scoreId, int pageIndex, int quarterTurns) => gate.future;
}

/// 뷰어 초기화가 묻는 캐시 디렉토리 채널. 답하지 않아 뷰어가 PDF 엔진을 부르기 전에 멈춰 있게 함.
/// 이 테스트 환경에는 PDF 엔진이 없어, 닫힌 뷰어가 뒤늦게 엔진을 부르면 처리되지 않은 오류가 남.
const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

/// 가짜 시계로 몇 번 그림.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 진짜 비동기 입출력(표지 렌더 시도, DB 쓰기)을 흘려보내며 몇 번 그림. 뷰어가 닫힌 뒤에만 씀.
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late BatonDatabase db;
  late Directory docs;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('baton-rotate-test');
    AppPaths.overrideDocuments(docs);
    db = BatonDatabase.forTesting(NativeDatabase.memory());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _pathProvider,
      (_) => Completer<Object?>().future,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _pathProvider,
      null,
    );
    await db.close();
    docs.deleteSync(recursive: true);
  });

  testWidgets('회전 도중 설정 화면을 떠나도 끝나면 라이브러리 칸에 알림', (tester) async {
    final repo = _GatedRotateRepo(db);
    final scoreId = await tester.runAsync(() => repo.createScore(name: '악보', pageCount: 2));
    final library = LibraryRepo(db);
    final before = (await tester.runAsync(() => library.node(scoreId!)))!.updatedAt;

    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          scoreRepoProvider.overrideWithValue(repo),
          coinWalletProvider.overrideWith((ref) => CoinWallet(ApiClient())),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ScoreSettingsPage(scoreId: scoreId!, pdfPath: '${docs.path}/없음.pdf'),
                ),
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await settle(tester);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await settle(tester);
    await tester.tap(find.text('오른쪽으로 90도'));
    await settle(tester);
    expect(find.text('페이지를 돌리는 중'), findsOneWidget);

    // 뒤로가기는 막혀 있지만 라우트는 다른 길로도 닫힐 수 있음
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester);
    expect(find.text('열기'), findsOneWidget);

    repo.gate.complete();
    await settleIo(tester);

    final after = (await tester.runAsync(() => library.node(scoreId!)))!.updatedAt;
    expect(after.isAfter(before), isTrue, reason: '칸은 노드가 바뀌어야 표지를 다시 읽음');
  });
}
