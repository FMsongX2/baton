// 라이브러리 통째로 내보내기·되살리기. 필기와 악보는 잃으면 복구할 방법이 없으므로
// 백업 전에 WAL을 정리하고, 되살리기 전에는 기존 DB 사본을 반드시 남김.

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../db/database.dart';
import 'paths.dart';

/// 백업 안에 들어가는 DB 파일 이름. drift_flutter가 문서 디렉토리에 이 이름으로 둠.
const _dbFileName = 'baton.sqlite';

/// 되살리기 직전에 남기는 기존 DB 사본. 실패하면 이 파일로 되돌림.
const _dbBackupName = 'baton.sqlite.pre-restore';

/// 되살리기 직전에 옆으로 밀어 두는 기존 악보 디렉토리.
const _scoresBackupName = 'scores.pre-restore';

/// 내보낸 백업을 모아 두는 임시 디렉토리 이름. 다음 내보내기 때 통째로 비움.
const _exportDirName = 'baton-export';

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

    final scores = Directory(AppPaths.abs('scores'));
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

/// 백업 zip을 풀어 되살림. 되살린 뒤에는 앱을 다시 시작해야 새 DB가 열림.
/// 합치기가 아니라 교체임. 기존 DB와 악보 디렉토리를 옆으로 밀어 두고 새로 풀며,
/// 도중에 실패하면 밀어 둔 것을 그대로 되돌림.
/// zip 전체를 메모리에 올리지 않고 항목마다 흘려 씀. 악보 수백 장이면 수백 MB가 됨.
Future<void> importBackup(File zip, BatonDatabase db) async {
  final input = InputFileStream(zip.path);
  try {
    final archive = ZipDecoder().decodeStream(input);

    final hasDb = archive.files.any((f) => f.isFile && f.name == _dbFileName);
    if (!hasDb) {
      throw const FormatException('백업 파일이 아님: $_dbFileName 이 없음');
    }

    final root = AppPaths.abs('');
    // 어디에 쓰일지 먼저 전부 검사함. 절반만 풀린 상태로 실패하지 않게 함
    final planned = <ArchiveFile, String>{};
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final target = p.normalize(p.join(root, f.name));
      // zip 안의 이름이 ../ 로 바깥을 가리킬 수 있음. 앱 디렉토리를 벗어나면 거부
      if (!p.isWithin(root, target)) {
        throw FormatException('백업에 앱 디렉토리 밖을 가리키는 경로가 있음: ${f.name}');
      }
      planned[f] = target;
    }

    // WAL에만 있는 최근 변경까지 본 파일에 넣고 닫아야 사본이 온전함
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    await db.close();

    final current = File(AppPaths.abs(_dbFileName));
    final dbBackup = File(AppPaths.abs(_dbBackupName));
    final scores = Directory(AppPaths.abs('scores'));
    final scoresBackup = Directory(AppPaths.abs(_scoresBackupName));

    // 지난 되살리기가 남긴 사본은 여기서 정리함. 남겨 두면 이번 되돌리기가 옛 상태로 감
    if (await dbBackup.exists()) await dbBackup.delete();
    if (await scoresBackup.exists()) await scoresBackup.delete(recursive: true);

    // 밀어 두기부터 try 안에 둠. 밖에 두면 두 번째 rename이 실패했을 때 롤백이 돌지 않아
    // DB가 밀린 이름으로 남고 사용자에겐 라이브러리 전체 소실로 보임
    var dbMoved = false;
    var scoresMoved = false;
    try {
      if (await current.exists()) {
        await current.rename(dbBackup.path);
        dbMoved = true;
      }
      if (await scores.exists()) {
        await scores.rename(scoresBackup.path);
        scoresMoved = true;
      }

      for (final entry in planned.entries) {
        final out = File(entry.value);
        await out.parent.create(recursive: true);
        final sink = OutputFileStream(out.path);
        try {
          entry.key.writeContent(sink);
        } finally {
          await sink.close();
        }
      }
    } catch (_) {
      await _rollback(current, dbBackup, scores, scoresBackup, dbMoved, scoresMoved);
      rethrow;
    }
  } finally {
    await input.close();
  }
}

/// 반쯤 풀린 것을 지우고 밀어 둔 원래 데이터를 되돌림.
/// 밀어 두지 못한 쪽은 원본이 제자리에 그대로 있으므로 손대지 않음.
/// 무조건 지우면 rename이 실패한 경우에 원본을 지우게 되어 되돌릴 것이 없어짐.
Future<void> _rollback(
  File current,
  File dbBackup,
  Directory scores,
  Directory scoresBackup,
  bool dbMoved,
  bool scoresMoved,
) async {
  if (dbMoved) {
    if (await current.exists()) await current.delete();
    if (await dbBackup.exists()) await dbBackup.rename(current.path);
  }
  if (scoresMoved) {
    if (await scores.exists()) await scores.delete(recursive: true);
    if (await scoresBackup.exists()) await scoresBackup.rename(scores.path);
  }
}
