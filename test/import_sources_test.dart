// 가져오기 원천 앞뒤 처리 검증. 사본 정리가 앱 임시 영역 밖의 원본을 지우지 않는지, 잃어버린 스캔을
// 쪽 순서대로 되찾는지, 실패 안내가 영어 원문 대신 할 일을 알려 주는지를 고정함.

import 'dart:io';

import 'package:baton/score/import/import_sources.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('baton-sources-test'));
  tearDown(() => root.deleteSync(recursive: true));

  /// root 아래에 파일을 만듦.
  File make(String rel) => File(p.join(root.path, rel))
    ..createSync(recursive: true)
    ..writeAsStringSync('x');

  test('임시 영역 안의 사본과 그 빈 상위 디렉토리만 지우고 밖의 원본은 둠', () async {
    final copy = make('cache/uuid-1/IMG_0001.jpg');
    final shared = make('cache/file_picker/a.pdf');
    final sibling = make('cache/file_picker/b.pdf');
    final original = make('Pictures/IMG_0002.jpg');

    await deleteTempCopies(
      [copy.path, shared.path, original.path],
      roots: [p.join(root.path, 'cache')],
    );

    expect(copy.existsSync(), isFalse);
    expect(copy.parent.existsSync(), isFalse, reason: '사진마다 만든 디렉토리가 쌓이지 않음');
    expect(shared.existsSync(), isFalse);
    expect(sibling.existsSync(), isTrue, reason: '다른 사본이 든 디렉토리는 지우지 않음');
    expect(original.existsSync(), isTrue, reason: '선택기가 원본 경로를 줬을 수 있음');
  });

  test('남은 스캔 쪽은 찍은 시각과 쪽 번호 순으로 세우고 다른 파일은 뺌', () {
    final ordered = orderLostScanFiles([
      '/p/DOCUMENT_SCAN_10_20260101_120001123.jpg',
      '/p/DOCUMENT_SCAN_2_20260101_120000456.jpg',
      '/p/DOCUMENT_SCAN_9_20260101_120000789.jpg',
      '/p/DOCUMENT_SCAN_0_20251231_235959001.jpg',
      '/p/DOCUMENT_SCAN_20260101_120000.pdf',
      '/p/IMG_0001.jpg',
    ]);
    expect(ordered, [
      '/p/DOCUMENT_SCAN_0_20251231_235959001.jpg',
      '/p/DOCUMENT_SCAN_2_20260101_120000456.jpg',
      '/p/DOCUMENT_SCAN_9_20260101_120000789.jpg',
      '/p/DOCUMENT_SCAN_10_20260101_120001123.jpg',
    ]);
  });

  test('되찾은 사진은 사본을 만든 순서로 세움', () {
    final first = make('b.jpg')..setLastModifiedSync(DateTime(2026, 1, 1, 12, 0, 0));
    final second = make('a.jpg')..setLastModifiedSync(DateTime(2026, 1, 1, 12, 0, 1));
    expect(orderByModified([second.path, first.path, p.join(root.path, '없음.jpg')]), [
      first.path,
      second.path,
    ]);
  });

  test('실패 안내는 원문 대신 할 수 있는 행동을 알려 줌', () {
    expect(
      importErrorMessage(const CunningDocumentScannerException.permissionDenied()),
      contains('설정'),
    );
    expect(importErrorMessage(PlatformException(code: 'photo_access_denied')), contains('설정'));
    expect(
      importErrorMessage(const PdfPasswordException('No password supplied by PasswordProvider.')),
      contains('암호'),
    );
    expect(importErrorMessage(const FormatException('이미지 2번을 읽을 수 없음')), contains('2번'));
    expect(
      importErrorMessage(const FileSystemException('write', '/x', OSError('No space', 28))),
      contains('저장공간'),
    );
    expect(importErrorMessage(StateError('boom')), isNot(contains('boom')));
  });
}
