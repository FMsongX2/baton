// 임포트한 이미지를 PDF 한 개로 감쌈. 뷰어·주석·내보내기가 PDF 경로 하나만 타도록 입구에서 정규화함.
// JPEG는 pdf 패키지가 재인코딩 없이 그대로 임베드하므로 화질과 용량이 유지됨.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 이미지 바이트들을 한 페이지씩 담은 PDF 바이트로 만듦.
/// 페이지 폭은 A4에 맞추고 높이는 이미지 비율을 따라 늘림. 세로로 긴 스캔도 잘리지 않음.
/// 디코드할 수 없는 이미지가 섞여 있으면 조용히 건너뛰지 않고 던짐.
Future<Uint8List> imagesToPdf(List<Uint8List> images) async {
  if (images.isEmpty) throw ArgumentError('이미지가 없음');
  final doc = pw.Document();
  for (var i = 0; i < images.length; i++) {
    // 사용자가 고른 파일은 손상돼 있을 수 있음. 디코더가 RangeError 같은 Error를 던지므로
    // Exception만 잡으면 앱이 그대로 죽음. 여기서 전부 받아 FormatException으로 바꿈
    final pw.MemoryImage img;
    try {
      img = pw.MemoryImage(images[i]);
    } catch (_) {
      throw FormatException('이미지 ${i + 1}번을 읽을 수 없음');
    }
    final iw = img.width;
    final ih = img.height;
    if (iw == null || ih == null || iw <= 0 || ih <= 0) {
      throw FormatException('이미지 ${i + 1}번의 크기를 읽을 수 없음');
    }
    final w = PdfPageFormat.a4.width;
    final h = w * ih / iw;
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(w, h),
        // 여백 없이 꽉 채움. 여백 크롭은 뷰어 쪽 관심사라 여기서 넣지 않음
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(img, fit: pw.BoxFit.fill),
      ),
    );
  }
  return doc.save();
}
