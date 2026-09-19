// 라이브러리 통째로 내보내기·되살리기. 필기와 악보는 잃으면 복구할 방법이 없으므로
// 되살리기는 먼저 옆에 풀어 검사하고, 교체 도중 죽어도 다음 시작에서 원래대로 되돌림.

import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../db/database.dart';
import '../db/settings_repo.dart';
import 'paths.dart';

/// 백업 안에 들어가는 DB 파일 이름. drift_flutter가 문서 디렉토리에 이 이름으로 둠.
const _dbFileName = 'baton.sqlite';

/// 악보 디렉토리 이름. 백업에는 이 아래의 `<nodeId>/` 디렉토리만 들어감.
const _scoresDirName = 'scores';

/// 되살리기 직전에 남기는 기존 DB 사본. 교체가 끝나기 전에 멈추면 이 파일로 되돌림.
const _dbBackupName = 'baton.sqlite.pre-restore';

/// DB 파일과 SQLite가 그 이름 뒤에 붙여 두는 짝 파일(WAL·저널)의 접미사. 옮길 때 한 묶음으로 옮김.
/// 옛 DB의 짝 파일이 새 DB 옆에 남으면 SQLite가 그 내용을 새 DB에 덮어 써 망가뜨림.
const _dbFileSuffixes = ['', '-wal', '-shm', '-journal'];

/// 되살리기 직전에 옆으로 밀어 두는 기존 악보 디렉토리.
const _scoresBackupName = 'scores.pre-restore';

/// 백업을 먼저 풀어 검사하는 자리. DB를 닫기 전에 여기서 전부 끝냄.
const _stagingName = 'restore-staging';

/// 교체 중임을 알리는 표시. 이 파일이 남아 있으면 교체가 끝나지 않은 것이라 시작할 때 되돌림.
const _journalName = 'restore.journal';

/// 내보낸 백업을 모아 두는 임시 디렉토리 이름. 다음 내보내기 때 통째로 비움.
const _exportDirName = 'baton-export';

/// 앱을 다시 시작해야 끝나는 되살리기 실패. 다음 시작이 원래 라이브러리로 되돌림.
/// DB를 닫는 중이나 닫은 뒤에 실패해 이번 실행의 DB 연결을 더 쓸 수 없거나,
/// 앞선 교체를 시작 때 되돌리지 못해 저널이 남은 경우.
class RestoreNeedsRestart implements Exception {
  /// 되살리기를 멈추게 한 원래 예외나 사유를 감쌈.
  RestoreNeedsRestart(this.cause);

  final Object cause;

  /// 원래 예외나 사유를 그대로 보여 줌.
  @override
  String toString() => '$cause';
}

/// DB와 악보 파일을 zip 하나로 묶어 경로를 돌려줌.
/// 지난 번에 내보낸 파일은 공유가 끝난 뒤 지울 방법이 없으므로 여기서 정리함.
Future<File> exportBackup(BatonDatabase db, {String? outPath}) async {
  // WAL에만 남아 있는 최근 변경이 백업에서 빠지지 않게 먼저 본 파일로 밀어 넣음
  await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');

  final File dest;
  if (outPath != null) {
    dest = File(outPath);
  } else {
    final dir = Directory(p.join(Directory.systemTemp.path, _exportDirName));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    dest = File(p.join(dir.path, 'baton-backup-${DateTime.now().millisecondsSinceEpoch}.zip'));
  }

  final encoder = ZipFileEncoder()..create(dest.path);
  try {
    final dbFile = File(AppPaths.abs(_dbFileName));
    if (await dbFile.exists()) await encoder.addFile(dbFile, _dbFileName);

    final scores = Directory(AppPaths.abs(_scoresDirName));
    if (await scores.exists()) {
      await for (final e in scores.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final rel = p.relative(e.path, from: AppPaths.abs(''));
        await encoder.addFile(e, rel);
      }
    }
  } finally {
    await encoder.close();
  }
  return dest;
}

