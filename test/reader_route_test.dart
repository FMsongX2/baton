// 리더·폴더 복원 경로의 인자 계약. 프로세스가 죽은 뒤 Navigator가 인자만으로 같은 화면을 다시 열 수 있는지,
// 인자가 플랫폼에 저장될 수 있는 값인지, 앱 갱신으로 바뀌는 절대 경로 대신 상대 경로를 싣는지를 고정함.

import 'dart:io';

import 'package:baton/core/storage/paths.dart';
import 'package:baton/library/library_page.dart';
import 'package:baton/reader/reader_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('복원 경로는 저장 가능한 인자만으로 같은 악보를 다시 엶', (tester) async {
    AppPaths.overrideDocuments(Directory('/docs'));
    final args = ReaderPage.routeArguments(scoreId: 7, fileRel: 'scores/7/source.pdf', title: '곡');
    // 플랫폼 복원 데이터로 나가는 값이라 표준 코덱으로 인코딩되지 않으면 복원이 통째로 실패함
    expect(() => const StandardMessageCodec().encodeMessage(args), returnsNormally);
    expect(args.values.whereType<String>().any((v) => v.startsWith('/')), isFalse);

    await tester.pumpWidget(const Placeholder());
    final context = tester.element(find.byType(Placeholder));
    final route = ReaderPage.restorableRoute(context, args) as MaterialPageRoute<void>;
    final page = route.builder(context) as ReaderPage;
    expect(page.scoreId, 7);
    expect(page.pdfPath, '/docs/scores/7/source.pdf');
    expect(page.title, '곡');
  });

  testWidgets('폴더 복원 경로는 저장 가능한 인자만으로 같은 폴더를 엶', (tester) async {
    // 폴더 화면이 복원돼야 그 위에서 연 리더도 복원됨
    const args = <String, Object?>{'folderId': 3, 'title': '연습곡'};
    expect(() => const StandardMessageCodec().encodeMessage(args), returnsNormally);

    await tester.pumpWidget(const Placeholder());
    final context = tester.element(find.byType(Placeholder));
    final route = LibraryPage.restorableRoute(context, args) as MaterialPageRoute<void>;
    final page = route.builder(context) as LibraryPage;
    expect(page.folderId, 3);
    expect(page.title, '연습곡');
  });
}
