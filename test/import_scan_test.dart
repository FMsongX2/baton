// 라이브러리 화면의 스캔 가져오기 뒷정리 검증. 취소·실패한 스캔은 저장소를 비우고, 되찾은 스캔은
// '버리기'를 고르기 전까지 지우지 않는지 고정함.

import 'package:baton/core/db/database.dart';
import 'package:baton/core/providers.dart';
import 'package:baton/library/library_page.dart';
import 'package:baton/score/import/import_sources.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('cunning_document_scanner');
  late BatonDatabase db;
  late List<String> calls;

  setUp(() {
    db = BatonDatabase.forTesting(NativeDatabase.memory());
    calls = [];
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
    await db.close();
  });

  /// 스캐너 채널을 가짜로 물림. getPictures는 scan이 정하고, 부른 메서드 이름을 calls에 남김.
  void fakeScanner(Future<Object?> Function() scan) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls.add(call.method);
        return call.method == 'getPictures' ? scan() : null;
      },
    );
  }

  /// 루트 라이브러리를 띄우고 가져오기 시트에서 스캔을 고름.
  Future<void> startScan(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 스캔'));
    await tester.pumpAndSettle();
  }

  /// drift가 감시를 닫을 때 거는 0초 타이머까지 흘려보냄.
  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('스캔을 취소해도 스캐너 저장소를 비움', (tester) async {
    fakeScanner(() async => null);
    await startScan(tester);
    expect(calls, ['getPictures', 'cleanCache'], reason: '폴백 스캐너는 취소해도 찍은 원본을 남김');
    await teardownTree(tester);
  });

  testWidgets('스캔이 실패해도 스캐너 저장소를 비우고 할 일을 알림', (tester) async {
    fakeScanner(() async => throw PlatformException(code: 'ERROR', message: 'save failed'));
    await startScan(tester);
    expect(calls, ['getPictures', 'cleanCache'], reason: '저장 도중 실패하면 옮긴 일부가 남음');
    expect(find.textContaining('스캔을 마치지 못함'), findsOneWidget);
    await teardownTree(tester);
  });

  testWidgets('되찾은 스캔의 이름 입력을 창 밖 탭·뒤로가기로 닫아도 버리지 않고 처음 물음으로 돌아감', (tester) async {
    fakeScanner(() async => null);
    const lost = LostImport(ImportSource.scan, ['DOCUMENT_SCAN_1_20260101_000000.jpg']);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          findLostImportProvider.overrideWithValue(() async => lost),
        ],
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
    final importButton = find.widgetWithText(FilledButton, '가져오기');

    await tester.tap(importButton);
    await tester.pumpAndSettle();
    expect(find.text('악보 이름'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('끝내지 못한 가져오기'), findsOneWidget, reason: '창 밖 탭은 버리기가 아님');

    await tester.tap(importButton);
    await tester.pumpAndSettle();
    await systemBack(tester);
    expect(find.text('악보 이름'), findsNothing);
    expect(find.text('끝내지 못한 가져오기'), findsOneWidget, reason: '뒤로가기도 버리기가 아님');
    expect(calls, isEmpty, reason: '스캐너 저장소를 비우면 되찾은 쪽이 사라짐');

    await tester.tap(find.text('버리기'));
    await tester.pumpAndSettle();
    expect(find.text('끝내지 못한 가져오기'), findsNothing);
    expect(calls, ['cleanCache']);
    await teardownTree(tester);
  });
}

/// 안드로이드 시스템 뒤로가기를 흉내 냄.
Future<void> systemBack(WidgetTester tester) async {
  final message = const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    message,
    (_) {},
  );
  await tester.pumpAndSettle();
}
