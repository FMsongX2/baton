// 이미지→PDF 정규화 검증. 페이지 비율이 뒤집히면 악보가 찌그러진 채 저장되고 되돌릴 수 없음.
// fixture는 tool/gen_fixtures.py로 재생성함.

import 'dart:io';
import 'dart:typed_data';

import 'package:baton/score/import/image_to_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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

  test('PNG는 JPEG로 바꿔 넣어 원시 비트맵과 알파 마스크를 싣지 않음', () async {
    final text = String.fromCharCodes(await imagesToPdf([landscape]));
    expect(text, contains('/DCTDecode'));
    expect(text, isNot(contains('/SMask')), reason: '스캔 한 쪽마다 원시 버퍼가 저장 끝까지 남던 경로');
  });

  test('JPEG는 다시 인코딩하지 않음', () {
    final jpeg = img.encodeJpg(img.Image(width: 8, height: 8));
    expect(identical(asJpeg(jpeg), jpeg), isTrue);
  });

  test('투명한 곳은 검게가 아니라 흰 바탕으로 채움', () {
    final clear = img.Image(width: 4, height: 4, numChannels: 4);
    final out = img.decodeJpg(asJpeg(img.encodePng(clear)))!;
    final px = out.getPixel(1, 1);
    expect(px.r, greaterThan(245));
    expect(px.g, greaterThan(245));
    expect(px.b, greaterThan(245));
  });

  test('회색조와 16비트 PNG도 밝기를 유지함', () {
    final gray = img.Image(width: 4, height: 4, numChannels: 1);
    img.fill(gray, color: img.ColorUint8.rgb(100, 100, 100));
    final g = img.decodeJpg(asJpeg(img.encodePng(gray)))!.getPixel(1, 1);
    expect(g.r, closeTo(100, 4));
    expect(g.b, closeTo(100, 4), reason: '한 채널만 옮겨 붉게 나오면 안 됨');

    final deep = img.Image(width: 4, height: 4, format: img.Format.uint16);
    for (final px in deep) {
      px
        ..r = 0x8000
        ..g = 0x8000
        ..b = 0x8000;
    }
    final d = img.decodeJpg(asJpeg(img.encodePng(deep)))!.getPixel(1, 1);
    expect(d.r, closeTo(128, 4));
  });

  test('파일 목록은 백그라운드 isolate에서 읽어 한 PDF로 묶음', () async {
    final bytes = await imageFilesToPdf([
      'test/fixtures/landscape_200x100.png',
      'test/fixtures/portrait_100x200.png',
    ]);
    final count = RegExp(r'/Count\s*(\d+)').firstMatch(String.fromCharCodes(bytes));
    expect(int.parse(count!.group(1)!), 2);
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
