// 라이브러리 화면의 수명 검증. 칸이 다른 노드를 받거나 표지 파일이 바뀔 때, 가져오는 중일 때 표지가 따라오는지,
// 선택 중 뒤로가기와 보고 있던 폴더가 휴지통으로 갔을 때 화면, 여러 파일 가져오기가 끝까지 도는지 봄.

import 'dart:io';

import 'package:baton/core/db/database.dart';
import 'package:baton/core/db/tables.dart';
import 'package:baton/core/providers.dart';
import 'package:baton/core/storage/paths.dart';
import 'package:baton/library/library_page.dart';
import 'package:baton/library/library_repo.dart';
import 'package:baton/library/score_tile.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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

/// 테스트용 노드. 필요한 값만 받음.
Node node(int id, NodeKind kind, String name, {DateTime? updatedAt}) => Node(
  id: id,
  kind: kind,
  name: name,
  sortIndex: 0,
  createdAt: DateTime(2026),
  updatedAt: updatedAt ?? DateTime(2026),
);

/// 격자 밖에서 칸 하나만 띄움. 같은 자리에 노드만 바꿔 끼우면 State가 이어짐.
Widget tileApp(Node n, {DateTime? importStartedAt}) => MaterialApp(
  home: Scaffold(
    body: ScoreTile(
      node: n,
      selected: false,
      selectionMode: false,
      onTap: () {},
      onLongPress: () {},
      importStartedAt: importStartedAt,
    ),
  ),
);

/// 칸이 파일을 찾는 진짜 비동기 입출력을 흘려보낸 뒤 다시 그림.
/// 입출력이 차례로 이어지므로 한 번씩 끝낼 때마다 가짜 시계 쪽 이어짐을 풀어 줌.
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
}

