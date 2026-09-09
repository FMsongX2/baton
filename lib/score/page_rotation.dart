// 페이지 회전. 뷰어가 회전 프록시 페이지를 받지 않으므로 PDF 파일에 구워 넣음.
// 필기는 페이지 정규 좌표라 같은 각도로 함께 돌리고, 굵기는 폭 기준이라 종횡비로 보정함.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:pdfrx/pdfrx.dart';

import '../reader/annotation/stroke.dart';

/// 정규 좌표(0~1) 점을 시계방향으로 90도씩 quarterTurns만큼 돌림.
/// 좌상단이 우상단으로 가는 방향. 회전 후에도 0~1 범위를 유지함.
Offset rotateNormalized(Offset p, int quarterTurns) {
  switch (quarterTurns & 3) {
    case 1:
      return Offset(1 - p.dy, p.dx);
    case 2:
      return Offset(1 - p.dx, 1 - p.dy);
    case 3:
      return Offset(p.dy, 1 - p.dx);
    default:
      return p;
  }
}

/// 획 하나를 돌림. aspect는 회전 전 페이지의 가로/세로 비.
/// 굵기는 페이지 폭 대비 비율이라 90·270도에서 기준 폭이 바뀌므로 함께 보정함.
Stroke rotateStroke(Stroke s, int quarterTurns, double aspect) {
  final turns = quarterTurns & 3;
  final swapped = turns.isOdd;
  return Stroke(
    tool: s.tool,
    color: s.color,
    width: swapped ? s.width * aspect : s.width,
    points: [for (final p in s.points) rotateNormalized(p, turns)],
    pressures: s.pressures,
  );
}

/// PDF 한 페이지를 돌려 같은 경로에 다시 씀.
/// 임시 파일에 먼저 쓰고 바꿔치기해 도중에 죽어도 원본이 반쯤 망가지지 않게 함.
/// 바꿔치기 전에 새 파일이 열리는지 확인함. 악보는 잃으면 되돌릴 방법이 없음.
Future<void> rotatePdfPage(String path, int pageIndex, int quarterTurns) async {
  final turns = quarterTurns & 3;
  if (turns == 0) return;

  final delta = PdfPageRotation.values[turns];
  final doc = await PdfDocument.openFile(path);
  final Uint8List bytes;
  final int pageCount;
  try {
    if (pageIndex < 0 || pageIndex >= doc.pages.length) {
      throw RangeError('페이지 범위를 벗어남: $pageIndex');
    }
    pageCount = doc.pages.length;
    final pages = [...doc.pages];
    pages[pageIndex] = pages[pageIndex].rotatedBy(delta);
    doc.pages = pages;
    bytes = await doc.encodePdf();
  } finally {
    await doc.dispose();
  }

  final tmp = File('$path.rotating');
  await tmp.writeAsBytes(bytes, flush: true);
  try {
    await _verifyPdf(tmp.path, pageCount);
  } catch (_) {
    await tmp.delete();
    rethrow;
  }
  await tmp.rename(path);
}

/// 만들어진 PDF가 열리고 페이지 수가 그대로인지 확인함. 아니면 던짐.
Future<void> _verifyPdf(String path, int expectedPages) async {
  final doc = await PdfDocument.openFile(path);
  try {
    if (doc.pages.length != expectedPages) {
      throw FormatException('회전 결과의 페이지 수가 다름: ${doc.pages.length} != $expectedPages');
    }
  } finally {
    await doc.dispose();
  }
}

/// 회전 전 페이지의 가로/세로 비를 읽음. 획 굵기 보정에 씀.
Future<double> pageAspect(String path, int pageIndex) async {
  final doc = await PdfDocument.openFile(path);
  try {
    final page = doc.pages[pageIndex];
    return page.height == 0 ? 1.0 : page.width / page.height;
  } finally {
    await doc.dispose();
  }
}
