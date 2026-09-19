// 트리 조작 검증. 폴더를 자기 하위로 옮기면 트리가 통째로 끊겨 복구가 어려우므로 특히 고정해 둠.
// 휴지통 아래 살아 있는 노드가 영구 삭제에 휩쓸리지 않는지, 목록 감시가 변경을 따라오는지도 봄.

import 'dart:async';
import 'dart:io';

import 'package:baton/core/db/database.dart';
import 'package:baton/core/db/tables.dart';
import 'package:baton/library/library_repo.dart';
import 'package:baton/core/storage/paths.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BatonDatabase db;
  late LibraryRepo repo;
  late Directory docs;

  /// 부모를 검사하지 않고 노드를 바로 넣음. 예전 버전이 남긴 휴지통 밑 고아를 흉내 낼 때 씀.
  Future<int> insertRaw(String name, {int? parentId, NodeKind kind = NodeKind.score}) => db
      .into(db.nodes)
      .insert(NodesCompanion.insert(kind: kind, name: name, parentId: Value(parentId)));

  /// 감시 스트림의 다음 값. 변경 알림이 오지 않으면 멈추지 않고 실패하게 시간을 둠.
  Future<T> next<T>(StreamIterator<T> it) async {
    expect(await it.moveNext().timeout(const Duration(seconds: 2)), isTrue);
    return it.current;
  }

  setUp(() {
    db = BatonDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepo(db);
    docs = Directory.systemTemp.createTempSync('baton-lib-test');
    AppPaths.overrideDocuments(docs);
  });

  tearDown(() async {
    await db.close();
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  test('폴더를 만들고 부모별로 조회함', () async {
    final a = await repo.createFolder('클래식');
    await repo.createFolder('바흐', parentId: a);
    await repo.createFolder('재즈');

    final root = await repo.children(null);
    expect(root.map((n) => n.name), ['재즈', '클래식']);
    final inA = await repo.children(a);
    expect(inA.single.name, '바흐');
  });

  test('이동은 parentId를 갈아끼움', () async {
    final a = await repo.createFolder('A');
    final b = await repo.createFolder('B');
    final c = await repo.createFolder('C', parentId: a);

    await repo.move([c], b);
    expect((await repo.children(a)), isEmpty);
    expect((await repo.children(b)).single.id, c);
  });

  test('자기 자신 안으로는 옮길 수 없음', () async {
    final a = await repo.createFolder('A');
    expect(() => repo.move([a], a), throwsArgumentError);
  });

  test('자기 하위로는 옮길 수 없음', () async {
    final a = await repo.createFolder('A');
    final b = await repo.createFolder('B', parentId: a);
    final c = await repo.createFolder('C', parentId: b);

    expect(() => repo.move([a], b), throwsArgumentError);
    expect(() => repo.move([a], c), throwsArgumentError, reason: '손자도 자손');
    // 거부된 뒤에도 트리가 그대로여야 함
    expect((await repo.children(a)).single.id, b);
  });

  test('루트로 끌어올리는 이동은 허용됨', () async {
    final a = await repo.createFolder('A');
    final b = await repo.createFolder('B', parentId: a);
    await repo.move([b], null);
    expect((await repo.children(null)).map((n) => n.name), ['A', 'B']);
  });

  test('삭제는 하위 전체를 휴지통으로 보냄', () async {
    final a = await repo.createFolder('A');
    final b = await repo.createFolder('B', parentId: a);
    await repo.createFolder('C', parentId: b);

    await repo.moveToTrash([a]);
    expect(await repo.children(null), isEmpty);
    expect(await repo.children(a), isEmpty);
    final t = await repo.trash();
    expect(t.single.name, 'A', reason: '휴지통에는 삭제의 뿌리만 보임');
  });

  test('복원은 하위까지 되살림', () async {
    final a = await repo.createFolder('A');
    final b = await repo.createFolder('B', parentId: a);
    await repo.moveToTrash([a]);
    await repo.restore([a]);

    expect((await repo.children(null)).single.id, a);
    expect((await repo.children(a)).single.id, b);
    expect(await repo.trash(), isEmpty);
  });

  test('부모가 아직 휴지통이면 복원 대상은 루트로 올라감', () async {
    final a = await repo.createFolder('A');
    final b = await repo.createFolder('B', parentId: a);
    await repo.moveToTrash([a]);
    await repo.restore([b]);

    final root = await repo.children(null);
    expect(root.single.id, b, reason: '부모가 죽어 있으면 고아가 되지 않게 루트로');
  });

  test('검색은 휴지통을 빼고 이름으로 찾음', () async {
    await repo.createFolder('바흐 무반주');
    final j = await repo.createFolder('바흐 인벤션');
    await repo.moveToTrash([j]);

    final hits = await repo.search('바흐');
    expect(hits.map((n) => n.name), ['바흐 무반주']);
  });

  test('경로는 루트부터 대상까지 순서대로', () async {
    final a = await repo.createFolder('A');
    final b = await repo.createFolder('B', parentId: a);
    final c = await repo.createFolder('C', parentId: b);
    expect((await repo.pathTo(c)).map((n) => n.name), ['A', 'B', 'C']);
  });

  test('이름 변경이 반영됨', () async {
    final a = await repo.createFolder('옛이름');
    await repo.rename(a, '새이름');
    expect((await repo.children(null)).single.name, '새이름');
  });

  test('폴더가 악보보다 먼저 나옴', () async {
    await db.into(db.nodes).insert(NodesCompanion.insert(kind: NodeKind.score, name: 'aaa 악보'));
    await repo.createFolder('zzz 폴더');
    final root = await repo.children(null);
    expect(root.map((n) => n.kind), [NodeKind.folder, NodeKind.score]);
  });

  test('영구 삭제는 하위 노드와 악보 파일까지 함께 지움', () async {
    final folder = await repo.createFolder('공연');
    final score = await db
        .into(db.nodes)
        .insert(NodesCompanion.insert(kind: NodeKind.score, name: '곡', parentId: Value(folder)));
    final dir = await AppPaths.ensureScoreDir(score);
    await File(AppPaths.abs(AppPaths.sourcePdf(score))).writeAsString('pdf');

    await repo.moveToTrash([folder]);
    await repo.purge([folder]);

    expect(await repo.trash(), isEmpty);
    expect(await repo.children(null), isEmpty);
    expect(dir.existsSync(), isFalse);
  });

  test('휴지통에 넣은 시각이 지금으로 읽힘', () async {
    final id = await repo.createFolder('임시');
    await repo.moveToTrash([id]);
    final deleted = (await repo.trash()).single.deletedAt!;
    expect(DateTime.now().difference(deleted).inMinutes.abs(), lessThan(1));
  });

  test('보관 기간이 지난 것만 자동으로 지움', () async {
    final old = await repo.createFolder('옛날');
    await repo.createFolder('최근');
    await repo.moveToTrash([old]);
    await repo.moveToTrash([2]);

    // 기한이 지난 쪽만 골라 지우는지 보려고 삭제 시각을 과거로 돌림
    await db.customStatement('UPDATE nodes SET deleted_at = ? WHERE id = ?', [
      DateTime.now().subtract(kTrashRetention + const Duration(days: 1)).millisecondsSinceEpoch ~/
          1000,
      old,
    ]);

    expect(await repo.purgeExpired(), 1);
    expect((await repo.trash()).single.name, '최근');
  });

  test('이름은 숫자 크기와 대소문자를 무시한 자연 순서로 정렬함', () async {
    for (final name in ['연습곡 10', '연습곡 2', 'Chopin', '연습곡 1', 'bach', 'Op. 10', 'Op. 9']) {
      await insertRaw(name);
    }
    await repo.createFolder('폴더');
    final names = (await repo.children(null)).map((n) => n.name).toList();
    expect(names, ['폴더', 'bach', 'Chopin', 'Op. 9', 'Op. 10', '연습곡 1', '연습곡 2', '연습곡 10']);
    expect((await repo.search('연습곡')).map((n) => n.name), ['연습곡 1', '연습곡 2', '연습곡 10']);
  });

  test('자연 정렬은 앞자리 0과 긴 숫자도 크기로 비교함', () {
    expect(compareNatural('track 007', 'track 10'), lessThan(0));
    expect(compareNatural('a 99999999999999999999', 'a 100000000000000000000'), lessThan(0));
    expect(compareNatural('a1', 'a01'), isNot(0), reason: '다른 이름이 같은 자리로 섞이지 않음');
    expect(compareNatural('Bach', 'bach'), isNot(0));
  });

  test('휴지통에 든 폴더 안으로는 만들거나 옮기지 못함', () async {
    final a = await repo.createFolder('A');
    final b = await repo.createFolder('B', parentId: a);
    final c = await repo.createFolder('C');
    await repo.moveToTrash([a]);

    expect(await repo.isAlive(b), isFalse, reason: '조상이 휴지통이면 죽은 것');
    await expectLater(repo.createFolder('새', parentId: a), throwsArgumentError);
    await expectLater(repo.createFolder('새', parentId: b), throwsArgumentError);
    await expectLater(repo.move([c], b), throwsArgumentError);
    expect(await repo.isAlive(c), isTrue);
  });

  test('영구 삭제는 휴지통 밑에 섞인 살아 있는 악보를 루트로 올리고 파일을 남김', () async {
    final folder = await repo.createFolder('쇼팽');
    final old = await insertRaw('버린 곡', parentId: folder);
    await repo.moveToTrash([folder]);
    // 폴더가 휴지통에 간 뒤 그 안에 들어온 악보. 사용자는 버린 적이 없음
    final alive = await insertRaw('나중에 들인 곡', parentId: folder);
    await AppPaths.ensureScoreDir(alive);
    await File(AppPaths.abs(AppPaths.sourcePdf(alive))).writeAsString('pdf');
    final oldDir = await AppPaths.ensureScoreDir(old);

    await repo.purge([folder]);

    expect((await repo.children(null)).single.id, alive);
    expect(File(AppPaths.abs(AppPaths.sourcePdf(alive))).existsSync(), isTrue);
    expect(oldDir.existsSync(), isFalse);
    expect(await repo.trash(), isEmpty);
  });

  test('영구 삭제는 살아 있는 노드 밑에서 따로 버린 것까지 지우지 않음', () async {
    final folder = await repo.createFolder('F');
    await repo.moveToTrash([folder]);
    final alive = await insertRaw('G', parentId: folder, kind: NodeKind.folder);
    final trashedLater = await insertRaw('H', parentId: alive);
    await repo.moveToTrash([trashedLater]);

    await repo.purge([folder]);

    expect((await repo.children(null)).single.id, alive);
    expect((await repo.trash()).single.id, trashedLater, reason: 'H는 G 밑 휴지통으로 남음');
  });

  test('되살릴 때 조상 어디든 휴지통이면 루트로 올림', () async {
    final a = await repo.createFolder('A');
    final b = await repo.createFolder('B', parentId: a);
    final c = await repo.createFolder('C', parentId: b);
    await repo.moveToTrash([c]);
    await repo.moveToTrash([a]);
    // 예전 버전이 남긴 상태: B만 살아 있고 A는 휴지통
    await db.customStatement('UPDATE nodes SET deleted_at = NULL WHERE id = ?', [b]);

    await repo.restore([c]);
    expect((await repo.children(null)).map((n) => n.id), contains(c));
  });

  test('다른 화면에서 되살리거나 지워도 목록 감시가 따라옴', () async {
    final a = await repo.createFolder('A');
    await repo.moveToTrash([a]);
    final list = StreamIterator(repo.watchChildren(null));
    final trash = StreamIterator(repo.watchTrash());
    expect(await next(list), isEmpty);
    expect((await next(trash)).single.id, a);

    await repo.restore([a]);
    expect((await next(list)).single.id, a);
    expect(await next(trash), isEmpty);

    await repo.moveToTrash([a]);
    expect(await next(list), isEmpty);
    expect((await next(trash)).single.id, a);

    await repo.purge([a]);
    expect(await next(trash), isEmpty);
    await list.cancel();
    await trash.cancel();
  });

  test('touch는 만든 직후 같은 초 안에 불러도 updatedAt을 바꿔 목록 감시에 알림', () async {
    final a = await insertRaw('A');
    final b = await insertRaw('B');
    final list = StreamIterator(repo.watchChildren(null));
    final before = {for (final n in await next(list)) n.id: n.updatedAt};

    await repo.touch([a]);
    final after = {for (final n in await next(list)) n.id: n.updatedAt};
    expect(after[a]!.isAfter(before[a]!), isTrue, reason: '같으면 칸이 표지를 다시 찾지 않음');
    expect(after[b], before[b]);
    await list.cancel();
  });

  test('폴더 생존 감시는 조상이 휴지통으로 가면 false를 냄', () async {
    final a = await repo.createFolder('A');
    final b = await repo.createFolder('B', parentId: a);
    final alive = StreamIterator(repo.watchAlive(b));
    expect(await next(alive), isTrue);
    await repo.moveToTrash([a]);
    expect(await next(alive), isFalse);
    await alive.cancel();
  });
}
