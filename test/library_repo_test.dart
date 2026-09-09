// 트리 조작 검증. 폴더를 자기 하위로 옮기면 트리가 통째로 끊겨 복구가 어려우므로 특히 고정해 둠.

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
}
