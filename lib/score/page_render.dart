// PDF 페이지를 PNG 바이트로 굽는 공용 경로. 목록 썸네일과 AI 분석이 같은 코드를 씀.
// 분석에 보내는 이미지는 마디선이 살아 있어야 하므로 썸네일보다 크게 뽑음.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

/// 목록 카드에 쓰는 가로 픽셀.
const kThumbWidth = 360;

/// 분석에 보내는 가로 픽셀. Claude가 긴 변 1568px까지 그대로 보므로 그 아래로 잡되
/// 마디선과 도돌이표가 뭉개지지 않을 만큼은 남김.
const kAnalyzeWidth = 1400;

/// PDF 한 페이지를 PNG 바이트로 렌더함. 열지 못하거나 범위를 벗어나면 null.
Future<Uint8List?> renderPagePng(String pdfPath, int pageIndex, int width) async {
  try {
    final doc = await PdfDocument.openFile(pdfPath);
    try {
      if (pageIndex < 0 || pageIndex >= doc.pages.length) return null;
      final page = doc.pages[pageIndex];
      final height = (width * page.height / page.width).round();
      final rendered = await page.render(
        fullWidth: width.toDouble(),
        fullHeight: height.toDouble(),
        backgroundColor: 0xFFFFFFFF,
      );
      if (rendered == null) return null;
      try {
        final image = await rendered.createImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data?.buffer.asUint8List();
      } finally {
        rendered.dispose();
      }
    } finally {
      await doc.dispose();
    }
  } catch (e) {
    debugPrint('페이지 렌더 실패 ($pageIndex): $e');
    return null;
  }
}

/// PDF를 한 번만 열고 여러 쪽을 이어서 렌더함. 쪽마다 파일을 다시 여는 비용을 없앰.
/// 렌더에 실패한 쪽은 결과에서 빠지므로 호출자가 개수를 확인해야 함.
Future<List<({int index, Uint8List png})>> renderPages(
  String pdfPath,
  List<int> indices,
  int width, {
  void Function(int done, int total)? onProgress,
}) async {
  final out = <({int index, Uint8List png})>[];
  try {
    final doc = await PdfDocument.openFile(pdfPath);
    try {
      for (var i = 0; i < indices.length; i++) {
        final index = indices[i];
        if (index < 0 || index >= doc.pages.length) continue;
        final page = doc.pages[index];
        final height = (width * page.height / page.width).round();
        final rendered = await page.render(
          fullWidth: width.toDouble(),
          fullHeight: height.toDouble(),
          backgroundColor: 0xFFFFFFFF,
        );
        if (rendered != null) {
          try {
            final image = await rendered.createImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            if (data != null) {
              out.add((index: index, png: data.buffer.asUint8List()));
            }
          } finally {
            rendered.dispose();
          }
        }
        onProgress?.call(i + 1, indices.length);
      }
    } finally {
      await doc.dispose();
    }
  } catch (e) {
    debugPrint('페이지 묶음 렌더 실패: $e');
  }
  return out;
}
