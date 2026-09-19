// 페이지별 필기 캐시와 실행취소 기록. 읽기·저장을 주입받아 화면·DB 없이 동작을 검증할 수 있게 함.
// 되돌리기 기록은 캐시 안의 획 객체를 가리키므로 캐시를 버릴 때 기록도 함께 버림.

import 'stroke.dart';

/// 필기 한 번의 변경. 실행취소는 이 기록을 뒤집어 되돌림.
class _Op {
  /// 어느 쪽에서 어떤 획을 더했는지(added) 지웠는지를 남김. 획은 캐시 안의 객체를 그대로 가리킴.
  _Op(this.page, this.stroke, this.added);

  final int page;
  final Stroke stroke;
  final bool added;
}

/// 한 악보의 쪽별 필기 캐시와 되돌리기 기록. 리더 화면 수명 동안 하나만 두고 읽기·저장은 주입받은 함수로 함.
class StrokeStore {
  /// 빈 캐시로 시작함. 쪽마다 처음 찾을 때(of) 읽기 시작하고, 그 쪽 저장은 읽기가 끝난 뒤에 함.
  StrokeStore({required this.load, required this.save, this.onLoaded, this.onSaveError});

  /// 한 페이지의 저장된 획을 읽음.
  final Future<List<Stroke>> Function(int page) load;

  /// 한 페이지의 획 전체를 덮어씀. 빈 목록이면 저장된 것을 지우는 계약이라 읽기 전에 부르면 안 됨.
  final Future<void> Function(int page, List<Stroke> strokes) save;

  /// 읽어 온 획이 캐시에 들어가 다시 그려야 할 때 부름.
  final void Function()? onLoaded;

  /// 저장하지 못했을 때 부름. 획은 캐시에 남아 있음.
  final void Function(int page, Object error)? onSaveError;

  /// 페이지 인덱스별 확정된 획. 열어본 페이지만 채움.
  final _strokes = <int, List<Stroke>>{};

  /// 아직 읽는 중이거나 읽기에 실패한 페이지의 작업. 실패한 채 남겨 두어 그 페이지 저장이 계속 실패하게 함.
  /// 실패를 지우면 다음 저장이 읽지 못한 획을 빼고 덮어써 DB의 필기를 지움.
  final _loading = <int, Future<void>>{};

  /// 캐시의 세대. 캐시를 버릴 때 올려, 그 전에 시작한 읽기·저장이 새 캐시에 끼어들지 못하게 함.
  int _epoch = 0;

  final _undo = <_Op>[];
  final _redo = <_Op>[];

  /// 되돌릴 변경이 있는지.
  bool get canUndo => _undo.isNotEmpty;

  /// 다시 적용할 변경이 있는지.
  bool get canRedo => _redo.isNotEmpty;

  /// 페이지의 획 목록. 아직 안 읽었으면 빈 목록을 돌려주고 읽기를 시작함.
  /// 읽기가 끝나면 같은 목록의 앞에 끼워 넣음. 새 목록으로 갈아 끼우면 그 전에 목록을 잡은
  /// 쪽이 읽어 온 획을 못 봐, 저장이 그 획을 빼고 덮어쓰거나 실행취소가 헛돎.
  List<Stroke> of(int page) {
    final cached = _strokes[page];
    if (cached != null) return cached;
    final list = <Stroke>[];
    final epoch = _epoch;
    _strokes[page] = list;
    final loading = load(page).then((loaded) {
      if (epoch != _epoch) return;
      _loading.remove(page);
      if (loaded.isEmpty) return;
      list.insertAll(0, loaded);
      onLoaded?.call();
    });
    // 실패는 저장 쪽에서 기다리며 받음. 아무도 기다리지 않을 때 처리되지 않은 오류로 새지 않게 함
    loading.ignore();
    _loading[page] = loading;
    return list;
  }

  /// 획을 더하고 기록한 뒤 저장함. 다시 실행 기록은 버림.
  void add(int page, Stroke s) {
    of(page).add(s);
    _undo.add(_Op(page, s, true));
    _redo.clear();
    persist(page);
  }

  /// 조건에 맞는 획을 지우고 기록한 뒤 저장함. 지운 것이 없으면 아무것도 바꾸지 않고 false.
  bool erase(int page, bool Function(Stroke) hit) {
    final list = of(page);
    final gone = list.where(hit).toList();
    if (gone.isEmpty) return false;
    for (final s in gone) {
      list.remove(s);
      _undo.add(_Op(page, s, false));
    }
    _redo.clear();
    persist(page);
    return true;
  }

  /// 마지막 변경을 되돌리고 저장함.
  void undo() {
    if (_undo.isEmpty) return;
    final op = _undo.removeLast();
    final list = of(op.page);
    op.added ? list.remove(op.stroke) : list.add(op.stroke);
    _redo.add(op);
    persist(op.page);
  }

  /// 되돌린 변경을 다시 적용하고 저장함.
  void redo() {
    if (_redo.isEmpty) return;
    final op = _redo.removeLast();
    final list = of(op.page);
    op.added ? list.add(op.stroke) : list.remove(op.stroke);
    _undo.add(op);
    persist(op.page);
  }

  /// 캐시와 되돌리기 기록을 함께 버리고 진행 중인 읽기를 무효로 만듦.
  /// 파일이 바뀌어 획을 다시 읽어야 할 때만 부름. 기록만 남기면 다시 읽은 다른 객체를 가리켜 헛돎.
  void reset() {
    _epoch++;
    _strokes.clear();
    _loading.clear();
    _undo.clear();
    _redo.clear();
  }

  /// 한 페이지를 저장함. 읽기가 끝난 뒤의 목록을 그때 꺼내 저장해 DB에 있던 획을 덮어쓰지 않음.
  /// 기다리는 사이 캐시가 버려졌으면 저장하지 않음. 옛 캐시의 목록이 새로 읽을 획을 덮어씀.
  Future<void> persist(int page) async {
    final epoch = _epoch;
    try {
      await _loading[page];
      final strokes = _strokes[page];
      if (epoch != _epoch || strokes == null) return;
      await save(page, strokes);
    } catch (e) {
      onSaveError?.call(page, e);
    }
  }
}
