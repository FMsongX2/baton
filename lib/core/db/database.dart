// 앱 로컬 DB 진입점. 스키마 정의는 tables.dart에 있고 여기서는 연결과 마이그레이션만 다룸.

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Nodes, Scores, ScorePages, Annotations, Settings])
class BatonDatabase extends _$BatonDatabase {
  BatonDatabase() : super(driftDatabase(name: 'baton'));

  /// 테스트에서 메모리 DB를 물릴 때 씀.
  BatonDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  /// 외래키는 SQLite 기본이 꺼져 있음. 켜지 않으면 cascade 삭제가 조용히 무시됨.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
