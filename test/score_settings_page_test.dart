// 재생 설정 화면의 입력 흐름 검증. 쪽 마디수를 모달 없이 이어서 넣고 늦은 저장이 치는 글자를 덮지 않으며,
// 쪽 템포는 바꾼 항목만 고정하고, 회전 중에는 나갈 수 없고, 되돌리기 알림이 화면 수명을 넘기지 않음.

import 'dart:async';
import 'dart:io';

import 'package:baton/cloud/api_client.dart';
import 'package:baton/cloud/coin_wallet.dart';
import 'package:baton/core/db/database.dart';
import 'package:baton/core/providers.dart';
import 'package:baton/core/storage/paths.dart';
import 'package:baton/score/score_repo.dart';
import 'package:baton/score/score_settings_page.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 회전이 끝나지 않고 쪽 저장을 붙잡아 둘 수 있는 저장소. 작업 중 화면 상태와 늦은 저장을 보려고 씀.
class _HoldingRepo extends ScoreRepo {
  /// 처음에는 아무것도 붙잡지 않음.
  _HoldingRepo(super.db);

  /// 채워 두면 쪽 저장이 이 신호를 기다림.
  Completer<void>? saveGate;

  /// 끝나지 않는 회전. 작업 중 상태만 봄.
  @override
  Future<void> rotatePage(int scoreId, int pageIndex, int quarterTurns) => Completer<void>().future;

  /// saveGate가 있으면 풀릴 때까지 기다린 뒤 저장함.
  @override
  Future<void> updatePage(
    int scoreId,
    int pageIndex, {
    int? barCount,
    Value<double?> bpm = const Value.absent(),
    Value<int?> clicksPerBar = const Value.absent(),
  }) async {
    await saveGate?.future;
    await super.updatePage(
      scoreId,
      pageIndex,
      barCount: barCount,
      bpm: bpm,
      clicksPerBar: clicksPerBar,
    );
  }
}

