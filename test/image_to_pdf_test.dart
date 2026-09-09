// 이미지→PDF 정규화 검증. 페이지 비율이 뒤집히면 악보가 찌그러진 채 저장되고 되돌릴 수 없음.
// fixture는 tool/gen_fixtures.py로 재생성함.

import 'dart:io';
import 'dart:typed_data';

import 'package:baton/score/import/image_to_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

void main() {
  final landscape = File('test/fixtures/landscape_200x100.png').readAsBytesSync();
  final portrait = File('test/fixtures/portrait_100x200.png').readAsBytesSync();

  test('PDF 헤더로 시작하고 페이지 수가 이미지 수와 같음', () async {
    final bytes = await imagesToPdf([landscape, portrait, landscape]);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    // Pages 노드의 /Count가 곧 페이지 수
    final text = String.fromCharCodes(bytes);
    final count = RegExp(r'/Count\s*(\d+)').firstMatch(text);
    expect(count, isNotNull);
    expect(int.parse(count!.group(1)!), 3);
  });

  test('페이지 폭은 A4에 맞추고 높이는 이미지 비율을 따름', () async {
    final bytes = await imagesToPdf([landscape]);
    final text = String.fromCharCodes(bytes);
    final w = PdfPageFormat.a4.width;
    final expectedH = w * 100 / 200;
    // MediaBox [0 0 w h] 형태로 기록됨
    final m = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]').firstMatch(text);
    expect(m, isNotNull, reason: 'MediaBox를 찾지 못함');
    expect(double.parse(m!.group(1)!), closeTo(w, 0.5));
    expect(double.parse(m.group(2)!), closeTo(expectedH, 0.5));
  });

  test('세로 이미지는 페이지가 세로로 길어짐', () async {
    final bytes = await imagesToPdf([portrait]);
    final text = String.fromCharCodes(bytes);
    final m = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]').firstMatch(text);
    final w = double.parse(m!.group(1)!);
    final h = double.parse(m.group(2)!);
    expect(h, greaterThan(w));
    expect(h / w, closeTo(2.0, 0.02));
  });

  test('빈 목록은 거부함', () {
    expect(() => imagesToPdf([]), throwsArgumentError);
  });

  test('손상된 이미지는 Error가 새어 나오지 않고 FormatException으로 바뀜', () {
    expect(
      () => imagesToPdf([
        Uint8List.fromList([1, 2, 3, 4]),
      ]),
      throwsA(isA<FormatException>()),
    );
  });
}
