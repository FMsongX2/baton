// 라이브러리 트리와 악보 재생 설정의 저장 스키마. 파일 경로는 앱 문서 디렉토리 기준 상대경로만 둠.
// iOS 컨테이너 UUID가 앱 업데이트마다 바뀌므로 절대경로를 저장하면 업데이트 직후 전 악보가 사라짐.

import 'package:drift/drift.dart';

enum NodeKind { folder, score }

/// 폴더와 악보를 함께 담는 트리. parentId가 null이면 루트.
class Nodes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get parentId => integer().nullable().references(Nodes, #id)();
  TextColumn get kind => textEnum<NodeKind>()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// null이 아니면 휴지통에 있음. 실제 파일은 이 시점에 지우지 않음.
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// kind가 score인 노드의 재생 설정. 임포트한 모든 원본은 PDF 한 개로 정규화해 둠.
class Scores extends Table {
  IntColumn get nodeId => integer().references(Nodes, #id, onDelete: KeyAction.cascade)();

  /// `scores/<nodeId>/source.pdf` 형태의 상대경로.
  TextColumn get fileRel => text()();
  IntColumn get pageCount => integer()();
  RealColumn get bpm => real().withDefault(const Constant(120))();
  IntColumn get timeSigNum => integer().withDefault(const Constant(4))();
  IntColumn get timeSigDen => integer().withDefault(const Constant(4))();

  /// 마디당 클릭 수. 겹박자를 별도 분기 없이 처리하려고 박자표와 분리해 둠.
  IntColumn get clicksPerBar => integer().withDefault(const Constant(4))();
  IntColumn get countInBars => integer().withDefault(const Constant(1))();

  /// 페이지를 몇 박 일찍 넘길지. 연주자가 다음 줄을 미리 읽을 여유.
  RealColumn get leadBeats => real().withDefault(const Constant(2))();

  /// 화면에 보여줄 페이지의 순서. 물리 페이지 인덱스 배열 JSON이며 중복은 없음.
  /// 여기서 빠진 페이지는 숨겨진 것으로 봄. PDF 자체는 건드리지 않아 필기가 그대로 따라옴.
  /// null이면 0..pageCount-1 순서 그대로.
  TextColumn get pageOrderJson => text().nullable()();

  /// 재생 순서. pageOrder상의 위치를 가리키는 인덱스 배열 JSON이며 중복을 허용함.
  /// 페이지 단위 반복·D.S.·D.C.를 전부 이 배열로 펼쳐서 표현함. null이면 선형.
  TextColumn get playOrderJson => text().nullable()();
  TextColumn get composer => text().nullable()();
  TextColumn get memo => text().nullable()();

  @override
  Set<Column> get primaryKey => {nodeId};
}

/// 페이지별 타이밍. bpm과 clicksPerBar가 null이면 악보 기본값을 상속함.
class ScorePages extends Table {
  IntColumn get scoreId => integer().references(Scores, #nodeId, onDelete: KeyAction.cascade)();
  IntColumn get pageIndex => integer()();

  /// 이 페이지가 화면에 떠 있는 동안 흐르는 마디 수. 페이지 중간 도돌이표는 여기에 합산함.
  IntColumn get barCount => integer().withDefault(const Constant(4))();
  RealColumn get bpm => real().nullable()();
  IntColumn get clicksPerBar => integer().nullable()();

  @override
  Set<Column> get primaryKey => {scoreId, pageIndex};
}

/// 페이지별 필기. 편집 단위가 페이지라 획을 행으로 쪼개지 않고 JSON 한 덩어리로 둠.
class Annotations extends Table {
  IntColumn get scoreId => integer().references(Scores, #nodeId, onDelete: KeyAction.cascade)();
  IntColumn get pageIndex => integer()();
  TextColumn get strokesJson => text()();

  @override
  Set<Column> get primaryKey => {scoreId, pageIndex};
}

/// 지연 보정, 페달 키맵, 표시 옵션, 구매 상태 캐시.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
