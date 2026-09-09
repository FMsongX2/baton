// 라이브러리 트리 조작. 폴더 이동·삭제는 하위 전체에 영향을 주므로 재귀 CTE로 한 번에 처리함.
// 삭제는 파일을 지우지 않고 deletedAt만 찍음. 실제 파일 정리는 purge에서 함.

import 'dart:io';

import 'package:drift/drift.dart';

import '../core/db/database.dart';
import '../core/db/tables.dart';
import '../core/storage/paths.dart';

/// 휴지통에 둔 항목을 자동으로 지우기까지의 기간.
const kTrashRetention = Duration(days: 30);

class LibraryRepo {
  LibraryRepo(this.db);

  final BatonDatabase db;

  /// 한 폴더의 자식 목록. parentId가 null이면 루트. 휴지통 항목은 제외하고 폴더를 먼저 둠.
  Future<List<Node>> children(int? parentId) {
    final q = db.select(db.nodes)
      ..where((n) => parentId == null ? n.parentId.isNull() : n.parentId.equals(parentId))
      ..where((n) => n.deletedAt.isNull())
      ..orderBy([
        (n) => OrderingTerm(expression: n.kind),
        (n) => OrderingTerm(expression: n.sortIndex),
        (n) => OrderingTerm(expression: n.name),
      ]);
    return q.get();
  }

  /// 폴더를 만들고 id를 돌려줌.
  Future<int> createFolder(String name, {int? parentId}) => db
      .into(db.nodes)
      .insert(NodesCompanion.insert(kind: NodeKind.folder, name: name, parentId: Value(parentId)));

  /// 이름을 바꾸고 updatedAt을 갱신함.
  Future<void> rename(int id, String name) async {
    await (db.update(db.nodes)..where((n) => n.id.equals(id))).write(
      NodesCompanion(name: Value(name), updatedAt: Value(DateTime.now())),
    );
  }

  /// 노드와 그 하위 전부의 id. 자기 자신을 포함함.
  Future<Set<int>> descendantIds(int rootId) async {
    final rows = await db
        .customSelect(
          'WITH RECURSIVE sub(id) AS ('
          '  SELECT id FROM nodes WHERE id = ?1'
          '  UNION'
          '  SELECT n.id FROM nodes n JOIN sub ON n.parent_id = sub.id'
          ') SELECT id FROM sub',
          variables: [Variable.withInt(rootId)],
          readsFrom: {db.nodes},
        )
        .get();
    return rows.map((r) => r.read<int>('id')).toSet();
  }

  /// 노드들을 다른 폴더로 옮김. 자기 자신이나 자기 자손으로 옮기려 하면 트리가 끊기므로 막음.
  /// 옮길 수 없는 항목이 하나라도 있으면 전체를 거부해 부분 이동으로 어질러지지 않게 함.
  Future<void> move(List<int> ids, int? newParentId) async {
    if (newParentId != null) {
      for (final id in ids) {
        if (id == newParentId) {
          throw ArgumentError('폴더를 자기 자신 안으로 옮길 수 없음');
        }
        final sub = await descendantIds(id);
        if (sub.contains(newParentId)) {
          throw ArgumentError('폴더를 자기 하위로 옮길 수 없음');
        }
      }
    }
    await db.batch((b) {
      b.update(
        db.nodes,
        NodesCompanion(parentId: Value(newParentId), updatedAt: Value(DateTime.now())),
        where: (n) => n.id.isIn(ids),
      );
    });
  }