/// 백업 zip으로 라이브러리를 교체함. 되살린 뒤에는 앱을 다시 시작해야 새 DB가 열림.
/// 먼저 옆 디렉토리에 전부 풀고 DB를 검사하므로, 여기까지 실패하면 DB는 열린 채 그대로 남음.
/// 그다음 DB를 닫고 이름만 바꿔 교체함. 이 구간에서 실패하면 [RestoreNeedsRestart]를 던짐.
/// 기기마다 다른 설정([kDeviceLocalKeys])은 백업 값 대신 이 기기 값을 남김.
/// 지금 DB가 열리지 않아도(손상, 더 새 스키마) 교체함. 되살리기가 그 DB를 고치는 수단이기 때문.
/// 앞선 교체의 저널이 남아 있으면 아무것도 건드리지 않고 [RestoreNeedsRestart]를 던짐.
Future<void> importBackup(File zip, BatonDatabase db) async {
  final root = AppPaths.abs('');
  // 저널이 남았다면 밀어 둔 사본이 유일한 원본. 아래에서 지난 사본을 지우면 그 원본을 잃음
  if (await File(p.join(root, _journalName)).exists()) {
    throw RestoreNeedsRestart('앞선 되살리기를 아직 되돌리지 못함');
  }
  final staging = p.join(root, _stagingName);
  final keep = await _deviceLocalSettings(db);

  try {
    await _deleteIfExists(staging);
    await _stageInIsolate(zip.path, staging, keep, db.schemaVersion);
    // 지난 되살리기가 남긴 사본. 저널이 없으니 그 교체는 끝났고, 남겨 두면 이번 되돌리기가 옛 상태로 감
    for (final suffix in _dbFileSuffixes) {
      await _deleteIfExists(p.join(root, '$_dbBackupName$suffix'));
    }
    await _deleteIfExists(p.join(root, _scoresBackupName));
    // 원본이 없어도 밀어 두기가 늘 일어나게 빈 자리를 만듦. 되돌리기가 사본 유무만 보고 판단하게 함.
    // 0바이트 파일은 SQLite에게 빈 DB라 없는 것과 같음
    final current = File(p.join(root, _dbFileName));
    if (!await current.exists()) await current.create(recursive: true);
    await Directory(p.join(root, _scoresDirName)).create(recursive: true);
  } catch (_) {
    await _deleteIfExists(staging);
    rethrow;
  }
  await _swap(root, db);
}

/// 이 기기의 [kDeviceLocalKeys] 값을 읽음. DB를 읽지 못하면 그 보존만 건너뛰고 전부 null을 돌려줌.
/// null은 되살린 DB에서 그 키를 지워 기본값으로 두게 함. 백업 값을 남기면 남의 구매 캐시까지 들어옴.
Future<Map<String, String?>> _deviceLocalSettings(BatonDatabase db) async {
  final settings = SettingsRepo(db);
  try {
    return {for (final key in kDeviceLocalKeys) key: await settings.get(key)};
  } on Exception {
    return {for (final key in kDeviceLocalKeys) key: null};
  }
}

/// 앱 시작 때 DB를 열기 전에 부름. 교체 도중 멈췄으면 밀어 둔 원본을 제자리로 돌리고,
/// 풀다 만 스테이징을 치움. 교체가 끝난 뒤의 사본은 건드리지 않음.
Future<void> recoverInterruptedRestore() async {
  final root = AppPaths.abs('');
  if (await File(p.join(root, _journalName)).exists()) {
    await _rollBack(root);
  } else {
    await _deleteIfExists(p.join(root, _stagingName));
  }
}

/// 풀기를 UI 격리 밖에서 돌림. 항목 쓰기가 동기라 여기서 돌리면 진행 표시가 굳어 앱이 멈춘 것으로 보임.
/// 클로저가 DB 같은 보낼 수 없는 값을 붙잡지 않게 인자만 받는 함수로 분리함.
Future<void> _stageInIsolate(
  String zipPath,
  String staging,
  Map<String, String?> keep,
  int schemaVersion,
) => Isolate.run(() => _stage(zipPath, staging, keep, schemaVersion));

/// zip을 스테이징에 풀고 DB를 검사해 이 기기 설정을 옮겨 적음. 문제가 있으면 FormatException.
void _stage(String zipPath, String staging, Map<String, String?> keep, int schemaVersion) {
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    if (!archive.files.any((f) => f.isFile && f.name == _dbFileName)) {
      throw const FormatException('백업 파일이 아님: $_dbFileName 이 없음');
    }
    // 어디에 쓰일지 먼저 전부 검사함. 받아들일 수 없는 항목이 하나라도 있으면 아무것도 풀지 않음
    final planned = <ArchiveFile, String>{
      for (final f in archive.files)
        if (f.isFile) f: p.join(staging, _acceptedPath(f.name)),
    };
    for (final entry in planned.entries) {
      final out = File(entry.value);
      out.parent.createSync(recursive: true);
      final sink = OutputFileStream(out.path);
      try {
        entry.key.writeContent(sink);
      } finally {
        sink.closeSync();
      }
    }
  } finally {
    input.closeSync();
  }
  _prepareDb(p.join(staging, _dbFileName), keep, schemaVersion);
}

/// zip 안의 이름을 스테이징 기준 상대경로로 바꿈. `baton.sqlite`와 `scores/<숫자>/` 아래만 받음.
/// 백업은 남이 만든 것일 수 있음. 나머지를 받으면 device.json(코인 신원)이나 되돌리기용 사본까지 덮임.
String _acceptedPath(String name) {
  final rel = p.posix.normalize(name);
  final parts = p.posix.split(rel);
  final ok =
      rel == _dbFileName ||
      (parts.length >= 3 && parts[0] == _scoresDirName && RegExp(r'^\d+$').hasMatch(parts[1]));
  if (!ok) throw FormatException('백업에 들어갈 수 없는 항목이 있음: $name');
  return p.joinAll(parts);
}

