// 백업 왕복과 악성 zip 방어, 되살리기 도중 끊김 복구, 열리지 않는 DB 교체 검증. 사용자가 고른 zip을 푸는
// 자리라 신뢰 경계이며, 경로 검사를 빠뜨리면 앱 디렉토리 밖이나 코인 신원 파일까지 덮을 수 있음.

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:baton/core/db/database.dart';
import 'package:baton/core/db/settings_repo.dart';
import 'package:baton/core/storage/backup.dart';
import 'package:baton/core/storage/paths.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// 진짜 Baton DB 파일을 만들고 표식을 넣음. 되살리기가 SQLite인지 검사하므로 글자 파일로는 안 됨.
Future<void> writeDb(String path, String marker, {String? latency, bool unlocked = false}) async {
  final db = BatonDatabase.forTesting(NativeDatabase(File(path)));
  final settings = SettingsRepo(db);
  await settings.set('marker', marker);
  if (latency != null) await settings.set(kLatencyMsKey, latency);
  if (unlocked) await settings.setBool(kMetronomeUnlockedKey, true);
  await db.close();
}

/// 닫기가 실패하는 DB. 닫기 전후 어디서 멈춰도 스테이징이 남지 않는지 보려고 씀.
class _CloseFailsDb extends BatonDatabase {
  /// 메모리 DB 위에 닫기만 실패하게 둠.
  _CloseFailsDb() : super.forTesting(NativeDatabase.memory());

  /// 닫지 않고 던짐.
  @override
  Future<void> close() async => throw StateError('닫기 실패');
}

/// 닫은 뒤 풀어 둔 DB를 치우는 DB. 원본을 밀어 둔 다음 단계에서 교체가 멈추는 상황을 흉내 냄.
class _SwapStopsDb extends BatonDatabase {
  /// 메모리 DB 위에, 닫을 때 [stagedDb]를 지우게 둠.
  _SwapStopsDb(this.stagedDb) : super.forTesting(NativeDatabase.memory());

  final String stagedDb;

  /// 실제로 닫은 뒤 풀어 둔 DB를 지움. 이어지는 제자리 옮기기가 실패함.
  @override
  Future<void> close() async {
    await super.close();
    File(stagedDb).deleteSync();
  }
}

/// DB 파일에서 설정 값 하나를 읽음. 없으면 null.
String? readSetting(String path, String key) {
  final raw = sqlite3.open(path);
  try {
    final rows = raw.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first.columnAt(0) as String;
  } finally {
    raw.close();
  }
}

/// 앱 자리의 DB와 짝 파일을 모두 지움.
void deleteDbFiles(String root) {
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final f = File(p.join(root, 'baton.sqlite$suffix'));
    if (f.existsSync()) f.deleteSync();
  }
}

