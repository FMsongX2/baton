// 광고 동의(UMP)·SDK 초기화와 앱 하단 배너 칸. 광고 상태는 이 파일만 소유함.
// 동의 확인 전에는 광고 요청이 나가지 않음. 악보 뷰어가 떠 있는 동안에는 배너 칸을 뺌.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 배너 광고 단위. 디버그·프로필은 공식 테스트 단위를 씀. 개발 중에 실제 단위를 누르면
/// 무효 트래픽으로 계정이 막힐 수 있음. 릴리스는 --dart-define=BATON_AD_BANNER로 받고 비면 광고를 끔.
String get _bannerUnitId {
  if (kReleaseMode) return const String.fromEnvironment('BATON_AD_BANNER');
  return Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-3940256099942544/2934735716';
}

/// 배너 크기. 작은 상자로 고정함. adaptive는 태블릿에서 높이가 150까지 커짐.
const _bannerSize = AdSize.banner;

/// 광고와 위쪽 화면 사이의 누를 수 없는 띠. 내비게이션 바에서 광고를 떼어 오터치를 줄임.
const _gapHeight = 8.0;

/// 새 광고 요청 사이 최소 간격. 화면을 오갈 때 요청을 남발하지 않도록 AdMob 권장치를 따름.
const _minRequestGap = Duration(seconds: 60);

/// 광고 동의·초기화 상태. 앱 전역에 하나만 있어야 하므로 정적 멤버로 둠.
abstract final class Ads {
  /// 동의가 확보되고 SDK 초기화가 끝나 광고를 요청해도 되는지.
  static final ready = ValueNotifier<bool>(false);

  /// 설정 화면에 개인정보 옵션 항목을 보여야 하는지. UMP가 요구하는 지역에서만 켜짐.
  static final privacyOptionsRequired = ValueNotifier<bool>(false);

  /// 배너를 내려야 하는 화면(악보 뷰어)이 몇 개 떠 있는지.
  static final suppressors = ValueNotifier<int>(0);

  /// 대화상자·시트가 몇 개 떠 있는지. 그동안 배너를 덮음.
  static final _modals = ValueNotifier<int>(0);

  /// AdFrame이 다시 그려야 하는 상태를 한데 묶음. 빌드마다 새로 만들면 구독이 매번 바뀜.
  static final _layout = Listenable.merge([ready, suppressors, _modals]);

  /// MaterialApp.navigatorObservers에 넣음. 대화상자·시트가 열리고 닫히는 것을 셈.
  static final modalObserver = _ModalObserver();

  static Future<InitializationStatus>? _init;

  /// 요청 간격을 재는 단조 시계. 벽시계는 사용자가 시간을 되돌리면 간격이 한없이 늘어남.
  static final _uptime = Stopwatch()..start();
  static Duration? _lastRequest;

  /// 앱 실행마다 한 번 부름. 동의 정보를 갱신하고 필요하면 동의 폼을 띄운 뒤 SDK를 올림.
  /// 릴리스에 광고 단위를 넣지 않았으면 SDK와 동의 흐름을 아예 건드리지 않음.
  static void start() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_bannerUnitId.isEmpty) {
      debugPrint('BATON_AD_BANNER가 비어 광고를 끔');
      return;
    }
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => unawaited(
        ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) debugPrint('동의 폼 실패: ${error.errorCode} ${error.message}');
          unawaited(_refreshPrivacyOptions());
          unawaited(_initIfAllowed());
        }),
      ),
      (error) {
        // 갱신이 실패해도 UMP는 지난 실행의 동의로 canRequestAds를 판단함
        debugPrint('동의 정보 갱신 실패: ${error.errorCode} ${error.message}');
        unawaited(_refreshPrivacyOptions());
        unawaited(_initIfAllowed());
      },
    );
    // 지난 실행에서 이미 동의했으면 폼을 기다리지 않고 바로 올림
    unawaited(_initIfAllowed());
  }

  /// 광고 요청이 허용됐으면 SDK를 올리고 ready를 켬. 여러 경로에서 불려도 initialize는 한 번만 나감.
  static Future<void> _initIfAllowed() async {
    if (!await ConsentInformation.instance.canRequestAds()) return;
    await (_init ??= MobileAds.instance.initialize());
    ready.value = true;
  }

  /// 개인정보 옵션 진입점이 필요한지 다시 읽음.
  static Future<void> _refreshPrivacyOptions() async {
    privacyOptionsRequired.value =
        await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
  }

  /// 설정의 개인정보 옵션 항목에서 부름. 폼이 닫힌 뒤 허용이 철회됐으면 배너를 내림.
  static void showPrivacyOptions() {
    unawaited(
      ConsentForm.showPrivacyOptionsForm((error) async {
        if (error != null) debugPrint('개인정보 옵션 폼 실패: ${error.errorCode} ${error.message}');
        if (await ConsentInformation.instance.canRequestAds()) {
          await _initIfAllowed();
        } else {
          ready.value = false;
        }
      }),
    );
  }

  /// 악보 뷰어 initState에서 부름. 빌드 중에 조상(AdFrame)을 다시 그리게 하면 안 되므로 뒤로 미룸.
  static void suppress() => scheduleMicrotask(() => suppressors.value++);

  /// 악보 뷰어 dispose에서 부름. 트리가 잠긴 동안 알리면 안 되므로 뒤로 미룸.
  static void release() => scheduleMicrotask(() => suppressors.value--);

  /// 다음 요청까지 기다릴 시간. 마지막 요청이 60초 안이면 남은 만큼.
  static Duration _nextRequestDelay() {
    final last = _lastRequest;
    if (last == null) return Duration.zero;
    final left = _minRequestGap - (_uptime.elapsed - last);
    return left.isNegative ? Duration.zero : left;
  }
}

