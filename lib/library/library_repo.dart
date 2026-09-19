// 라이브러리 트리 조작. 폴더 이동·삭제는 하위 전체에 영향을 주므로 재귀 CTE로 한 번에 처리함.
// 삭제는 파일을 지우지 않고 deletedAt만 찍음. 목록은 drift 감시 쿼리라 어디서 바꾸든 화면이 따라옴.

import 'dart:io';

import 'package:drift/drift.dart';

import '../core/db/database.dart';
import '../core/db/tables.dart';
import '../core/storage/paths.dart';

/// 휴지통에 둔 항목을 자동으로 지우기까지의 기간.
const kTrashRetention = Duration(days: 30);

/// ?1 노드에서 시작해 휴지통에 든 노드만 따라 내려간 집합(sub). 살아 있는 노드에서 멈춤.
const _trashedSubtree =
    'WITH RECURSIVE sub(id) AS ('
    '  SELECT id FROM nodes WHERE id = ?1 AND deleted_at IS NOT NULL'
    '  UNION'
    '  SELECT n.id FROM nodes n JOIN sub ON n.parent_id = sub.id WHERE n.deleted_at IS NOT NULL'
    ')';

/// 숫자 덩어리와 나머지 덩어리. ASCII 숫자만 숫자로 봄.
final _nameChunk = RegExp(r'\d+|\D+');

/// 사람이 기대하는 이름 순서. 숫자 덩어리는 크기로, 나머지는 대소문자를 무시하고 비교함.
/// '연습곡 2'가 '연습곡 10'보다, 'bach'가 'Chopin'보다 앞에 옴.
int compareNatural(String a, String b) {
  final x = _nameChunk.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final y = _nameChunk.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final c = _compareChunk(x[i], y[i]);
    if (c != 0) return c;
  }
  if (x.length != y.length) return x.length.compareTo(y.length);
  // 대소문자만 다른 이름도 순서가 늘 같게 함
  return a.compareTo(b);
}

/// 덩어리 하나를 비교함. 둘 다 숫자면 앞의 0을 떼고 자릿수·값 순으로 봐서 긴 숫자도 넘치지 않음.
int _compareChunk(String x, String y) {
  if (!_isDigits(x) || !_isDigits(y)) return x.compareTo(y);
  final xs = x.replaceFirst(RegExp(r'^0+'), '');
  final ys = y.replaceFirst(RegExp(r'^0+'), '');
  if (xs.length != ys.length) return xs.length.compareTo(ys.length);
  final c = xs.compareTo(ys);
  return c != 0 ? c : x.length.compareTo(y.length);
}

/// 덩어리가 숫자인지. 덩어리는 전부 숫자이거나 전부 아니므로 첫 글자만 봄.
bool _isDigits(String chunk) => _leadingDigit.hasMatch(chunk);

final _leadingDigit = RegExp(r'^\d');

class LibraryRepo {
  LibraryRepo(this.db);

  final BatonDatabase db;

  /// 한 폴더의 자식 목록. parentId가 null이면 루트. 휴지통 항목은 제외하고 폴더를 먼저 둠.
  Future<List<Node>> children(int? parentId) async => _sorted(await _childrenQuery(parentId).get());

  /// [children]을 감시함. 노드가 바뀔 때마다(다른 화면의 되살리기·가져오기 포함) 새 목록을 냄.
  Stream<List<Node>> watchChildren(int? parentId) => _childrenQuery(parentId).watch().map(_sorted);

  /// 자식 목록 쿼리. 정렬은 이름을 자연 순서로 비교해야 해서 [_sorted]가 맡음.
  SimpleSelectStatement<$NodesTable, Node> _childrenQuery(int? parentId) => db.select(db.nodes)
    ..where((n) => parentId == null ? n.parentId.isNull() : n.parentId.equals(parentId))
    ..where((n) => n.deletedAt.isNull());

  /// 폴더 먼저, 그다음 sortIndex, 이름은 자연 순서. drift 스트림이 캐시한 목록을 건드리지 않게 복사함.
  List<Node> _sorted(List<Node> nodes) => [...nodes]
    ..sort((a, b) {
      final kind = a.kind.index.compareTo(b.kind.index);
      if (kind != 0) return kind;
      final index = a.sortIndex.compareTo(b.sortIndex);
      if (index != 0) return index;
      return compareNatural(a.name, b.name);
    });

  /// 노드 하나. 없으면 null.
  Future<Node?> node(int id) =>
      (db.select(db.nodes)..where((n) => n.id.equals(id))).getSingleOrNull();