/// 풀어 둔 DB가 이 앱이 열 수 있는 것인지 확인하고, 이 기기 설정을 그 DB에 옮겨 적음.
/// 교체한 뒤에야 열기에 실패하면 라이브러리 전체가 잠기므로 교체 전에 거름.
void _prepareDb(String path, Map<String, String?> keep, int schemaVersion) {
  final raw = sqlite3.open(path);
  try {
    // 이 격리는 drift가 잡아 둔 임시 디렉토리 설정이 없음. 안드로이드는 기본 임시 경로에 못 씀
    raw.execute('PRAGMA temp_store = MEMORY');
    final version = raw.userVersion;
    final check = raw.select('PRAGMA quick_check').first.columnAt(0);
    if (check != 'ok') throw FormatException('백업 DB가 손상됨: $check');
    if (version < 1) throw const FormatException('Baton 백업 DB가 아님');
    if (version > schemaVersion) {
      throw const FormatException('더 새 버전의 앱에서 만든 백업임. 앱을 업데이트한 뒤 되살려야 함');
    }
    for (final e in keep.entries) {
      if (e.value == null) {
        raw.execute('DELETE FROM settings WHERE key = ?', [e.key]);
      } else {
        raw.execute('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [e.key, e.value]);
      }
    }
  } on SqliteException catch (e) {
    throw FormatException('백업 DB를 열 수 없음: ${e.message}');
  } finally {
    raw.close();
  }
}

/// DB를 닫고 원본을 옆으로 민 뒤 스테이징을 제자리로 옮김. 이름 바꾸기만 하므로 닫힌 구간이 짧음.
/// 교체 중에는 저널을 남겨, 도중에 프로세스가 죽어도 다음 시작에서 원본으로 되돌리게 함.
/// 닫기부터 실패하면 스테이징까지 치우고 [RestoreNeedsRestart]를 던짐. 연결 상태를 알 수 없기 때문.
Future<void> _swap(String root, BatonDatabase db) async {
  final scores = Directory(p.join(root, _scoresDirName));
  final staging = p.join(root, _stagingName);
  final journal = File(p.join(root, _journalName));

  try {
    // 체크포인트는 열리지 않는 DB에서 던지므로 하지 않음. 닫기는 열린 적 없는 연결에서도 끝나고,
    // WAL·저널에 남은 변경은 짝 파일째 옆으로 밀어 사본에 붙여 둠
    await db.close();
    await journal.writeAsString('restore', flush: true);
    await _moveDbFiles(root, from: _dbFileName, to: _dbBackupName);
    await scores.rename(p.join(root, _scoresBackupName));
    await File(p.join(staging, _dbFileName)).rename(p.join(root, _dbFileName));
    final stagedScores = Directory(p.join(staging, _scoresDirName));
    if (await stagedScores.exists()) {
      await stagedScores.rename(scores.path);
    } else {
      await scores.create();
    }
    // 저널이 사라지는 순간 교체가 확정됨
    await journal.delete();
  } catch (e) {
    try {
      await _rollBack(root);
    } catch (_) {
      // 저널이 남아 있으므로 다음 시작에서 마저 되돌림
    }
    throw RestoreNeedsRestart(e);
  }
  try {
    await _deleteIfExists(staging);
  } catch (_) {
    // 못 지워도 다음 시작에서 치움
  }
}

/// DB 파일과 그 짝 파일을 [from] 이름에서 [to] 이름으로 옮김. 없는 짝 파일은 건너뜀.
/// 본 파일을 먼저 옮김. 짝 파일을 옮기기 전에 멈춰도 되돌리기가 본 파일만 돌려 원래 짝과 다시 만남.
Future<void> _moveDbFiles(String root, {required String from, required String to}) async {
  for (final suffix in _dbFileSuffixes) {
    final file = File(p.join(root, '$from$suffix'));
    if (await file.exists()) await file.rename(p.join(root, '$to$suffix'));
  }
}

/// 끝나지 않은 교체를 되돌림. 저널이 있을 때만 부르며, 그때 밀어 둔 사본이 곧 원본.
/// 몇 번 불러도 같은 결과가 되도록 파일마다 사본 유무로만 판단하고, 저널은 맨 마지막에 지움.
Future<void> _rollBack(String root) async {
  for (final suffix in _dbFileSuffixes) {
    final aside = File(p.join(root, '$_dbBackupName$suffix'));
    if (!await aside.exists()) continue;
    await _deleteIfExists(p.join(root, '$_dbFileName$suffix'));
    await aside.rename(p.join(root, '$_dbFileName$suffix'));
  }
  final scoresAside = Directory(p.join(root, _scoresBackupName));
  if (await scoresAside.exists()) {
    await _deleteIfExists(p.join(root, _scoresDirName));
    await scoresAside.rename(p.join(root, _scoresDirName));
  }
  await _deleteIfExists(p.join(root, _stagingName));
  await _deleteIfExists(p.join(root, _journalName));
}

/// 경로에 무엇이 있든(파일·디렉토리) 지움. 없으면 넘어감.
Future<void> _deleteIfExists(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  await (type == FileSystemEntityType.directory ? Directory(path) : File(path)).delete(
    recursive: true,
  );
}