  /// 노드와 하위 전부를 휴지통으로 보냄.
  /// drift는 DateTime을 초 단위로 저장함. 밀리초를 넣으면 삭제 시각이 먼 미래로 읽혀
  /// 남은 보관 일수와 자동 정리가 둘 다 어긋남.
  /// 이미 휴지통에 있던 하위 항목의 시각은 건드리지 않음. 덮으면 사용자가 따로 버린 것이
  /// 부모를 되살릴 때 함께 살아나고 보관 기간도 다시 시작함.
  /// 여러 개를 한 번에 버리다 끊기면 일부만 휴지통에 가므로 한 트랜잭션으로 묶음.
  /// restore·purge와 형태를 맞춤.
  Future<void> moveToTrash(List<int> ids) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.transaction(() async {
      for (final id in ids) {
        await db.customStatement(
          'WITH RECURSIVE sub(id) AS ('
          '  SELECT id FROM nodes WHERE id = ?1'
          '  UNION'
          '  SELECT n.id FROM nodes n JOIN sub ON n.parent_id = sub.id'
          ') UPDATE nodes SET deleted_at = ?2 '
          'WHERE id IN (SELECT id FROM sub) AND deleted_at IS NULL',
          [id, now],
        );
      }
    });
  }

  /// 휴지통에서 되살림. 부모가 아직 휴지통에 있으면 루트로 끌어올려 고아가 되지 않게 함.
  /// 같은 조작으로 버려진 것(삭제 시각이 같은 것)만 되살림. 따로 버린 항목은 그대로 둠.
  /// 두 갱신을 한 트랜잭션에 묶음. 사이에서 끊기면 부모는 휴지통인데 자식은 살아 있어
  /// 목록에도 휴지통에도 안 보이는 노드가 됨.
  Future<void> restore(List<int> ids) async {
    for (final id in ids) {
      await db.transaction(() async {
        final node = await (db.select(db.nodes)..where((n) => n.id.equals(id))).getSingleOrNull();
        if (node == null || node.deletedAt == null) return;
        var parentId = node.parentId;
        if (parentId != null) {
          final parent = await (db.select(
            db.nodes,
          )..where((n) => n.id.equals(parentId!))).getSingleOrNull();
          if (parent == null || parent.deletedAt != null) parentId = null;
        }
        await db.customStatement(
          'WITH RECURSIVE sub(id) AS ('
          '  SELECT id FROM nodes WHERE id = ?1'
          '  UNION'
          '  SELECT n.id FROM nodes n JOIN sub ON n.parent_id = sub.id'
          ') UPDATE nodes SET deleted_at = NULL '
          'WHERE id IN (SELECT id FROM sub) AND deleted_at = ?2',
          [id, node.deletedAt!.millisecondsSinceEpoch ~/ 1000],
        );
        await (db.update(
          db.nodes,
        )..where((n) => n.id.equals(id))).write(NodesCompanion(parentId: Value(parentId)));
      });
    }
  }

  /// 휴지통 항목을 하위까지 완전히 지움. 악보 파일 디렉토리도 함께 지움.
  /// 되돌릴 수 없으므로 호출자가 먼저 확인을 받아야 함.
  Future<void> purge(List<int> ids) async {
    for (final id in ids) {
      final sub = await descendantIds(id);
      // 행을 먼저 지우면 파일 삭제가 실패했을 때 어느 디렉토리가 남았는지 알 수 없음
      for (final nodeId in sub) {
        final dir = Directory(AppPaths.abs(AppPaths.scoreDir(nodeId)));
        if (await dir.exists()) await dir.delete(recursive: true);
      }
      // 부모가 자식보다 먼저 지워지면 parent_id 외래키에 걸림.
      // 한 트랜잭션 안에서 순서를 신경 쓰지 않도록 검사를 커밋 시점으로 미룸
      await db.transaction(() async {
        await db.customStatement('PRAGMA defer_foreign_keys = ON');
        await db.customStatement(
          'WITH RECURSIVE sub(id) AS ('
          '  SELECT id FROM nodes WHERE id = ?1'
          '  UNION'
          '  SELECT n.id FROM nodes n JOIN sub ON n.parent_id = sub.id'
          ') DELETE FROM nodes WHERE id IN (SELECT id FROM sub)',
          [id],
        );
      });
    }
  }

  /// 보관 기간이 지난 휴지통 항목을 지움. 앱을 열 때 한 번 부름.
  /// 지운 항목 수를 돌려줌.
  Future<int> purgeExpired({DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(kTrashRetention);
    final expired = [
      for (final n in await trash())
        if (n.deletedAt != null && n.deletedAt!.isBefore(cutoff)) n.id,
    ];
    if (expired.isNotEmpty) await purge(expired);
    return expired.length;
  }

  /// 휴지통 목록. 하위 항목은 빼고 삭제의 뿌리만 보여줌.
  Future<List<Node>> trash() async {
    final rows = await db
        .customSelect(
          'SELECT n.* FROM nodes n '
          'LEFT JOIN nodes p ON n.parent_id = p.id '
          'WHERE n.deleted_at IS NOT NULL AND (p.id IS NULL OR p.deleted_at IS NULL) '
          'ORDER BY n.deleted_at DESC',
          readsFrom: {db.nodes},
        )
        .get();
    return rows.map((r) => db.nodes.map(r.data)).toList();
  }

  /// 이름으로 검색함. 휴지통은 제외.
  Future<List<Node>> search(String query) {
    final q = db.select(db.nodes)
      ..where((n) => n.name.like('%$query%') & n.deletedAt.isNull())
      ..orderBy([(n) => OrderingTerm(expression: n.name)])
      ..limit(200);
    return q.get();
  }

  /// 루트에서 해당 노드까지의 경로. 상단 breadcrumb에 씀.
  Future<List<Node>> pathTo(int id) async {
    final path = <Node>[];
    int? cur = id;
    // 데이터가 깨져 순환이 생겨도 멈추도록 방문한 id를 기록함
    final seen = <int>{};
    while (cur != null && seen.add(cur)) {
      final n = await (db.select(db.nodes)..where((t) => t.id.equals(cur!))).getSingleOrNull();
      if (n == null) break;
      path.insert(0, n);
      cur = n.parentId;
    }
    return path;
  }
}