  /// 노드와 조상이 모두 휴지통 밖에 있는지. null(루트)은 늘 살아 있음. 지워진 노드는 죽은 것으로 봄.
  Future<bool> isAlive(int? id) async => id == null || await _aliveQuery(id).getSingle();

  /// [isAlive]를 감시함. 폴더 화면이 자기 폴더가 휴지통으로 간 것을 알아채는 데 씀.
  Stream<bool> watchAlive(int id) => _aliveQuery(id).watchSingle();

  /// 위로 거슬러 올라가며 휴지통에 든 조상이 있는지 셈. UNION이라 데이터가 순환해도 멈춤.
  Selectable<bool> _aliveQuery(int id) => db
      .customSelect(
        'WITH RECURSIVE up(id, parent_id, deleted_at) AS ('
        '  SELECT id, parent_id, deleted_at FROM nodes WHERE id = ?1'
        '  UNION'
        '  SELECT n.id, n.parent_id, n.deleted_at FROM nodes n JOIN up ON n.id = up.parent_id'
        ') SELECT COUNT(*) > 0 AND COUNT(deleted_at) = 0 AS alive FROM up',
        variables: [Variable.withInt(id)],
        readsFrom: {db.nodes},
      )
      .map((r) => r.read<bool>('alive'));

  /// 폴더를 만들고 id를 돌려줌. 휴지통에 든 폴더 안에는 만들지 않음.
  /// 거기 만든 노드는 목록에도 휴지통에도 안 보이다가 부모와 함께 영구 삭제될 뻔함.
  Future<int> createFolder(String name, {int? parentId}) async {
    if (!await isAlive(parentId)) throw ArgumentError('휴지통에 있는 폴더 안에는 만들 수 없음');
    return db
        .into(db.nodes)
        .insert(
          NodesCompanion.insert(kind: NodeKind.folder, name: name, parentId: Value(parentId)),
        );
  }

  /// 이름을 바꾸고 updatedAt을 갱신함.
  Future<void> rename(int id, String name) async {
    await (db.update(db.nodes)..where((n) => n.id.equals(id))).write(
      NodesCompanion(name: Value(name), updatedAt: Value(DateTime.now())),
    );
  }