void main() {
  // 기기마다 DB 하나를 흉내 내느라 인스턴스를 여럿 만듦. 같은 실행기를 나눠 쓰지 않음
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory root;
  late BatonDatabase db;
  late String dbPath;

  /// 지금 앱 자리에 있는 DB의 표식.
  String? marker() => readSetting(dbPath, 'marker');

  /// 항목 이름과 내용 파일을 받아 zip을 만듦.
  Future<File> zipOf(String name, Map<String, File> entries) async {
    final zip = File(p.join(root.path, name));
    final enc = ZipFileEncoder()..create(zip.path);
    for (final e in entries.entries) {
      await enc.addFile(e.value, e.key);
    }
    await enc.close();
    return zip;
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('baton-backup-test');
    AppPaths.overrideDocuments(root);
    db = BatonDatabase.forTesting(NativeDatabase.memory());
    // drift_flutter가 두는 위치를 흉내 냄
    dbPath = p.join(root.path, 'baton.sqlite');
    await writeDb(dbPath, 'DBDATA');
    final scoreDir = Directory(p.join(root.path, 'scores', '7'))..createSync(recursive: true);
    File(p.join(scoreDir.path, 'source.pdf')).writeAsStringSync('PDFDATA');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  test('DB와 악보 파일이 백업에 함께 담김', () async {
    final zip = await exportBackup(db, outPath: p.join(root.path, 'out.zip'));
    final names = ZipDecoder()
        .decodeBytes(zip.readAsBytesSync())
        .files
        .where((f) => f.isFile)
        .map((f) => f.name)
        .toList();
    expect(names, contains('baton.sqlite'));
    expect(names.any((n) => n.endsWith('source.pdf')), isTrue);
  });

  test('백업을 되살리면 파일 내용이 돌아옴', () async {
    final zip = await exportBackup(db, outPath: p.join(root.path, 'out.zip'));

    // 되살리기 전에 원본을 망가뜨려 실제로 덮어쓰는지 확인
    File(p.join(root.path, 'scores', '7', 'source.pdf')).writeAsStringSync('망가짐');
    await writeDb(dbPath, '망가짐');

    await importBackup(zip, BatonDatabase.forTesting(NativeDatabase.memory()));

    expect(File(p.join(root.path, 'scores', '7', 'source.pdf')).readAsStringSync(), 'PDFDATA');
    expect(marker(), 'DBDATA');
    expect(Directory(p.join(root.path, 'restore-staging')).existsSync(), isFalse);
    expect(File(p.join(root.path, 'restore.journal')).existsSync(), isFalse);
  });

  test('되살리기 전에 기존 DB 사본을 남김', () async {
    final zip = await exportBackup(db, outPath: p.join(root.path, 'out.zip'));
    await writeDb(dbPath, '되살리기 직전 상태');

    await importBackup(zip, BatonDatabase.forTesting(NativeDatabase.memory()));

    final saved = p.join(root.path, 'baton.sqlite.pre-restore');
    expect(File(saved).existsSync(), isTrue);
    expect(readSetting(saved, 'marker'), '되살리기 직전 상태');
  });

  test('앱 디렉토리 밖을 가리키는 zip은 거부하고 파일을 쓰지 않음', () async {
    final payload = File(p.join(root.path, 'payload.txt'))..writeAsStringSync('X');
    final evil = await zipOf('evil.zip', {'baton.sqlite': payload, '../../escaped.txt': payload});

    final db2 = BatonDatabase.forTesting(NativeDatabase.memory());
    await expectLater(importBackup(evil, db2), throwsA(isA<FormatException>()));
    expect(File(p.join(root.parent.path, 'escaped.txt')).existsSync(), isFalse);
    expect(marker(), 'DBDATA', reason: '검사에 걸리면 아무것도 쓰지 않아야 함');
  });

  test('코인 신원 파일과 되돌리기용 사본 자리는 백업으로 덮을 수 없음', () async {
    final device = File(p.join(root.path, 'device.json'))..writeAsStringSync('{"token":"mine"}');
    final attacker = File(p.join(root.path, 'attacker.json'))..writeAsStringSync('{"token":"x"}');
    final zip = await exportBackup(db, outPath: p.join(root.path, 'out.zip'));
    final dbCopy = File(p.join(root.path, 'copy.sqlite'));
    File(dbPath).copySync(dbCopy.path);

    for (final name in ['device.json', 'baton.sqlite.pre-restore', 'restore.journal']) {
      final evil = await zipOf('evil.zip', {'baton.sqlite': dbCopy, name: attacker});
      await expectLater(
        importBackup(evil, BatonDatabase.forTesting(NativeDatabase.memory())),
        throwsA(isA<FormatException>()),
        reason: name,
      );
    }
    expect(device.readAsStringSync(), '{"token":"mine"}');
    expect(marker(), 'DBDATA');
    // 정상 백업은 그대로 통과함
    await importBackup(zip, BatonDatabase.forTesting(NativeDatabase.memory()));
    expect(device.readAsStringSync(), '{"token":"mine"}', reason: '백업은 device.json을 담지 않음');
  });

  test('DB가 없는 zip은 백업으로 보지 않음', () async {
    final f = File(p.join(root.path, 'x.txt'))..writeAsStringSync('X');
    final notBackup = await zipOf('other.zip', {'x.txt': f});

    final db2 = BatonDatabase.forTesting(NativeDatabase.memory());
    await expectLater(importBackup(notBackup, db2), throwsA(isA<FormatException>()));
  });

  test('SQLite가 아니거나 더 새 버전 앱의 DB는 교체 전에 거부하고 DB를 열어 둠', () async {
    final notDb = File(p.join(root.path, 'not.sqlite'))..writeAsStringSync('DBDATA');
    final newer = p.join(root.path, 'newer.sqlite');
    await writeDb(newer, 'NEWER');
    final raw = sqlite3.open(newer)..execute('PRAGMA user_version = 99');
    raw.close();

    for (final dbFile in [notDb, File(newer)]) {
      final zip = await zipOf('bad.zip', {'baton.sqlite': dbFile});
      final db2 = BatonDatabase.forTesting(NativeDatabase.memory());
      await expectLater(importBackup(zip, db2), throwsA(isA<FormatException>()));
      expect(marker(), 'DBDATA');
      await expectLater(db2.customSelect('SELECT 1').get(), completes, reason: '교체 전이라 닫지 않음');
    }
  });

  test('되살려도 출력 지연·구매 캐시처럼 기기마다 다른 설정은 이 기기 값을 남김', () async {
    final other = p.join(root.path, 'other.sqlite');
    await writeDb(other, 'OTHER', latency: '5000', unlocked: true);
    final zip = await zipOf('other.zip', {'baton.sqlite': File(other)});

    final here = BatonDatabase.forTesting(NativeDatabase.memory());
    await SettingsRepo(here).set(kLatencyMsKey, '180');
    await importBackup(zip, here);
    expect(marker(), 'OTHER');
    expect(readSetting(dbPath, kLatencyMsKey), '180');
    expect(readSetting(dbPath, kMetronomeUnlockedKey), isNull, reason: '남의 백업으로 구매 없이 풀리면 안 됨');

    // 이 기기에 값이 없으면 백업 값도 들이지 않고 기본값으로 둠
    await importBackup(zip, BatonDatabase.forTesting(NativeDatabase.memory()));
    expect(readSetting(dbPath, kLatencyMsKey), isNull);
  });

  test('지금 DB가 열리지 않아도(손상, 더 새 스키마) 되살리기로 교체하고 기기 설정은 기본값으로 둠', () async {
    final other = p.join(root.path, 'other.sqlite');
    await writeDb(other, 'OTHER', latency: '5000', unlocked: true);
    final zip = await zipOf('other.zip', {'baton.sqlite': File(other)});

    for (final kind in ['손상', '더 새 스키마']) {
      deleteDbFiles(root.path);
      if (kind == '손상') {
        File(dbPath).writeAsStringSync('쓰레기' * 200);
      } else {
        await writeDb(dbPath, 'NEWER');
        sqlite3.open(dbPath)
          ..execute('PRAGMA user_version = 99')
          ..close();
      }
      final broken = BatonDatabase.forTesting(NativeDatabase(File(dbPath)));

      await importBackup(zip, broken);

      expect(
        File(p.join(root.path, 'baton.sqlite.pre-restore')).existsSync(),
        isTrue,
        reason: kind,
      );
      expect(marker(), 'OTHER', reason: kind);
      expect(readSetting(dbPath, kLatencyMsKey), isNull, reason: '이 기기 값을 못 읽으면 기본값');
      expect(readSetting(dbPath, kMetronomeUnlockedKey), isNull);
      expect(Directory(p.join(root.path, 'restore-staging')).existsSync(), isFalse);
      expect(File(p.join(root.path, 'restore.journal')).existsSync(), isFalse);
    }
  });

  test('옛 DB의 짝 파일은 새 DB 옆에 남기지 않고 사본과 함께 밀어 둠', () async {
    final zip = await exportBackup(db, outPath: p.join(root.path, 'out.zip'));
    // -wal이 있으면 SQLite는 헤더와 무관하게 그 내용을 DB에 덮어 읽음
    File('$dbPath-wal').writeAsStringSync('OLDWAL');

    await importBackup(zip, BatonDatabase.forTesting(NativeDatabase.memory()));

    expect(File('$dbPath-wal').existsSync(), isFalse);
    expect(File(p.join(root.path, 'baton.sqlite.pre-restore-wal')).readAsStringSync(), 'OLDWAL');
    expect(marker(), 'DBDATA');
  });

  test('지난 되살리기가 남긴 짝 파일은 이번 교체가 멈춰 되돌려도 원래 DB 옆으로 오지 않음', () async {
    final zip = await exportBackup(db, outPath: p.join(root.path, 'out.zip'));
    // 지난 되살리기가 끝나며 사본 옆에 남긴 -wal. 지우지 않으면 이번 사본의 짝이 됨
    File(p.join(root.path, 'baton.sqlite.pre-restore-wal')).writeAsStringSync('STALEWAL');
    final staged = p.join(root.path, 'restore-staging', 'baton.sqlite');

    await expectLater(importBackup(zip, _SwapStopsDb(staged)), throwsA(isA<RestoreNeedsRestart>()));

    // DB를 열어 보기 전에 봄. 열었다 닫으면 SQLite가 -wal을 치움
    expect(File('$dbPath-wal').existsSync(), isFalse, reason: '옛 -wal이 원래 DB에 덮여 읽힘');
    expect(File(p.join(root.path, 'restore.journal')).existsSync(), isFalse);
    expect(marker(), 'DBDATA');
  });

  test('DB를 닫다가 실패하면 풀어 둔 스테이징을 치우고 원래 라이브러리를 둔 채 재시작을 요구함', () async {
    final zip = await exportBackup(db, outPath: p.join(root.path, 'out.zip'));

    await expectLater(importBackup(zip, _CloseFailsDb()), throwsA(isA<RestoreNeedsRestart>()));

    expect(Directory(p.join(root.path, 'restore-staging')).existsSync(), isFalse);
    expect(File(p.join(root.path, 'restore.journal')).existsSync(), isFalse);
    expect(File(p.join(root.path, 'baton.sqlite.pre-restore')).existsSync(), isFalse);
    expect(marker(), 'DBDATA');
  });

  test('되살리기는 합치기가 아니라 교체라 백업에 없던 악보가 남지 않음', () async {
    final zip = await exportBackup(db, outPath: p.join(root.path, 'out.zip'));
    // 백업을 만든 뒤에 생긴 악보. 되살리면 사라져야 함
    final later = Directory(p.join(root.path, 'scores', '9'))..createSync(recursive: true);
    File(p.join(later.path, 'source.pdf')).writeAsStringSync('LATER');

    await importBackup(zip, BatonDatabase.forTesting(NativeDatabase.memory()));

    expect(Directory(p.join(root.path, 'scores', '7')).existsSync(), isTrue);
    expect(later.existsSync(), isFalse);
  });

  test('풀다가 실패하면 원래 데이터가 그대로이고 DB도 닫지 않음', () async {
    // 둘 다 받아들이는 경로지만 파일 자리에 디렉토리를 만들어야 해서 풀기 도중에 실패함
    final dbFile = File(dbPath);
    final broken = await zipOf('broken.zip', {
      'baton.sqlite': dbFile,
      'scores/1/a': dbFile,
      'scores/1/a/b': dbFile,
    });

    final db2 = BatonDatabase.forTesting(NativeDatabase.memory());
    // 경로 검사(FormatException)가 아니라 풀기에서 멈췄는지 확인함
    await expectLater(importBackup(broken, db2), throwsA(isA<FileSystemException>()));

    expect(marker(), 'DBDATA');
    expect(File(p.join(root.path, 'scores', '7', 'source.pdf')).readAsStringSync(), 'PDFDATA');
    // 반쯤 풀린 것이 남아 있으면 안 됨
    expect(Directory(p.join(root.path, 'scores', '1')).existsSync(), isFalse);
    expect(Directory(p.join(root.path, 'restore-staging')).existsSync(), isFalse);
    // 닫힌 DB로 앱이 계속 돌면 모든 읽기·쓰기가 실패함
    await expectLater(db2.customSelect('SELECT 1').get(), completes);
  });

  test('앞선 교체의 저널이 남아 있으면 되살리지 않고 밀어 둔 원본을 지키며 재시작을 요구함', () async {
    final zip = await exportBackup(db, outPath: p.join(root.path, 'out.zip'));
    // 시작 때 되돌리기가 실패한 상태. 원본은 사본 자리에만 있고 제자리에는 반쯤 바뀐 DB가 있음
    final aside = p.join(root.path, 'baton.sqlite.pre-restore');
    File(dbPath).renameSync(aside);
    await writeDb(dbPath, 'HALF');
    File(p.join(root.path, 'restore.journal')).writeAsStringSync('restore');

    final db2 = BatonDatabase.forTesting(NativeDatabase.memory());
    await expectLater(importBackup(zip, db2), throwsA(isA<RestoreNeedsRestart>()));
    expect(readSetting(aside, 'marker'), 'DBDATA', reason: '유일한 원본 사본이 남아야 함');
    await expectLater(db2.customSelect('SELECT 1').get(), completes);

    // 다음 시작이 원본으로 되돌림
    await recoverInterruptedRestore();
    expect(marker(), 'DBDATA');
  });

  group('교체 도중 프로세스가 죽은 뒤 다음 시작', () {
    late String staging;

    /// 교체가 어디까지 갔는지 흉내 냄. 저널을 남기고 스테이징에 새 DB를 둠.
    Future<void> interrupted({required bool dbMoved, required bool scoresMoved}) async {
      staging = p.join(root.path, 'restore-staging');
      Directory(p.join(staging, 'scores', '1')).createSync(recursive: true);
      await writeDb(p.join(staging, 'baton.sqlite'), 'NEW');
      File(p.join(root.path, 'restore.journal')).writeAsStringSync('restore');
      if (dbMoved) {
        File(dbPath).renameSync(p.join(root.path, 'baton.sqlite.pre-restore'));
        File(p.join(staging, 'baton.sqlite')).renameSync(dbPath);
      }
      if (scoresMoved) {
        Directory(p.join(root.path, 'scores')).renameSync(p.join(root.path, 'scores.pre-restore'));
        Directory(p.join(staging, 'scores')).renameSync(p.join(root.path, 'scores'));
      }
    }

    /// 원래 라이브러리가 제자리에 있고 교체 흔적이 없는지 확인함.
    void expectOriginal() {
      expect(marker(), 'DBDATA');
      expect(File(p.join(root.path, 'scores', '7', 'source.pdf')).readAsStringSync(), 'PDFDATA');
      expect(Directory(p.join(root.path, 'scores', '1')).existsSync(), isFalse);
      for (final left in [
        'restore.journal',
        'restore-staging',
        'baton.sqlite.pre-restore',
        'scores.pre-restore',
      ]) {
        expect(
          FileSystemEntity.typeSync(p.join(root.path, left)),
          FileSystemEntityType.notFound,
          reason: left,
        );
      }
    }

    test('밀어 두기 전이면 스테이징만 치움', () async {
      await interrupted(dbMoved: false, scoresMoved: false);
      await recoverInterruptedRestore();
      expectOriginal();
    });

    test('DB만 바뀐 채 멈췄으면 원래 DB로 되돌림', () async {
      await interrupted(dbMoved: true, scoresMoved: false);
      expect(marker(), 'NEW');
      await recoverInterruptedRestore();
      expectOriginal();
    });

    test('DB와 악보까지 바뀐 채 멈췄어도 원래 라이브러리로 되돌림', () async {
      await interrupted(dbMoved: true, scoresMoved: true);
      await recoverInterruptedRestore();
      expectOriginal();
    });

    test('밀어 둔 짝 파일도 원래 DB 옆으로 돌아옴', () async {
      File('$dbPath-wal').writeAsStringSync('OLDWAL');
      await interrupted(dbMoved: true, scoresMoved: false);
      File('$dbPath-wal').renameSync(p.join(root.path, 'baton.sqlite.pre-restore-wal'));

      await recoverInterruptedRestore();

      expect(File('$dbPath-wal').readAsStringSync(), 'OLDWAL');
      expect(File(p.join(root.path, 'baton.sqlite.pre-restore-wal')).existsSync(), isFalse);
      expectOriginal();
    });

    test('끝난 되살리기의 사본은 건드리지 않고 남은 스테이징만 치움', () async {
      final zip = await exportBackup(db, outPath: p.join(root.path, 'out.zip'));
      await importBackup(zip, BatonDatabase.forTesting(NativeDatabase.memory()));
      Directory(p.join(root.path, 'restore-staging')).createSync();

      await recoverInterruptedRestore();

      expect(File(p.join(root.path, 'baton.sqlite.pre-restore')).existsSync(), isTrue);
      expect(Directory(p.join(root.path, 'restore-staging')).existsSync(), isFalse);
      expect(marker(), 'DBDATA');
    });
  });
}