/// MaterialApp.builder에서 Navigator를 감싸 화면 아래에 배너 칸을 붙임.
/// 칸 높이만큼 본문의 하단 여백·키보드 인셋을 덜어 이중으로 밀리지 않게 함.
class AdFrame extends StatelessWidget {
  const AdFrame({super.key, required this.child});

  /// MaterialApp이 넘긴 Navigator. 감싸는 트리 모양이 바뀌면 경로 스택이 새로 만들어지므로 모양을 고정함.
  final Widget child;

  /// 칸 표시 여부만 바꾸고 Navigator 쪽 트리는 항상 같은 모양으로 둠.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Ads._layout,
    builder: (context, _) => Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final mq = MediaQuery.of(context);
              // 배너 칸이 가져간 하단 높이. 칸이 없으면 0
              final taken = mq.size.height - box.maxHeight;
              double less(double v) => math.max(0, v - taken);
              return MediaQuery(
                data: mq.copyWith(
                  padding: mq.padding.copyWith(bottom: less(mq.padding.bottom)),
                  viewPadding: mq.viewPadding.copyWith(bottom: less(mq.viewPadding.bottom)),
                  viewInsets: mq.viewInsets.copyWith(bottom: less(mq.viewInsets.bottom)),
                ),
                child: child,
              );
            },
          ),
        ),
        if (Ads.ready.value && Ads.suppressors.value == 0)
          Stack(
            children: [
              const BannerSlot(),
              // 대화상자·시트의 배경막은 Navigator 안에만 그려짐. 배너도 덮어야
              // 바깥을 눌러 닫으려던 탭이 광고로 가지 않음. 칸은 그대로 둬 시트가 튀지 않게 함
              if (Ads._modals.value > 0)
                const Positioned.fill(
                  child: AbsorbPointer(child: ColoredBox(color: Colors.black54)),
                ),
            ],
          ),
      ],
    ),
  );
}

/// 대화상자·시트·메뉴(PopupRoute)가 열리고 닫히는 것을 셈.
class _ModalObserver extends NavigatorObserver {
  /// 빌드 중에 조상(AdFrame)을 다시 그리게 하면 안 되므로 뒤로 미룸.
  void _count(Route<dynamic>? route, int delta) {
    if (route is PopupRoute) scheduleMicrotask(() => Ads._modals.value += delta);
  }

  /// 모달이 열림.
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _count(route, 1);

  /// 모달이 닫힘.
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _count(route, -1);

  /// 모달이 애니메이션 없이 빠짐.
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _count(route, -1);

  /// 모달이 다른 경로로 바뀜.
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _count(oldRoute, -1);
    _count(newRoute, 1);
  }
}

/// 하단 배너 칸. 광고가 오기 전에도 자리를 먼저 잡아 뒤늦게 본문이 밀리며 오터치가 나지 않게 함.
class BannerSlot extends StatefulWidget {
  const BannerSlot({super.key});

  @override
  State<BannerSlot> createState() => _BannerSlotState();
}

class _BannerSlotState extends State<BannerSlot> {
  /// 로드가 끝난 광고. null이면 칸만 비워 둠.
  BannerAd? _ad;

  /// 예약된 다음 요청.
  Timer? _pending;

  /// 칸이 생기면 직전 요청과 60초 간격을 두고 첫 광고를 요청함.
  @override
  void initState() {
    super.initState();
    _pending = Timer(Ads._nextRequestDelay(), _load);
  }

  /// 광고 한 장을 요청함. 실패하면 칸을 유지한 채 60초 뒤 다시 시도함.
  void _load() {
    if (!mounted) return;
    Ads._lastRequest = Ads._uptime.elapsed;
    unawaited(
      BannerAd(
        adUnitId: _bannerUnitId,
        request: const AdRequest(),
        size: _bannerSize,
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            // 요청 중에 뷰어가 열려 칸이 사라졌으면 붙일 곳이 없음
            if (!mounted) {
              ad.dispose();
              return;
            }
            setState(() => _ad = ad as BannerAd);
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('배너 로드 실패: ${error.code} ${error.message}');
            // 이미 보이는 광고의 자동 새로고침 실패면 SDK가 다음 주기에 다시 시도하므로 그대로 둠
            if (identical(ad, _ad)) return;
            ad.dispose();
            if (mounted) _pending = Timer(_minRequestGap, _load);
          },
        ),
      ).load(),
    );
  }

  /// 칸이 사라질 때 예약 요청을 끊고 광고를 해제함. 진행 중 요청은 도착 즉시 버려짐.
  @override
  void dispose() {
    _pending?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  /// 광고가 없어도 크기를 유지함. 홈 인디케이터 영역은 칸 바탕색으로 채움.
  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    // 바탕을 폭 전체로 깔아 광고 좌우 여백을 누른 탭도 흡수함
    return SizedBox(
      width: double.infinity,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(height: _gapHeight),
              SizedBox(
                width: _bannerSize.width.toDouble(),
                height: _bannerSize.height.toDouble(),
                child: ad == null ? null : AdWidget(ad: ad),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