/// 뷰어가 계속 그릴 수 있어 pumpAndSettle 대신 넉넉히 몇 번 돌림.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late BatonDatabase db;
  late _HoldingRepo repo;
  late int scoreId;
  late Directory docs;

  setUp(() async {
    docs = Directory.systemTemp.createTempSync('baton-settings-test');
    AppPaths.overrideDocuments(docs);
    db = BatonDatabase.forTesting(NativeDatabase.memory());
    repo = _HoldingRepo(db);
    scoreId = await repo.createScore(name: '테스트 악보', pageCount: 3);
  });

  tearDown(() async {
    await db.close();
    docs.deleteSync(recursive: true);
  });

  /// 홈 화면 위에 설정 화면을 연 상태로 띄움. 닫힌 뒤를 보려고 홈에도 Scaffold를 둠.
  Future<void> openSettings(WidgetTester tester) async {
    // 폰 배치(폭 720 이하)에서 쪽 줄까지 한 화면에 들어오게 세로로 길게 둠
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          scoreRepoProvider.overrideWithValue(repo),
          // 기본 제공자는 닫힐 때 지갑을 두 번 dispose해 테스트 끝에서 단언이 터짐
          coinWalletProvider.overrideWith((ref) => CoinWallet(ApiClient())),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ScoreSettingsPage(scoreId: scoreId, pdfPath: '${docs.path}/없음.pdf'),
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await settle(tester);
  }

  /// 쪽 줄의 메뉴를 열어 항목을 고름.
  Future<void> pickMenu(WidgetTester tester, int slot, String item) async {
    await tester.tap(find.byType(PopupMenuButton<String>).at(slot));
    await settle(tester);
    await tester.tap(find.text(item));
    await settle(tester);
  }

  testWidgets('쪽 목록 위에 마디수 세는 규칙을 보여 줌', (tester) async {
    await openSettings(tester);
    expect(find.textContaining('도돌이표는 되풀이되는 만큼 더하고'), findsOneWidget);
    expect(find.textContaining('표지는 0'), findsOneWidget);
  });

  testWidgets('마디수 칸은 칠 때마다 저장하고 다음 키로 다음 쪽 칸에 들어감', (tester) async {
    await openSettings(tester);
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));

    await tester.tap(fields.at(0));
    await tester.enterText(fields.at(0), '12');
    await settle(tester);
    expect((await repo.pages(scoreId))[0].barCount, 12, reason: '제출하지 않고 나가도 값이 남아야 함');

    await tester.testTextInput.receiveAction(TextInputAction.next);
    await settle(tester);
    expect(tester.widget<TextField>(fields.at(1)).focusNode!.hasFocus, isTrue);
    expect(tester.widget<ListTile>(find.byType(ListTile).at(1)).selected, isTrue);
  });

  testWidgets('늦게 끝난 저장이 치는 중에 비운 칸을 되살리지 않고, 밖에서 바꾼 값은 칸에 보임', (tester) async {
    await openSettings(tester);
    final field = find.byType(TextField).at(0);
    String shown() => tester.widget<TextField>(field).controller!.text;
    await tester.tap(field);
    await settle(tester);

    repo.saveGate = Completer<void>();
    await tester.enterText(field, '5');
    await tester.enterText(field, '');
    repo.saveGate!.complete();
    repo.saveGate = null;
    await settle(tester);
    expect((await repo.pages(scoreId))[0].barCount, 5);
    expect(shown(), '', reason: '되살아난 옛 값 뒤에 이어 친 숫자가 붙으면 안 됨');

    await tester.enterText(field, '7');
    await settle(tester);
    await tester.tap(find.text('균등 배분'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '30');
    await tester.tap(find.text('배분'));
    await settle(tester);
    expect(shown(), '10', reason: '배분 같은 바깥 변경은 칸에 바로 보여야 함');
  });

  testWidgets('쪽 템포 대화상자는 범위 밖 값을 알리고, 바꾼 항목만 쪽 고정값으로 남김', (tester) async {
    await openSettings(tester);
    await pickMenu(tester, 0, '이 페이지만 템포·박 바꾸기');

    final dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogFields.at(1), '0');
    await tester.tap(find.text('확인'));
    await settle(tester);
    expect(find.text('1~16 사이로 넣어야 함'), findsOneWidget, reason: '조용히 버리지 않음');
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(dialogFields.at(1), '3');
    await tester.tap(find.text('확인'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    final page = (await repo.pages(scoreId))[0];
    expect(page.clicksPerBar, 3);
    expect(page.bpm, isNull, reason: '손대지 않은 BPM은 곡 템포를 계속 따라가야 함');
  });

  testWidgets('회전 중에는 뒤로 나갈 수 없고 무엇을 기다리는지 보여 줌', (tester) async {
    await openSettings(tester);
    await pickMenu(tester, 0, '오른쪽으로 90도');
    expect(find.text('페이지를 돌리는 중'), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await settle(tester);
    expect(find.text('재생 설정'), findsOneWidget, reason: '회전이 끝나기 전에 리더가 파일을 다시 읽으면 안 됨');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('균등 배분의 되돌리기 알림은 시간이 지나거나 화면을 닫으면 사라짐', (tester) async {
    await openSettings(tester);
    await tester.tap(find.text('균등 배분'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '12');
    await tester.tap(find.text('배분'));
    await settle(tester);
    expect(find.text('되돌리기'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(find.text('되돌리기'), findsNothing, reason: '동작이 달려도 스스로 닫혀야 함');

    await tester.tap(find.text('균등 배분'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '9');
    await tester.tap(find.text('배분'));
    await settle(tester);
    expect(find.text('되돌리기'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester);
    expect(find.text('열기'), findsOneWidget);
    expect(find.text('되돌리기'), findsNothing, reason: '닫힌 화면의 State에 묶인 동작이 남으면 안 됨');
  });
}
