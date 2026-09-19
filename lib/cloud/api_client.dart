// 서버 호출. OpenAI 키와 코인 원장은 서버에만 있으므로 앱은 이 창구로만 접근함.
// 서버 주소는 빌드 때 --dart-define=BATON_API_BASE=... 로 넣음. 비어 있으면 기능이 꺼짐.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const kApiBase = String.fromEnvironment('BATON_API_BASE');

/// 보통 요청의 응답 한도.
const kApiTimeout = Duration(seconds: 20);

/// 분석 요청의 응답 한도. 서버가 모델 호출을 210초(analyze.ts ANALYSIS_BUDGET_MS) 안에 끝내므로
/// 그보다 이미지를 올리는 시간만큼 길게 잡음. 한도는 기다림만 끝내고 연결은 닫지 않아 서버는 끝까지
/// 돌고 결과를 남김. 같은 id로 다시 보내면 409를 받다가 저장된 결과를 받음. 연결이 실제로
/// 끊기면(네트워크 단절·앱 종료) 워커가 취소돼, 선점 기한 뒤의 재전송이 모델을 다시 부름.
const kAnalyzeTimeout = Duration(minutes: 5);

/// 분석 요청을 같은 requestId로 다시 보내기 전 대기. 합쳐 1분 남짓 기다리고 그래도 안 되면 포기함.
/// 서버가 결과를 들고 있거나 아직 처리 중일 수 있어, 새 id로 다시 누르면 코인이 또 빠짐.
const kAnalyzeRetryDelays = [
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 20),
  Duration(seconds: 30),
];

/// 사용자가 분석을 멈춤. 재전송하지 않고 결과도 기다리지 않음. 보낸 요청의 연결은 닫지 않음.
class AnalysisCancelled implements Exception {
  /// 멈춤 신호를 만듦.
  const AnalysisCancelled();

  /// 사람이 읽는 멈춤 사유.
  @override
  String toString() => '분석을 멈춤';
}

/// 이미 멈췄으면 work를 시작하지 않고 [AnalysisCancelled]를 던짐. 아니면 work를 시작해 cancel과 먼저
/// 끝난 쪽을 따름. cancel이 먼저면 [AnalysisCancelled]를 던지고 work는 버림.
Future<T> untilCancelled<T>(Future<T> Function() work, Completer<void>? cancel) async {
  if (cancel == null) return work();
  // Future만으로는 이미 끝났는지 알 수 없어 Completer로 받음. 시작한 요청은 멈춰도 서버에 닿아 코인이 빠짐
  if (cancel.isCompleted) throw const AnalysisCancelled();
  return Future.any([work(), cancel.future.then<T>((_) => throw const AnalysisCancelled())]);
}

/// 서버가 보낸 사람이 읽을 수 있는 오류. 화면에 그대로 띄움.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.balance, this.needed});

  final String message;
  final int? statusCode;

  /// 코인이 모자랄 때 서버가 함께 알려 주는 값.
  final int? balance;
  final int? needed;

  bool get isInsufficientCoins => statusCode == 402 && needed != null;

  /// 같은 요청을 그대로 다시 보내면 되는 실패인지. 전송이 끊겨 결과를 못 받았거나(상태 코드 없음),
  /// 서버가 같은 요청을 아직 처리 중이거나(409), 일시 오류(500·503·504)인 경우.
  /// 402·422와 환불을 마친 502는 다시 보내도 결과가 같음.
  bool get isRetryable =>
      statusCode == null ||
      statusCode == 409 ||
      statusCode == 500 ||
      statusCode == 503 ||
      statusCode == 504;

  @override
  String toString() => message;
}

class DeviceIdentity {
  const DeviceIdentity({
    required this.userId,
    required this.token,
    required this.balance,
    this.recoveryCode,
  });

  final String userId;
  final String token;
  final int balance;

  /// 등록 직후 한 번만 서버가 평문으로 줌. 다른 기기로 옮길 때 씀.
  final String? recoveryCode;
}

class CoinPack {
  const CoinPack({required this.productId, required this.coins});

  final String productId;
  final int coins;
}

class Pricing {
  const Pricing({required this.coinsPerPage, required this.packs, required this.maxPagesPerCall});

  final int coinsPerPage;
  final List<CoinPack> packs;
  final int maxPagesPerCall;
}

/// 한 페이지의 분석 결과.
class PageAnalysis {
  const PageAnalysis({required this.page, required this.bars, required this.confidence});

  /// 1부터 세는 쪽 번호. 서버에 보낸 값 그대로 돌아옴.
  final int page;
  final int bars;

  /// high / medium / low. 낮으면 사용자에게 확인을 권함.
  final String confidence;
}

class ScoreAnalysis {
  /// 서버 분석 응답 하나를 담음.
  const ScoreAnalysis({
    required this.pages,
    required this.bpm,
    required this.bpmSource,
    required this.timeSigNum,
    required this.timeSigDen,
    required this.coinsSpent,
    required this.balance,
    this.bpmUnit,
  });

