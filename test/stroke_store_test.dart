// 필기 캐시·되돌리기·저장 순서. 읽기가 끝나기 전의 저장이나 캐시를 버린 뒤의 저장이
// DB의 필기를 지우지 않는지를 고정함. 필기는 사용자가 만든 데이터라 지워지면 되살릴 수 없음.

import 'dart:async';

import 'package:baton/reader/annotation/stroke.dart';
import 'package:baton/reader/annotation/stroke_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 높이 y를 가로지르는 펜 획 하나.
Stroke _stroke(double y) => Stroke(
  tool: StrokeTool.pen,
  color: 0xFF000000,
  width: 0.003,
  points: [Offset(0.1, y), Offset(0.9, y)],
);

/// 읽기를 손으로 끝내고 저장 호출을 기록하는 가짜 저장소.
class _Db {
  final loads = <int, List<Completer<List<Stroke>>>>{};
  final saves = <({int page, List<Stroke> strokes})>[];
  Object? loadError;

  /// 읽기 요청을 남기고 끝낼 수 있는 Future를 돌려줌.
  Future<List<Stroke>> load(int page) {
    if (loadError != null) return Future.error(loadError!);
    final c = Completer<List<Stroke>>();
    (loads[page] ??= []).add(c);
    return c.future;
  }

  /// 저장할 때의 목록을 복사해 남김.
  Future<void> save(int page, List<Stroke> strokes) async {
    saves.add((page: page, strokes: List.of(strokes)));
  }
}

void main() {
  late _Db db;
  late StrokeStore store;
  final errors = <Object>[];

  setUp(() {
    db = _Db();
    errors.clear();
    store = StrokeStore(load: db.load, save: db.save, onSaveError: (_, e) => errors.add(e));
  });

  test('읽기 전에 받은 목록에도 읽어 온 획이 들어옴', () async {
    final a = _stroke(0.1);
    final list = store.of(3);
    db.loads[3]!.single.complete([a]);
    await pumpEventQueue();
    expect(list, [a]);
  });

  test('읽기가 끝나기 전에 그은 획을 저장해도 DB에 있던 획을 지우지 않음', () async {
    final a = _stroke(0.1);
    final s = _stroke(0.5);
    store.add(3, s);
    db.loads[3]!.single.complete([a]);
    await pumpEventQueue();
    expect(db.saves.single.strokes, [a, s]);
  });

  test('되돌리기와 다시 실행은 같은 획 객체를 한 번씩만 넣고 뺌', () async {
    final s = _stroke(0.5);
    store.of(0);
    db.loads[0]!.single.complete([]);
    await pumpEventQueue();
    store.add(0, s);
    store.undo();
    expect(store.of(0), isEmpty);
    store.redo();
    store.redo();
    expect(store.of(0), [s]);
  });

  test('캐시를 버리면 되돌리기 기록도 함께 버림', () async {
    store.add(0, _stroke(0.5));
    expect(store.canUndo, isTrue);
    store.reset();
    expect(store.canUndo, isFalse);
    expect(store.canRedo, isFalse);
  });

  test('기다리는 사이 캐시를 버리면 새 캐시의 빈 목록으로 덮어쓰지 않음', () async {
    store.add(0, _stroke(0.5));
    store.reset();
    // 버린 뒤 다시 그려져 새 읽기가 시작된 상태
    store.of(0);
    db.loads[0]!.first.complete([_stroke(0.1)]);
    await pumpEventQueue();
    expect(db.saves, isEmpty);
  });

  test('캐시를 버린 뒤 끝난 옛 읽기는 새 캐시에 끼어들지 않음', () async {
    store.of(0);
    store.reset();
    final list = store.of(0);
    final b = _stroke(0.2);
    db.loads[0]![0].complete([_stroke(0.1)]);
    db.loads[0]![1].complete([b]);
    await pumpEventQueue();
    expect(list, [b]);
  });

  test('읽기에 실패한 쪽은 저장하지 않아 DB의 필기를 덮어쓰지 않음', () async {
    db.loadError = StateError('읽기 실패');
    store.add(0, _stroke(0.5));
    await pumpEventQueue();
    store.add(0, _stroke(0.6));
    await pumpEventQueue();
    expect(db.saves, isEmpty);
    expect(errors, hasLength(2));
  });
}