void main() {
  test('여러 파일 중 하나가 실패해도 나머지를 끝까지 가져옴', () async {
    final result = await runEach([
      () async => 1,
      () async => throw const FormatException('암호 PDF'),
      () async => 3,
    ]);
    expect(result.ids, [1, 3]);
    expect(result.errors.single, isA<FormatException>());
  });

  group('칸 표지', () {
    late File thumb;
    final png = File(p.join('test', 'fixtures', 'portrait_100x200.png'));

    setUp(() {
      final docs = Directory.systemTemp.createTempSync('baton-tile-test');
      addTearDown(() => docs.deleteSync(recursive: true));
      AppPaths.overrideDocuments(docs);
      thumb = File(AppPaths.abs(AppPaths.thumbnail(2)));
    });

    testWidgets('칸이 다른 노드를 받으면 앞 노드의 상태를 버리고 썸네일을 다시 찾음', (tester) async {
      thumb
        ..createSync(recursive: true)
        ..writeAsBytesSync(png.readAsBytesSync());
      // 같은 자리에 노드만 바꿔 끼움. 키 없이 재사용되던 예전 격자와 같은 조건
      await tester.pumpWidget(tileApp(node(1, NodeKind.folder, '폴더')));
      await tester.pumpWidget(tileApp(node(2, NodeKind.score, '악보')));
      await settleIo(tester);

      expect(find.byType(Image), findsOneWidget, reason: '폴더였던 칸도 악보 표지를 찾아 스피너에 머물지 않음');
    });

    testWidgets('가져오는 중인 행은 표지를 만들지 않고 기다리다 touch되면 찾음', (tester) async {
      // 행만 먼저 생긴 순간. 가져오기가 아직 PDF를 옮기는 중이라 칸이 만들어 보면 실패하거나 겹쳐 렌더함
      File(AppPaths.abs(AppPaths.sourcePdf(2)))
        ..createSync(recursive: true)
        ..writeAsStringSync('쓰는 중');
      final since = DateTime(2026);
      await tester.pumpWidget(tileApp(node(2, NodeKind.score, '악보'), importStartedAt: since));
      await settleIo(tester);
      expect(find.byIcon(Icons.description_outlined), findsNothing, reason: '실패로 그리지 않음');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      thumb
        ..createSync(recursive: true)
        ..writeAsBytesSync(png.readAsBytesSync());
      final touched = node(2, NodeKind.score, '악보', updatedAt: DateTime(2027));
      await tester.pumpWidget(tileApp(touched, importStartedAt: since));
      await settleIo(tester);
      expect(find.byType(Image), findsOneWidget, reason: '가져오기가 끝났다는 신호를 받으면 다시 찾아야 함');
    });

    testWidgets('가져오기 전에 생긴 표지 없는 악보는 가져오는 동안에도 칸이 직접 만들어 봄', (tester) async {
      // PDF가 없어 만들기에 실패하고 실패 그림이 됨. 가져오는 중으로 보면 스피너에 머묾
      final later = DateTime(2027);
      await tester.pumpWidget(tileApp(node(2, NodeKind.score, '악보'), importStartedAt: later));
      await settleIo(tester);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    });

    testWidgets('touch 없이 가져오기가 끝나도 만드는 중에 머물지 않음', (tester) async {
      final since = DateTime(2026);
      await tester.pumpWidget(tileApp(node(2, NodeKind.score, '악보'), importStartedAt: since));
      await settleIo(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(tileApp(node(2, NodeKind.score, '악보')));
      await settleIo(tester);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    });

    testWidgets('실패로 확정된 칸은 가져오기가 끝나도 다시 찾지 않음', (tester) async {
      // 가져오기 전에 생긴 행. PDF가 없어 실패로 확정됨
      await tester.pumpWidget(
        tileApp(node(2, NodeKind.score, '악보'), importStartedAt: DateTime(2027)),
      );
      await settleIo(tester);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);

      // 다시 찾는지 가리는 표식. 다시 찾으면 이 표지를 집어 그림으로 바뀜
      thumb
        ..createSync(recursive: true)
        ..writeAsBytesSync(png.readAsBytesSync());
      await tester.pumpWidget(tileApp(node(2, NodeKind.score, '악보')));
      await settleIo(tester);
      expect(find.byType(Image), findsNothing, reason: '다시 찾으면 깨진 PDF를 가져오기마다 렌더함');
    });

    testWidgets('가져오기 시작과 같은 초에 생긴 행도 가져오는 중으로 봄', (tester) async {
      // 생성 시각은 초 단위로 저장됨. 시작 시각을 내리지 않으면 이 행을 전부터 있던 행으로 봄
      final since = DateTime(2026, 1, 1, 0, 0, 0, 700);
      await tester.pumpWidget(tileApp(node(2, NodeKind.score, '악보'), importStartedAt: since));
      await settleIo(tester);
      expect(find.byIcon(Icons.description_outlined), findsNothing, reason: '실패로 그리지 않음');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('표지 파일이 바뀐 경우에만 그림을 새로 읽음', (tester) async {
      thumb
        ..createSync(recursive: true)
        ..writeAsBytesSync(png.readAsBytesSync())
        ..setLastModifiedSync(DateTime(2026));
      await tester.pumpWidget(tileApp(node(2, NodeKind.score, '악보')));
      await settleIo(tester);
      Key? imageKey() => tester.widget<Image>(find.byType(Image)).key;
      final first = imageKey();

      // 이름만 바뀜. 파일은 그대로라 이미 받은 그림을 계속 씀
      await tester.pumpWidget(tileApp(node(2, NodeKind.score, '새 이름', updatedAt: DateTime(2027))));
      await settleIo(tester);
      expect(imageKey(), first);

      // 회전으로 표지를 다시 만듦. 같은 경로라 새로 읽지 않으면 옛 그림이 남음
      thumb.setLastModifiedSync(DateTime(2028));
      await tester.pumpWidget(tileApp(node(2, NodeKind.score, '새 이름', updatedAt: DateTime(2028))));
      await settleIo(tester);
      expect(imageKey(), isNot(first));
    });
  });

  group('화면', () {
    late BatonDatabase db;
    late LibraryRepo repo;

    setUp(() {
      db = BatonDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepo(db);
    });

    tearDown(() => db.close());

    /// 메모리 DB를 물린 앱을 띄움.
    Future<void> launch(WidgetTester tester, Widget home) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(home: home),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// drift가 감시를 닫을 때 거는 0초 타이머까지 흘려보냄. 시간을 넘기지 않는 pump로는 안 돎.
    Future<void> teardownTree(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    }

    /// DB 조작을 가짜 시계 안에서 돌림. drift 감시가 같은 영역에 있어 진짜 비동기로 돌리면 서로 기다림.
    Future<T> inFakeZone<T>(WidgetTester tester, Future<T> Function() action) async {
      final future = action();
      await tester.pumpAndSettle();
      return future;
    }

    testWidgets('앞 칸이 빠져도 뒤 칸의 상태는 새로 만들지 않고 옮김', (tester) async {
      final a = await inFakeZone(tester, () => repo.createFolder('A'));
      await inFakeZone(tester, () => repo.createFolder('B'));
      await launch(tester, const LibraryPage());
      State<StatefulWidget> tileOf(String name) =>
          tester.state(find.ancestor(of: find.text(name), matching: find.byType(ScoreTile)));
      final before = tileOf('B');

      await inFakeZone(tester, () => repo.moveToTrash([a]));
      expect(find.text('A'), findsNothing);
      expect(identical(tileOf('B'), before), isTrue, reason: '새로 만들면 칸마다 표지를 다시 찾으며 깜빡임');
      await teardownTree(tester);
    });

    testWidgets('선택 중 뒤로가기는 화면을 닫지 않고 선택만 풂', (tester) async {
      await inFakeZone(tester, () => repo.createFolder('A'));
      await launch(tester, const LibraryPage());
      await tester.longPress(find.text('A'));
      await tester.pumpAndSettle();
      expect(find.text('1개 선택'), findsOneWidget);

      await systemBack(tester);
      expect(find.text('1개 선택'), findsNothing);
      expect(find.byType(LibraryPage), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('보고 있던 폴더가 휴지통으로 가면 그 화면을 닫음', (tester) async {
      final folder = await inFakeZone(tester, () => repo.createFolder('F'));
      await launch(tester, const Text('root'));
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => LibraryPage(folderId: folder, title: 'F'),
            ),
          );
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsOneWidget);

      await inFakeZone(tester, () => repo.moveToTrash([folder]));
      expect(find.byType(LibraryPage), findsNothing, reason: '남아 있으면 휴지통 폴더에 악보를 들이게 됨');
      expect(find.text('root'), findsOneWidget);
      await teardownTree(tester);
    });
  });
}