  final List<PageAnalysis> pages;

  /// 악보에 적힌 숫자 그대로. 단위는 [bpmUnit]이라 앱의 클릭 템포와 다를 수 있음.
  final double? bpm;

  /// 템포 표기의 음표 단위. quarter, dotted_quarter, half, eighth 등. 읽지 못했으면 null.
  final String? bpmUnit;

  /// marking(악보에 숫자 표기) / tempo_word(용어만, bpm 없음) / none(표기 없음).
  final String bpmSource;
  final int? timeSigNum;
  final int? timeSigDen;
  final int coinsSpent;
  final int balance;

  /// 확신이 낮다고 표시된 쪽 수. 사용자에게 검토를 권할 때 씀.
  int get lowConfidenceCount => pages.where((p) => p.confidence == 'low').length;
}

/// 서버가 토큰을 모른다고 답한 경우. 기기를 옮기면 옛 토큰이 무효가 되므로
/// 호출자가 이걸 보고 다시 등록해야 함.
class ApiUnauthorized extends ApiException {
  ApiUnauthorized(super.message) : super(statusCode: 401);
}

class ApiClient {
  /// 서버 창구를 만듦. 통신 대역과 재시도 간격은 테스트가 바꿈.
  ApiClient({
    http.Client? httpClient,
    this.baseUrl = kApiBase,
    this.timeout = kApiTimeout,
    this.analyzeRetryDelays = kAnalyzeRetryDelays,
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String baseUrl;

  /// 응답을 기다리는 한도. 없으면 끊긴 회선에서 화면이 영영 진행 중으로 남음.
  final Duration timeout;

  /// 분석을 같은 requestId로 다시 보내기 전 대기. 길이가 곧 재시도 횟수.
  final List<Duration> analyzeRetryDelays;

  /// 서버 주소가 주입되지 않았으면 기능을 통째로 감춤.
  bool get configured => baseUrl.isNotEmpty;

  /// 요청 하나를 보내며 한도를 검. 끊기면 사용자에게 보일 문구로 바꿔 던짐.
  Future<http.Response> _send(Future<http.Response> Function() request, {Duration? limit}) async {
    try {
      return await request().timeout(limit ?? timeout);
    } on TimeoutException {
      throw ApiException('서버가 응답하지 않음. 잠시 뒤 다시 시도');
    } on http.ClientException catch (e) {
      throw ApiException('서버에 연결하지 못함: ${e.message}');
    }
  }

  /// 응답을 해석하고 오류면 사용자에게 보일 메시지로 바꿔 던짐.
  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('서버 응답을 읽지 못함', statusCode: res.statusCode);
    }
    if (res.statusCode == 401) {
      throw ApiUnauthorized((body['error'] as String?) ?? '인증이 필요함');
    }
    if (res.statusCode >= 400) {
      throw ApiException(
        (body['error'] as String?) ?? '요청이 거절됨',
        statusCode: res.statusCode,
        balance: (body['balance'] as num?)?.toInt(),
        needed: (body['needed'] as num?)?.toInt(),
      );
    }
    return body;
  }

  Map<String, String> _headers(String? token) => {
    'content-type': 'application/json',
    if (token != null) 'authorization': 'Bearer $token',
  };

  /// 새 기기를 등록해 사용자 id와 토큰, 복구 코드를 받음.
  Future<DeviceIdentity> registerDevice() async {
    final res = await _send(
      () => _http.post(Uri.parse('$baseUrl/v1/device/register'), headers: _headers(null)),
    );
    final body = _decode(res);
    return DeviceIdentity(
      userId: body['userId'] as String,
      token: body['token'] as String,
      balance: (body['balance'] as num).toInt(),
      recoveryCode: body['recoveryCode'] as String?,
    );
  }

  /// 복구 코드로 다른 기기의 코인을 이 기기로 옮김.
  Future<DeviceIdentity> restoreDevice(String recoveryCode) async {
    final res = await _send(
      () => _http.post(
        Uri.parse('$baseUrl/v1/device/restore'),
        headers: _headers(null),
        body: jsonEncode({'recoveryCode': recoveryCode}),
      ),
    );
    final body = _decode(res);
    return DeviceIdentity(
      userId: body['userId'] as String,
      token: body['token'] as String,
      balance: (body['balance'] as num).toInt(),
    );
  }

  /// 복구 코드를 새로 발급받음. 서버는 해시만 들고 있어 이 응답이 평문을 보는 유일한 기회임.
  /// 받은 코드는 [confirmRecoveryCode] 전까지 대기 상태이고 이전 코드가 그대로 통함.
  Future<String> issueRecoveryCode(String token) async {
    final res = await _send(
      () => _http.post(Uri.parse('$baseUrl/v1/device/recovery'), headers: _headers(token)),
    );
    return (_decode(res))['recoveryCode'] as String;
  }

