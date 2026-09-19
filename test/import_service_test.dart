// 임포트 입구 검증. 파일을 다 쓰고 열어 보기 전에는 악보 행이 생기지 않아, 쓰다가 앱이 죽어도
// 파일 없는 악보가 남지 않는지, 동시 가져오기가 임시 자리를 공유하지 않는지, 이름 길이를 고정함.

import 'dart:async';
import 'dart:io';

import 'package:baton/core/db/database.dart';
import 'package:baton/core/storage/paths.dart';
import 'package:baton/score/import/import_service.dart';
import 'package:baton/score/score_repo.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory docs;
  late BatonDatabase db;
  late ScoreRepo repo;
  final landscape = File('test/fixtures/landscape_200x100.png');
  final portrait = File('test/fixtures/portrait_100x200.png');

  setUp(() {
    docs = Directory.systemTemp.createTempSync('baton-import-test');
    AppPaths.overrideDocuments(docs);
    db = BatonDatabase.forTesting(NativeDatabase.memory());
    repo = ScoreRepo(db);
  });

  tearDown(() async {
    await db.close();
    docs.deleteSync(recursive: true);
  });

  /// docs 아래 디렉토리에 남은 항목. 없으면 빈 목록.
  List<FileSystemEntity> entriesOf(String rel) {
    final dir = Directory(p.join(docs.path, rel));
    return dir.existsSync() ? dir.listSync() : const [];
  }

  /// 악보 디렉토리 아래 남은 항목.
  List<FileSystemEntity> leftovers() => entriesOf('scores');

  /// 가져오기 임시 자리에 남은 항목.
  List<FileSystemEntity> stagingLeftovers() => entriesOf('import-staging');

  test('파일을 다 쓰고 열어 보기 전에는 악보 행이 없고, 실패하면 흔적이 남지 않음', () async {
    final opened = Completer<void>();
    final release = Completer<int>();
    final svc = ImportService(
      db,
      repo,
      countPages: (path) {
        expect(File(path).existsSync(), isTrue);
        opened.complete();
        return release.future;
      },
    );
    final job = svc.importImages([landscape], name: '스캔');
    await opened.future;
    expect(await db.select(db.nodes).get(), isEmpty, reason: '이 사이에 앱이 죽으면 파일 없는 악보가 남던 자리');

    release.completeError(const FormatException('깨진 PDF'));
    await expectLater(job, throwsFormatException);
    expect(await db.select(db.nodes).get(), isEmpty);
    expect(leftovers(), isEmpty);
    expect(stagingLeftovers(), isEmpty);
  });

  test('성공하면 실제 쪽수로 행을 만들고 파일을 제자리에 둠', () async {
    final svc = ImportService(db, repo, countPages: (_) async => 2);
    final id = await svc.importImages([landscape, portrait], name: '두 장');
    expect((await repo.score(id))!.pageCount, 2);
    expect((await repo.pages(id)).length, 2);
    expect(File(AppPaths.abs(AppPaths.sourcePdf(id))).existsSync(), isTrue);
    expect(stagingLeftovers(), isEmpty);
  });

  test('동시에 도는 가져오기가 서로의 임시 파일을 지우지 않음', () async {
    final opened = Completer<void>();
    final release = Completer<int>();
    final held = ImportService(
      db,
      repo,
      countPages: (_) {
        opened.complete();
        return release.future;
      },
    );
    final first = held.importImages([landscape], name: '먼저');
    await opened.future;
    // 다른 폴더 화면이나 복구 가져오기가 그 사이 시작함
    final second = await ImportService(
      db,
      repo,
      countPages: (_) async => 1,
    ).importImages([portrait], name: '나중');
    release.complete(1);
    final firstId = await first;

    for (final id in [firstId, second]) {
      expect(File(AppPaths.abs(AppPaths.sourcePdf(id))).existsSync(), isTrue);
    }
    expect(stagingLeftovers(), isEmpty);
  });

  test('앞선 실행이 가져오다 끊기며 남긴 임시 파일은 다음 가져오기가 치움', () async {
    final stale = File(p.join(docs.path, 'import-staging', '1-0', 'source.pdf'))
      ..createSync(recursive: true);
    final svc = ImportService(db, repo, countPages: (_) async => 1);
    await svc.importImages([landscape], name: '스캔');
    expect(stale.parent.existsSync(), isFalse);
    expect(stagingLeftovers(), isEmpty);
  });

  test('없는 PDF를 고르면 행 없이 실패함', () async {
    final svc = ImportService(db, repo, countPages: (_) async => 1);
    await expectLater(
      svc.importPdf(File(p.join(docs.path, '없음.pdf'))),
      throwsA(isA<FileSystemException>()),
    );
    expect(await db.select(db.nodes).get(), isEmpty);
    expect(leftovers(), isEmpty);
  });

  test('긴 파일 이름은 저장 가능한 길이로 잘라 가져옴', () async {
    final svc = ImportService(db, repo, countPages: (_) async => 1);
    final id = await svc.importImages([landscape], name: 'a' * 250);
    final node = await (db.select(db.nodes)..where((n) => n.id.equals(id))).getSingle();
    expect(node.name.length, kMaxNodeNameLength);
  });

  test('이름은 공백을 떼고, 비면 기본값을 쓰고, 이모지를 반쪽으로 자르지 않음', () {
    expect(clampNodeName('  악보  '), '악보');
    expect(clampNodeName('   '), '새 악보');
    final cut = clampNodeName('${'a' * (kMaxNodeNameLength - 1)}🎵');
    expect(cut, 'a' * (kMaxNodeNameLength - 1), reason: '서로게이트 쌍의 앞쪽만 남기지 않음');
  });
}
