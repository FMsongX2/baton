// 임포트한 이미지를 PDF 한 개로 감쌈. 뷰어·주석·내보내기가 PDF 경로 하나만 타도록 입구에서 정규화함.
// JPEG는 재인코딩 없이 그대로 넣고, 그 밖의 형식은 쪽마다 JPEG로 바꿔 원시 비트맵이 쌓이지 않게 함.

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// JPEG가 아닌 이미지를 바꿀 때와 iOS 스캐너에 요청할 때 쓰는 JPEG 품질(0~100).
const kImportJpegQuality = 90;

/// 이미지 파일들을 백그라운드 isolate에서 PDF로 만듦. 스캔 20쪽을 풀어도 UI isolate가 멈추지 않음.
/// 파일은 한 장씩 읽어 바로 JPEG로 맞추므로 원본 전체나 원시 비트맵 여러 장을 한꺼번에 들지 않음.
Future<Uint8List> imageFilesToPdf(List<String> paths) =>
    Isolate.run(() => imagesToPdf(paths.map((p) => File(p).readAsBytesSync())));

/// 이미지 바이트들을 한 페이지씩 담은 PDF 바이트로 만듦. 순서가 곧 페이지 순서.
/// 페이지 폭은 A4에 맞추고 높이는 이미지 비율을 따라 늘림. 세로로 긴 스캔도 잘리지 않음.
/// 디코드할 수 없는 이미지가 섞여 있으면 조용히 건너뛰지 않고 던짐. 쪽마다 디코드하므로 느림.
Future<Uint8List> imagesToPdf(Iterable<Uint8List> images) async {
  final doc = pw.Document();
  var n = 0;
  for (final raw in images) {
    n++;
    // 사용자가 고른 파일은 손상돼 있을 수 있음. 디코더가 RangeError 같은 Error를 던지므로
    // Exception만 잡으면 앱이 그대로 죽음. 여기서 전부 받아 FormatException으로 바꿈
    final pw.MemoryImage image;
    try {
      image = pw.MemoryImage(asJpeg(raw));
    } catch (_) {
      throw FormatException('이미지 $n번을 읽을 수 없음');
    }
    final iw = image.width;
    final ih = image.height;
    if (iw == null || ih == null || iw <= 0 || ih <= 0) {
      throw FormatException('이미지 $n번의 크기를 읽을 수 없음');
    }
    final w = PdfPageFormat.a4.width;
    final h = w * ih / iw;
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(w, h),
        // 여백 없이 꽉 채움. 여백 크롭은 뷰어 쪽 관심사라 여기서 넣지 않음
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
      ),
    );
  }
  if (n == 0) throw ArgumentError('이미지가 없음');
  return doc.save();
}

/// JPEG면 그대로 돌려주고, 아니면 흰 바탕에 합성해 JPEG로 바꿈. 투명한 곳이 검게 나오지 않게 함.
/// pdf 패키지는 JPEG가 아닌 이미지를 저장이 끝날 때까지 원시 비트맵(A4 스캔 한 쪽에 수십 MB)으로
/// 들고 있으므로, 쪽마다 여기서 바꿔 그 버퍼가 다음 쪽 전에 풀리게 함. 디코드하지 못하면 던짐.
Uint8List asJpeg(Uint8List bytes) {
  if (img.JpegDecoder().isValidFile(bytes)) return bytes;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('이미지를 읽을 수 없음');
  // 회색조·팔레트·16비트를 8비트 RGBA로 먼저 펼침. 합성은 채널 수를 맞춰 주지 않아
  // 회색조 한 채널이 빨강에만 옮겨짐
  final rgba = decoded.convert(format: img.Format.uint8, numChannels: 4);
  final flat = img.Image(width: decoded.width, height: decoded.height);
  img.fill(flat, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(flat, rgba);
  return img.encodeJpg(flat, quality: kImportJpegQuality);
}
