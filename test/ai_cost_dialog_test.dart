// 재생 설정 화면의 AI 분석 흐름 검증. 이어받기를 전체 쪽 비용으로 막으면 '코인 부족'으로 다시 못 하고,
// 분석 중 나갈 수 없으면 느린 회선에서 사용자가 수십 분 갇히며, 멈춘 분석이 요청을 보내거나 반영하면 안 됨.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:baton/cloud/api_client.dart';
import 'package:baton/cloud/coin_wallet.dart';
import 'package:baton/core/db/database.dart';
import 'package:baton/core/db/settings_repo.dart';
import 'package:baton/core/providers.dart';
import 'package:baton/core/storage/paths.dart';
import 'package:baton/score/ai_analysis.dart';
import 'package:baton/score/score_repo.dart';
import 'package:baton/score/score_settings_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory docs;
  late BatonDatabase db;
  late int scoreId;
  late CoinWallet wallet;

  setUp(() async {
    docs = Directory.systemTemp.createTempSync('baton-ai-cost-test');
    AppPaths.overrideDocuments(docs);
    db = BatonDatabase.forTesting(NativeDatabase.memory());
    scoreId = await ScoreRepo(db).createScore(name: '긴 악보', pageCount: 16);
    // 잔액은 남은 둘째 묶음(8쪽) 몫뿐. 등록은 화면을 띄우기 전에 끝내 둠
    final routes = <String, Map<String, dynamic>>{
      '/v1/device/register': {
        'userId': 'u',
        'token': 'tok-u',
        'balance': 8,
        'recoveryCode': 'ABCD-EFGH-JKLM',
      },
      '/v1/pricing': {'coinsPerPage': 1, 'packs': [], 'maxPagesPerCall': 8},
    };
    wallet = CoinWallet(
      ApiClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient(
          (req) async => http.Response.bytes(utf8.encode(jsonEncode(routes[req.url.path])), 200),
        ),
      ),
    );
    await wallet.refresh();
  });

  tearDown(() async {
    await db.close();
    docs.deleteSync(recursive: true);
  });

  /// 묶음 기록을 넣고 설정 화면에서 AI 확인 대화상자를 띄움.
  Future<void> openAiDialog(WidgetTester tester, Map<String, dynamic> batch) async {
    final record = {'id': 'b-1', 'pageCount': 16, 'perCall': 8, ...batch};
    await SettingsRepo(db).set('ai_batch_$scoreId', jsonEncode(record));
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          coinWalletProvider.overrideWith((ref) => wallet),
        ],
        child: MaterialApp(
          home: ScoreSettingsPage(scoreId: scoreId, pdfPath: '${docs.path}/없음.pdf'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('AI로 마디수 읽기'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('첫 묶음 결과를 받고 끊긴 분석은 남은 쪽 코인만 있으면 다시 분석할 수 있음', (tester) async {
    // 앞선 분석이 1~8쪽(0부터 0~7) 결과를 받고 둘째 묶음에서 끊긴 기록
    await openAiDialog(tester, {
      'answered': [for (var i = 0; i < 8; i++) i],
    });

    expect(find.textContaining('코인 8개를 씀'), findsOneWidget);
    expect(find.textContaining('답을 못 받은'), findsNothing);
    final analyze = find.widgetWithText(FilledButton, '분석');
    expect(analyze, findsOneWidget);
    expect(tester.widget<FilledButton>(analyze).onPressed, isNotNull);
  });

  testWidgets('답을 기다리다 멈춘 묶음은 잔액이 모자라도 코인 없이 이어받으러 갈 수 있음', (tester) async {
    // 둘째 묶음을 보낸 뒤 멈춤. 서버가 그 몫을 이미 빼 잔액이 0
    wallet.setBalance(0);
    await openAiDialog(tester, {
      'answered': [for (var i = 0; i < 8; i++) i],
      'sent': [for (var i = 0; i < 16; i++) i],
    });

    expect(find.textContaining('코인 0개를 씀'), findsOneWidget);
    expect(find.textContaining('답을 못 받은 8쪽'), findsOneWidget);
    final analyze = find.widgetWithText(FilledButton, '분석');
    expect(analyze, findsOneWidget);
    expect(tester.widget<FilledButton>(analyze).onPressed, isNotNull);
  });

  /// 분석 서비스를 바꿔 끼운 앱에 설정 화면을 띄움. 테스트가 직접 걷어 낼 수 있게 그 라우트를 돌려줌.
  Future<Route<void>> openWithService(WidgetTester tester, AiAnalysisService service) async {
    final navigator = GlobalKey<NavigatorState>();
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          coinWalletProvider.overrideWith((ref) => wallet),
          aiAnalysisProvider.overrideWithValue(service),
        ],
        child: MaterialApp(navigatorKey: navigator, home: const SizedBox()),
      ),
    );
    final route = MaterialPageRoute<void>(
      builder: (_) => ScoreSettingsPage(scoreId: scoreId, pdfPath: '${docs.path}/없음.pdf'),
    );
    navigator.currentState!.push(route);
    await tester.pumpAndSettle();
    return route;
  }

  /// 확인 대화상자에서 분석을 시작하고 진행 화면이 뜰 때까지 흘려보냄. 진행 표시가 돌아 settle하지 않음.
  Future<void> startAnalysis(WidgetTester tester) async {
    await tester.tap(find.byTooltip('AI로 마디수 읽기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '분석'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('분석 중 뒤로가기는 분석을 멈추고 반영 없이 화면을 닫음', (tester) async {
    final settings = SettingsRepo(db);
    final scores = ScoreRepo(db);
    await settings.set(
      'ai_batch_$scoreId',
      jsonEncode({
        'id': 'b-1',
        'pageCount': 16,
        'perCall': 8,
        'answered': [for (var i = 0; i < 8; i++) i],
      }),
    );
    final before = [for (final p in await scores.pages(scoreId)) p.barCount];
    // 첫 묶음은 저장된 결과가 오고 둘째 묶음은 응답이 오지 않음
    var calls = 0;
    final api = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((req) async {
        if (++calls > 1) return Completer<http.Response>().future;
        return analysisResponse([for (var p = 1; p <= 8; p++) p]);
      }),
    );
    await openWithService(tester, AiAnalysisService(api, scores, settings, render: instantRender));
    await startAnalysis(tester);
    expect(calls, 2);
    expect(find.widgetWithText(OutlinedButton, '취소'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ScoreSettingsPage), findsNothing);
    expect([for (final p in await scores.pages(scoreId)) p.barCount], before);
    expect(jsonDecode((await settings.get('ai_batch_$scoreId'))!)['id'], 'b-1');
    // 버려진 요청의 응답 한도 타이머를 흘려보냄
    await tester.pump(kAnalyzeTimeout);
  });

  testWidgets('그림으로 바꾸는 중 취소하면 화면에 남아 멈춤을 알리고 요청 없이 묶음 기록을 둠', (tester) async {
    wallet.setBalance(16);
    final settings = SettingsRepo(db);
    var calls = 0;
    final api = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((req) async {
        calls++;
        return analysisResponse([for (var p = 1; p <= 8; p++) p]);
      }),
    );
    await openWithService(
      tester,
      AiAnalysisService(
        api,
        ScoreRepo(db),
        settings,
        // 끝나지 않는 렌더
        render: (path, indices, width, {onProgress}) =>
            Completer<List<({int index, Uint8List png})>>().future,
      ),
    );
    await startAnalysis(tester);
    expect(find.textContaining('악보를 그림으로 바꾸는 중'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '취소'));
    await tester.pumpAndSettle();
    expect(find.byType(ScoreSettingsPage), findsOneWidget, reason: '취소 버튼은 화면을 닫지 않음');
    // 일반 실패 알림('분석 실패: 분석을 멈춤')과 구분함
    expect(find.textContaining('분석을 멈춤. 다시 누르면'), findsOneWidget);
    expect(find.textContaining('분석 실패'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '취소'), findsNothing);
    expect(calls, 0);
    expect(await settings.get('ai_batch_$scoreId'), isNotNull, reason: '다시 누르면 같은 id로 이어받음');
  });

  testWidgets('분석 중 화면 라우트가 걷히면 분석을 멈추고 늦게 온 결과를 반영하지 않음', (tester) async {
    wallet.setBalance(16);
    final settings = SettingsRepo(db);
    final scores = ScoreRepo(db);
    final before = [for (final p in await scores.pages(scoreId)) p.barCount];
    // 응답은 gate가 풀린 뒤에야 옴. 보낸 쪽을 모두 7마디로 읽은 결과
    final gate = Completer<void>();
    final api = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((req) async {
        await gate.future;
        final sent = (jsonDecode(req.body) as Map<String, dynamic>)['pages'] as List;
        return analysisResponse([for (final p in sent) (p['index'] as int) + 1]);
      }),
    );
    final route = await openWithService(
      tester,
      AiAnalysisService(api, scores, settings, render: instantRender),
    );
    await startAnalysis(tester);
    expect(find.widgetWithText(OutlinedButton, '취소'), findsOneWidget);

    // 뒤로가기 막음을 거치지 않고 라우트가 걷히는 경우
    route.navigator!.removeRoute(route);
    await tester.pumpAndSettle();
    expect(find.byType(ScoreSettingsPage), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect([for (final p in await scores.pages(scoreId)) p.barCount], before);
    expect(await settings.get('ai_undo_$scoreId'), isNull);
    expect(await settings.get('ai_batch_$scoreId'), isNotNull);
  });
}

/// 쪽마다 바로 1바이트 그림을 돌려주는 렌더.
Future<List<({int index, Uint8List png})>> instantRender(
  String path,
  List<int> indices,
  int width, {
  void Function(int done, int total)? onProgress,
}) async => [for (final i in indices) (index: i, png: Uint8List(1))];

/// pages(1부터 센 쪽)를 모두 7마디로 읽은 분석 응답.
http.Response analysisResponse(List<int> pages) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'pages': [
        for (final p in pages) {'page': p, 'bars': 7, 'confidence': 'high'},
      ],
      'bpmSource': 'none',
      'coinsSpent': pages.length,
      'balance': 8,
    }),
  ),
  200,
);
