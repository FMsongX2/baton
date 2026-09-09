// 백업 왕복과 악성 zip 방어 검증. 사용자가 고른 zip을 푸는 자리라 신뢰 경계이며,
// 경로 검사를 빠뜨리면 앱 디렉토리 밖에 파일을 쓸 수 있음.

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:baton/core/db/database.dart';
import 'package:baton/core/storage/backup.dart';
import 'package:baton/core/storage/paths.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late BatonDatabase db;

  setUp(() {
    root = Directory.systemTemp.createTempSync('baton-backup-test');
    AppPaths.overrideDocuments(root);
    db = BatonDatabase.forTesting(NativeDatabase.memory());
    // drift_flutter가 두는 위치를 흉내 냄
    File(p.join(root.path, 'baton.sqlite')).writeAsStringSync('DBDATA');
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

    final db2 = BatonDatabase.forTesting(NativeDatabase.memory());
    await importBackup(zip, db2);

    expect(File(p.join(root.path, 'scores', '7', 'source.pdf')).readAsStringSync(), 'PDFDATA');
    expect(File(p.join(root.path, 'baton.sqlite')).readAsStringSync(), 'DBDATA');
  });

  test('되살리기 전에 기존 DB 사본을 남김', () async {
    final zip = await exportBackup(db, outPath: p.join(root.path, 'out.zip'));
    File(p.join(root.path, 'baton.sqlite')).writeAsStringSync('되살리기 직전 상태');

    final db2 = BatonDatabase.forTesting(NativeDatabase.memory());
    await importBackup(zip, db2);

    final saved = File(p.join(root.path, 'baton.sqlite.pre-restore'));
    expect(saved.existsSync(), isTrue);
    expect(saved.readAsStringSync(), '되살리기 직전 상태');
  });

  test('앱 디렉토리 밖을 가리키는 zip은 거부하고 파일을 쓰지 않음', () async {
    final evil = File(p.join(root.path, 'evil.zip'));
    final enc = ZipFileEncoder()..create(evil.path);
    final payload = File(p.join(root.path, 'payload.txt'))..writeAsStringSync('X');
    await enc.addFile(payload, 'baton.sqlite');
    await enc.addFile(payload, '../../escaped.txt');
    await enc.close();

    final db2 = BatonDatabase.forTesting(NativeDatabase.memory());
    await expectLater(importBackup(evil, db2), throwsA(isA<FormatException>()));
    expect(File(p.join(root.parent.path, 'escaped.txt')).existsSync(), isFalse);
    expect(
      File(p.join(root.path, 'baton.sqlite')).readAsStringSync(),
      'DBDATA',
      reason: '검사에 걸리면 아무것도 쓰지 않아야 함',
    );
  });

  test('DB가 없는 zip은 백업으로 보지 않음', () async {
    final notBackup = File(p.join(root.path, 'other.zip'));
    final enc = ZipFileEncoder()..create(notBackup.path);
    final f = File(p.join(root.path, 'x.txt'))..writeAsStringSync('X');
    await enc.addFile(f, 'x.txt');
    await enc.close();

    final db2 = BatonDatabase.forTesting(NativeDatabase.memory());
    await expectLater(importBackup(notBackup, db2), throwsA(isA<FormatException>()));
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

  test('되살리기가 도중에 실패하면 원래 데이터로 돌아감', () async {
    // 디렉토리 자리에 같은 이름의 파일을 쓰게 만들어 풀기 중간에 실패시킴
    final broken = File(p.join(root.path, 'broken.zip'));
    final encoder = ZipFileEncoder()..create(broken.path);
    await encoder.addFile(File(p.join(root.path, 'baton.sqlite')), 'baton.sqlite');
    await encoder.addFile(File(p.join(root.path, 'baton.sqlite')), 'scores/1/source.pdf');
    await encoder.addFile(File(p.join(root.path, 'baton.sqlite')), 'scores/1');
    await encoder.close();

    await expectLater(
      importBackup(broken, BatonDatabase.forTesting(NativeDatabase.memory())),
      throwsA(anything),
    );

    expect(File(p.join(root.path, 'baton.sqlite')).readAsStringSync(), 'DBDATA');
    expect(File(p.join(root.path, 'scores', '7', 'source.pdf')).readAsStringSync(), 'PDFDATA');
    // 반쯤 풀린 것이 남아 있으면 안 됨
    expect(Directory(p.join(root.path, 'scores', '1')).existsSync(), isFalse);
  });

  test('악보 밀어 두기가 실패해도 원본 악보를 지우지 않음', () async {
    final zip = await exportBackup(db, outPath: p.join(root.path, 'out.zip'));

    // scores.pre-restore 자리에 파일을 미리 둠. 디렉토리를 그 이름으로 rename할 수 없어
    // DB만 밀린 상태에서 실패함. 롤백이 원본 악보를 지우면 되돌릴 것이 없어짐
    File(p.join(root.path, 'scores.pre-restore')).writeAsStringSync('걸림돌');

    await expectLater(
      importBackup(zip, BatonDatabase.forTesting(NativeDatabase.memory())),
      throwsA(anything),
    );

    expect(File(p.join(root.path, 'baton.sqlite')).readAsStringSync(), 'DBDATA');
    expect(File(p.join(root.path, 'scores', '7', 'source.pdf')).readAsStringSync(), 'PDFDATA');
  });
}