  /// 노드의 updatedAt을 올려 감시 중인 목록에 알림. 표지처럼 행 밖의 파일만 바뀌었을 때 씀.
  /// DateTime이 초 단위로 저장돼 같은 초 안에서는 값이 그대로일 수 있으므로 적어도 1초 올림.
  Future<void> touch(List<int> ids) async {
    if (ids.isEmpty) return;
    await db.customUpdate(
      "UPDATE nodes SET updated_at = MAX(updated_at + 1, CAST(strftime('%s', 'now') AS INTEGER)) "
      'WHERE id IN (${List.filled(ids.length, '?').join(', ')})',
      variables: [for (final id in ids) Variable.withInt(id)],
      updates: {db.nodes},
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
  /// 휴지통에 든 폴더로도 옮기지 않음. createFolder와 같은 이유.
  /// 옮길 수 없는 항목이 하나라도 있으면 전체를 거부해 부분 이동으로 어질러지지 않게 함.
  Future<void> move(List<int> ids, int? newParentId) async {
    if (!await isAlive(newParentId)) throw ArgumentError('휴지통에 있는 폴더로는 옮길 수 없음');
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
  /// restore·purge와 형태를 맞춤. 셋 다 customUpdate로 nodes 변경을 알려 감시 중인 목록이 따라오게 함.
  Future<void> moveToTrash(List<int> ids) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.transaction(() async {
      for (final id in ids) {
        await db.customUpdate(
          'WITH RECURSIVE sub(id) AS ('
          '  SELECT id FROM nodes WHERE id = ?1'
          '  UNION'
          '  SELECT n.id FROM nodes n JOIN sub ON n.parent_id = sub.id'
          ') UPDATE nodes SET deleted_at = ?2 '
          'WHERE id IN (SELECT id FROM sub) AND deleted_at IS NULL',
          variables: [Variable.withInt(id), Variable.withInt(now)],
          updates: {db.nodes},
        );
      }
    });
  }

  /// 휴지통에서 되살림. 부모나 그 조상이 아직 휴지통에 있으면 루트로 끌어올려 고아가 되지 않게 함.
  /// 같은 조작으로 버려진 것(삭제 시각이 같은 것)만 되살림. 따로 버린 항목은 그대로 둠.
  /// 두 갱신을 한 트랜잭션에 묶음. 사이에서 끊기면 부모는 휴지통인데 자식은 살아 있어
  /// 목록에도 휴지통에도 안 보이는 노드가 됨.
  Future<void> restore(List<int> ids) async {
    for (final id in ids) {
      await db.transaction(() async {
        final target = await node(id);
        if (target == null || target.deletedAt == null) return;
        final parentId = await isAlive(target.parentId) ? target.parentId : null;
        await db.customUpdate(
          'WITH RECURSIVE sub(id) AS ('
          '  SELECT id FROM nodes WHERE id = ?1'
          '  UNION'
          '  SELECT n.id FROM nodes n JOIN sub ON n.parent_id = sub.id'
          ') UPDATE nodes SET deleted_at = NULL '
          'WHERE id IN (SELECT id FROM sub) AND deleted_at = ?2',
          variables: [
            Variable.withInt(id),
            Variable.withInt(target.deletedAt!.millisecondsSinceEpoch ~/ 1000),
          ],
          updates: {db.nodes},
        );
        await (db.update(
          db.nodes,
        )..where((n) => n.id.equals(id))).write(NodesCompanion(parentId: Value(parentId)));
      });
    }
  }

  /// 휴지통 항목을 하위까지 완전히 지움. 악보 파일 디렉토리도 함께 지움.
  /// 되돌릴 수 없으므로 호출자가 먼저 확인을 받아야 함.
  /// 휴지통에 든 노드만 지움. 그 아래에 살아 있는 노드가 섞여 있으면(예: 휴지통에 간 폴더 안에
  /// 나중에 들인 악보) 루트로 올려 살림. 그대로 지우면 사용자가 버린 적 없는 악보가 조용히 사라짐.
  Future<void> purge(List<int> ids) async {
    for (final id in ids) {
      final rows = await db
          .customSelect('$_trashedSubtree SELECT id FROM sub', variables: [Variable.withInt(id)])
          .get();
      // 행을 먼저 지우면 파일 삭제가 실패했을 때 어느 디렉토리가 남았는지 알 수 없음
      for (final r in rows) {
        final dir = Directory(AppPaths.abs(AppPaths.scoreDir(r.read<int>('id'))));
        if (await dir.exists()) await dir.delete(recursive: true);
      }
      // 부모가 자식보다 먼저 지워지면 parent_id 외래키에 걸림.
      // 한 트랜잭션 안에서 순서를 신경 쓰지 않도록 검사를 커밋 시점으로 미룸
      await db.transaction(() async {
        await db.customStatement('PRAGMA defer_foreign_keys = ON');
        await db.customUpdate(
          '$_trashedSubtree UPDATE nodes SET parent_id = NULL '
          'WHERE deleted_at IS NULL AND parent_id IN (SELECT id FROM sub)',
          variables: [Variable.withInt(id)],
          updates: {db.nodes},
        );
        await db.customUpdate(
          '$_trashedSubtree DELETE FROM nodes WHERE id IN (SELECT id FROM sub)',
          variables: [Variable.withInt(id)],
          updates: {db.nodes},
          updateKind: UpdateKind.delete,
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
  Future<List<Node>> trash() => _trashQuery().get();

  /// [trash]를 감시함. 되살리기·영구 삭제 뒤 휴지통 화면이 따로 다시 읽지 않아도 됨.
  Stream<List<Node>> watchTrash() => _trashQuery().watch();

  /// 부모가 살아 있거나 없는 삭제 노드. 최근에 버린 것부터.
  Selectable<Node> _trashQuery() => db
      .customSelect(
        'SELECT n.* FROM nodes n '
        'LEFT JOIN nodes p ON n.parent_id = p.id '
        'WHERE n.deleted_at IS NOT NULL AND (p.id IS NULL OR p.deleted_at IS NULL) '
        'ORDER BY n.deleted_at DESC',
        readsFrom: {db.nodes},
      )
      .map((r) => db.nodes.map(r.data));

  /// 이름으로 검색함. 휴지통은 제외. 이름은 자연 순서.
  Future<List<Node>> search(String query) async => _byName(await _searchQuery(query).get());

  /// [search]를 감시함.
  Stream<List<Node>> watchSearch(String query) => _searchQuery(query).watch().map(_byName);

  /// 검색 쿼리. 너무 흔한 검색어로 목록이 끝없이 길어지지 않게 자름.
  SimpleSelectStatement<$NodesTable, Node> _searchQuery(String query) => db.select(db.nodes)
    ..where((n) => n.name.like('%$query%') & n.deletedAt.isNull())
    ..orderBy([(n) => OrderingTerm(expression: n.name)])
    ..limit(200);

  /// 이름만 자연 순서로 정렬한 사본.
  List<Node> _byName(List<Node> nodes) =>
      [...nodes]..sort((a, b) => compareNatural(a.name, b.name));

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