  /// 받아 적은 대기 코드를 적용함. 이 순간부터 이전 코드는 무효가 됨.
  /// 같은 코드로 다시 보내도 결과가 같아 응답이 유실되면 그대로 재시도하면 됨.
  Future<void> confirmRecoveryCode(String token, String recoveryCode) async {
    final res = await _send(
      () => _http.post(
        Uri.parse('$baseUrl/v1/device/recovery/confirm'),
        headers: _headers(token),
        body: jsonEncode({'recoveryCode': recoveryCode}),
      ),
    );
    _decode(res);
  }

  /// 코인 잔액을 다시 읽음.
  Future<int> balance(String token) async {
    final res = await _send(
      () => _http.get(Uri.parse('$baseUrl/v1/balance'), headers: _headers(token)),
    );
    return ((_decode(res))['balance'] as num).toInt();
  }

  /// 쪽당 가격과 코인 묶음 목록. 값을 앱에 박지 않고 서버에서 받아 씀.
  Future<Pricing> pricing() async {
    final res = await _send(
      () => _http.get(Uri.parse('$baseUrl/v1/pricing'), headers: _headers(null)),
    );
    final body = _decode(res);
    return Pricing(
      coinsPerPage: (body['coinsPerPage'] as num).toInt(),
      maxPagesPerCall: (body['maxPagesPerCall'] as num).toInt(),
      packs: [
        for (final p in (body['packs'] as List).cast<Map<String, dynamic>>())
          CoinPack(productId: p['productId'] as String, coins: (p['coins'] as num).toInt()),
      ],
    );
  }

  /// 스토어 영수증을 서버에 넘겨 코인을 받음. 같은 영수증을 다시 보내도 한 번만 적립됨.
  Future<int> redeemPurchase(
    String token, {
    required String platform,
    required String productId,
    required String purchaseToken,
  }) async {
    final res = await _send(
      () => _http.post(
        Uri.parse('$baseUrl/v1/purchase'),
        headers: _headers(token),
        body: jsonEncode({
          'platform': platform,
          'productId': productId,
          'purchaseToken': purchaseToken,
        }),
      ),
    );
    return ((_decode(res))['balance'] as num).toInt();
  }

  /// 페이지 이미지를 넘겨 쪽별 마디수와 템포를 받음. 코인은 서버가 먼저 빼고 실패하면 되돌려 줌.
  /// requestId는 재시도를 구분하는 열쇠. 같은 값으로 다시 부르면 코인이 두 번 빠지지 않고
  /// 이미 끝난 분석이면 저장된 결과가 그대로 옴. 그래서 결과를 못 받은 실패([ApiException.isRetryable])는
  /// [analyzeRetryDelays]만큼 같은 id로 다시 보냄. 본문은 한 번만 만들어 재시도에 그대로 씀.
  /// cancel이 완료되면 새 요청을 시작하지 않고 기다림과 재전송을 멈춘 뒤 [AnalysisCancelled]를 던짐.
  Future<ScoreAnalysis> analyze(
    String token, {
    required String requestId,
    required List<({int index, Uint8List png})> pages,
    Completer<void>? cancel,
  }) async {
    final body = jsonEncode({
      'requestId': requestId,
      'pages': [
        for (final p in pages)
          {'index': p.index, 'mediaType': 'image/png', 'base64': base64Encode(p.png)},
      ],
    });
    for (var attempt = 0; ; attempt++) {
      try {
        // 멈춰도 보낸 요청은 닫지 않음. 서버가 끝까지 돌아 남긴 결과를 다음에 같은 id로 받음
        final res = await untilCancelled(
          () => _send(
            () =>
                _http.post(Uri.parse('$baseUrl/v1/analyze'), headers: _headers(token), body: body),
            limit: kAnalyzeTimeout,
          ),
          cancel,
        );
        return _parseAnalysis(_decode(res));
      } on ApiException catch (e) {
        if (!e.isRetryable || attempt >= analyzeRetryDelays.length) rethrow;
        await untilCancelled(() => Future<void>.delayed(analyzeRetryDelays[attempt]), cancel);
      }
    }
  }

  /// 분석 응답 본문을 읽음.
  ScoreAnalysis _parseAnalysis(Map<String, dynamic> body) => ScoreAnalysis(
    pages: [
      for (final p in (body['pages'] as List).cast<Map<String, dynamic>>())
        PageAnalysis(
          page: (p['page'] as num).toInt(),
          bars: (p['bars'] as num).toInt(),
          confidence: p['confidence'] as String,
        ),
    ],
    bpm: (body['bpm'] as num?)?.toDouble(),
    bpmUnit: body['bpmUnit'] as String?,
    bpmSource: body['bpmSource'] as String? ?? 'none',
    timeSigNum: (body['timeSigNum'] as num?)?.toInt(),
    timeSigDen: (body['timeSigDen'] as num?)?.toInt(),
    coinsSpent: (body['coinsSpent'] as num?)?.toInt() ?? 0,
    balance: (body['balance'] as num?)?.toInt() ?? 0,
  );
}
