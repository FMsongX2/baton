// 악보 뷰어. 악보가 화면의 주인공이라 조작 UI는 기본으로 숨기고 탭할 때만 띄움.
// 확정된 획은 pdfrx의 페인트 콜백이, 그리는 중인 획은 별도 오버레이가 그려 뷰어를 다시 빌드하지 않음.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../ads/ads.dart';
import '../core/db/settings_repo.dart';
import '../core/providers.dart';
import '../core/storage/paths.dart';
import '../metronome/click_scheduler.dart';
import '../score/playback_engine.dart';
import '../score/score_settings_page.dart';
import '../score/timeline.dart';
import '../settings/pedal_keys.dart';
import 'reader_prefs.dart';
import 'annotation/page_coords.dart';
import 'annotation/stroke.dart';
import 'annotation/stroke_painter.dart';
import 'annotation/stroke_store.dart';
import '../theme.dart';
import 'draw_toolbar.dart';
import 'page_layout.dart';
import 'page_nav.dart';
import 'playback_bar.dart';
import 'stage_layers.dart';

/// 조작 UI를 띄워 두는 시간. 지나면 다시 악보만 남김.
const _autoHide = Duration(seconds: 4);

/// 쪽(두 장씩이면 한 줄)이 통째로 화면에 들어오는 배율. 폭 맞춤(cover)으로 열면 가로 화면에서
/// 쪽 아래 단이 잘린 채 자동으로 넘어감. 이 배율이 곧 최소 배율이라 회전·두 장 전환 때도 pdfrx가 따라 맞춤.
double? _fitWholeRow(
  PdfDocument document,
  PdfViewerController controller,
  double fit,
  double cover,
) => math.min(fit, cover);

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.pdfPath, required this.scoreId, this.title});

  final String pdfPath;
  final int scoreId;
  final String? title;

  /// Navigator.restorablePush에 넘길 인자. 절대 경로는 앱 갱신 때 바뀌므로 상대 경로로 남김.
  static Map<String, Object?> routeArguments({
    required int scoreId,
    required String fileRel,
    String? title,
  }) => {'scoreId': scoreId, 'fileRel': fileRel, 'title': title};

  /// 프로세스가 죽었다 살아나도 Navigator가 인자만으로 다시 만들 수 있는 리더 경로.
  /// 복원 때 콜백 핸들로 다시 찾으므로 entry-point 표시가 없으면 릴리스(AOT)에서 찾지 못함.
  @pragma('vm:entry-point')
  static Route<void> restorableRoute(BuildContext context, Object? arguments) {
    final args = (arguments! as Map).cast<String, Object?>();
    return MaterialPageRoute(
      builder: (_) => ReaderPage(
        scoreId: args['scoreId']! as int,
        pdfPath: AppPaths.abs(args['fileRel']! as String),
        title: args['title'] as String?,
      ),
    );
  }

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, RestorationMixin {
  final _controller = PdfViewerController();
  final _focus = FocusNode();

  late final _audio = ref.read(audioProvider);
  late final _clock = _audio.createClock();
  late final _scheduler = ClickScheduler(_audio.soloud, _clock);
  late final _engine = PlaybackEngine(_clock, _scheduler);
  late final Ticker _ticker;

  /// 페이지 인덱스별 뷰어 좌표 사각형. 페인트 콜백이 매 프레임 채움.
  final _pageRects = <int, Rect>{};

  /// 페이지별 확정된 획과 되돌리기 기록.
  late final StrokeStore _strokes;

  /// 그리는 중인 획. 점을 덧붙이기만 하고 통째로 복사하지 않음.
  /// 이동 이벤트마다 리스트를 복사하면 획이 길어질수록 프레임이 밀림.
  Stroke? _live;

  /// 오버레이만 다시 그리게 하는 신호. 획을 제자리에서 고치므로 값 비교로는 변화를 알 수 없음.
  final _liveRevision = ValueNotifier<int>(0);

  /// 지금 획을 그리고 있는 포인터. 손바닥이나 두 번째 손가락이 끼어들어 획이 튀지 않게 함.
  int? _drawPointer;

  /// 뷰어 캐시를 버리고 다시 열게 할 때 바꿈. 회전처럼 파일이 바뀐 뒤에 씀.
  int _viewerEpoch = 0;

  /// 지금 뷰어가 첫 배치를 마쳤는지. 그 전의 이동은 pdfrx가 첫 쪽으로 가며 덮어쓰므로
  /// 보내지 않고 _viewed에만 남겨 두었다가 첫 쪽을 정할 때 씀.
  bool _viewerReady = false;

  Timer? _hideTimer;
  bool _chromeVisible = true;
  bool _drawMode = false;
  bool _stylusOnly = false;
  bool _invert = false;

  /// 연주 잠금. 켜면 탭 넘김·드래그·확대와 위치를 옮기는 조작을 막음. 페달과 키는 그대로 받음.
  /// 보면대에 눕힌 태블릿에 팔이 스쳐 페이지가 넘어가는 것이 이 앱에서 가장 비싼 사고임.
  /// 사용자가 정한 값이라 저장함. 그리는 동안에는 멈추고 그리기를 끄면 다시 걸림.
  bool _locked = false;

  /// 지금 실제로 잠겨 있는지. 그리기와 잠금은 함께 걸리지 않음.
  bool get _touchLocked => _locked && !_drawMode;

  /// 재생 설정을 열 수 있는지. 다녀오면 타임라인을 다시 걸어 재생이 끊기고 멈춘 마디 위치를 잃으므로
  /// 처음으로·진행바처럼 재생 중과 잠금 중에는 막음.
  bool get _canOpenSettings => !_touchLocked && !_engine.isPlaying.value;

  /// 재생 중 선행 넘김 뒤 앞 쪽을 다시 보고 있는지. 연주가 넘어간 쪽에 들어서면 풀림.
  bool _peeking = false;

  /// 지금 스팬에 엔진의 넘김(tick)으로 들어왔는지. 건너뛰기·재생 시작으로 온 스팬은 선행 구간이 아님.
  bool _turned = false;

  /// 재생 설정을 한 번도 손대지 않았는지. 기본값 그대로면 쪽당 8초로 넘어가 버림.
  bool _timingUnset = false;

  /// null이면 화면 비율에 맡김. 태블릿 가로처럼 넓은 화면은 펼침면이 자연스러움.
  bool? _twoUp;
  bool _clickOn = true;
  ReaderTool _tool = ReaderTool.pen;
  int _color = 0xFF1A1A1A;
  double _width = 0.003;
  int _drawingPage = -1;

  /// 보고 있는(또는 뷰어가 준비되면 보여 줄) 물리 페이지. 멈춘 동안의 넘김이 여기서 다음 쪽을 셈함.
  final _viewed = ViewedPage();

  /// 표시 인덱스에서 물리 페이지 인덱스로 가는 지도. 타임라인은 표시 인덱스로만 말함.
  List<int> _pageOrder = const [];

  /// 페달 넘김 키. 설정에서 바꾼 값을 화면을 열 때 읽어 옴.
  PedalKeys _pedal = PedalKeys.defaults;

  /// 지우개 판정 반경. 페이지 폭 대비 비율.
  static const _eraseTolerance = 0.012;

  /// 방향별로 본 가장 큰 화면 여백. 가로/세로를 따로 둠.
  final _stagePaddings = <bool, EdgeInsets>{};

  /// 프로세스가 죽었다 살아날 때 되돌릴 재생 위치(스팬)와 보던 물리 쪽.
  final _savedSpan = RestorableInt(0);
  final _savedPage = RestorableIntN(null);

  /// 경로 안에서 이 화면의 복원 칸 이름. 리더는 한 번에 하나만 뜸.
  @override
  String? get restorationId => 'reader';

  /// 복원할 값을 등록함. 되살아난 경우 여기서 값이 채워지고 타임라인을 읽은 뒤 적용함.
  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_savedSpan, 'span');
    registerForRestoration(_savedPage, 'page');
  }

  /// 엔진·필기·설정을 준비하고 비동기로 타임라인과 저장된 값을 읽기 시작함.
  @override
  void initState() {
    super.initState();
    // 연주 화면에는 광고를 두지 않음. 넘김 탭 영역·재생줄과 붙어 오터치를 부르고 반전 무대에서 번쩍임
    Ads.suppress();
    WidgetsBinding.instance.addObserver(this);
    // 곡 사이에 멈춰도 화면이 꺼지면 손으로 깨워야 함. 리더에 있는 동안 계속 켜 둠
    WakelockPlus.enable();
    // 저장은 화면이 사라진 뒤에도 끝나야 하므로 repo를 여기서 잡아 둠. 뒤에서 ref를 읽으면
    // mounted 검사가 필요해지고, 그 검사가 저장 자체를 건너뛰어 방금 그은 획이 사라짐
    final repo = ref.read(scoreRepoProvider);
    _strokes = StrokeStore(
      load: (page) => repo.strokes(widget.scoreId, page),
      save: (page, strokes) => repo.saveStrokes(widget.scoreId, page, strokes),
      onLoaded: () {
        if (mounted) setState(() {});
      },
      onSaveError: _onSaveError,
    );
    _scheduler.accent = _audio.accent;
    _scheduler.tick = _audio.tick;
    _engine.onPageChanged = _onEnginePage;
    _ticker = createTicker(_onFrame);
    _engine.isPlaying.addListener(_onPlayingChanged);
    _engine.spanIndex.addListener(_rememberSpan);
    // 구매 상태의 지금 값을 바로 적용하고 이후 바뀔 때마다 따라감. 스케줄러는 음소거 꺼짐으로
    // 시작하므로 첫 값을 적용하지 않으면 미구매자와 클릭을 꺼 둔 사용자에게도 클릭이 울림
    ref.listenManual(purchasesProvider, (_, _) => setState(_applyMuted), fireImmediately: true);
    _loadTimeline(restore: true);
    _loadLatency();
    _loadPedalKeys();
    _loadPrefs();
    _scheduleHide();
  }

  /// 저장된 출력 지연 보정을 읽어 클릭 예약에 반영함.
  Future<void> _loadLatency() async {
    final ms = await ref.read(settingsRepoProvider).getDouble(kLatencyMsKey, 0);
    _scheduler.latency = Duration(microseconds: (ms * 1000).round());
  }

  /// 저장된 표시·필기·잠금 설정을 읽어 화면과 클릭 음소거에 반영함. 곡마다 다시 켜지 않아도 되게 함.
  Future<void> _loadPrefs() async {
    final p = await loadReaderPrefs(ref.read(settingsRepoProvider));
    if (!mounted) return;
    setState(() {
      _invert = p.invert;
      _twoUp = p.twoUp;
      _clickOn = p.clickOn;
      _stylusOnly = p.stylusOnly;
      _tool = p.tool;
      _color = p.color;
      _width = p.width;
      _locked = p.locked;
      _applyMuted();
    });
  }

  /// 바뀐 설정 하나를 저장함. 값마다 키가 하나씩이라 통째로 쓰지 않음.
  void _savePref(String key, Object value) {
    final settings = ref.read(settingsRepoProvider);
    if (value is bool) {
      settings.setBool(key, value);
    } else {
      settings.set(key, '$value');
    }
  }

  /// 저장된 페달 키 매핑을 읽음. 없으면 기본값 그대로 씀.
  Future<void> _loadPedalKeys() async {
    final keys = await loadPedalKeys(ref.read(settingsRepoProvider));
    if (mounted) _pedal = keys;
  }

  /// 재생 상태에 맞춰 프레임 콜백과 조작줄을 켜고 끔. 재생 설정 버튼의 막힘도 다시 그림.
  /// 재생이 시작되면 선행 넘김 표시를 지우고 화면을 엔진 스팬 쪽으로 맞춘 뒤 조작줄을 바로 걷음.
  void _onPlayingChanged() {
    // 조작줄 표시가 그대로면(그리는 중, 이미 떠 있음) _setChrome이 다시 그리지 않음
    setState(() {});
    if (_engine.isPlaying.value) {
      if (!_ticker.isActive) _ticker.start();
      // 재생 시작으로 선 스팬은 넘김으로 들어온 것이 아님. 시계가 잠깐 시작 앞에 있어도 이전은 점프함
      _turned = false;
      // 멈춘 동안 손으로 스크롤했거나 뷰어가 늦게 떴어도 첫 박부터 엔진이 연주하는 쪽을 보여 줌.
      // 엔진은 스팬이 바뀔 때만 쪽을 넘기므로 여기서 맞추지 않으면 다음 넘김까지 틀린 쪽이 남음
      _alignViewToEngine();
      // 카운트인과 첫 마디를 조작줄이 가리지 않게 바로 걷음. 가운데를 누르면 다시 뜸
      _hideTimer?.cancel();
      if (!_drawMode) _setChrome(false);
    } else {
      _peeking = false;
      if (_ticker.isActive) _ticker.stop();
      _showChrome();
    }
  }

  /// 매 프레임 엔진을 굴리고, 앞 쪽을 다시 보던 중이면 돌아갈 때가 됐는지 봄.
  /// 엔진이 앞으로 넘겼으면 선행 넘김으로 들어온 스팬으로 표시함. 되감아 뒤로 갔으면 지움.
  void _onFrame(Duration _) {
    final before = _engine.spanIndex.value;
    _engine.tick();
    final after = _engine.spanIndex.value;
    if (after != before) _turned = after > before;
    _endPeekIfDue();
  }

  /// 엔진이 넘긴 쪽을 보여 줌. 앞 쪽을 다시 보던 중이었어도 엔진이 넘기면 그쪽을 따름.
  void _onEnginePage(int displayIndex) {
    _peeking = false;
    _goToDisplayPage(displayIndex);
  }

  /// 앞 쪽을 다시 보던 중 연주가 넘어간 쪽에 들어서면 그 쪽으로 돌아감.
  void _endPeekIfDue() {
    final tl = _engine.timeline;
    if (!_peeking || tl == null) return;
    final si = _engine.spanIndex.value;
    if (_engine.position.inMicroseconds / 1e6 < tl.spans[si].start) return;
    _peeking = false;
    _goToDisplayPage(tl.spans[si].pageIndex);
  }

  /// 화면을 엔진의 지금 스팬 쪽으로 옮김. 시계 위치로 쪽을 되짚지 않음. 재생 시작 직후 시계는 출력 지연
  /// 보정만큼 목표 앞에 있을 수 있어 되짚으면 앞 쪽으로 가고, 앞으로만 가는 tick이 되돌려 주지 않음.
  /// 재개하며 앞 쪽으로 되감은 경우는 엔진이 그 쪽을 알려 옴.
  void _alignViewToEngine() {
    final tl = _engine.timeline;
    if (tl == null || tl.spans.isEmpty) return;
    _goToDisplayPage(tl.spans[_engine.spanIndex.value].pageIndex);
  }

  /// 재생 위치가 바뀌면 복원용으로 남김.
  void _rememberSpan() => _savedSpan.value = _engine.spanIndex.value;

  /// DB의 재생 설정과 표시 순서를 읽어 타임라인을 걸음.
  /// restore면 프로세스가 죽기 전 보던 재생 위치와 쪽으로 되돌림. 새로 연 경우 저장된 값이 없어 그대로 둠.
  Future<void> _loadTimeline({bool restore = false}) async {
    final pb = await ref.read(scoreRepoProvider).playback(widget.scoreId);
    if (!mounted || pb == null) return;
    // load가 처음으로 되돌리며 복원용 값을 덮어쓰므로 먼저 읽어 둠
    final span = restore ? _savedSpan.value : 0;
    final page = restore ? _savedPage.value : null;
    _pageOrder = pb.pageOrder;
    _timingUnset = pb.timingUnset;
    // 표시 순서가 바뀌면 페이지가 놓이는 자리도 바뀜
    _pageRects.clear();
    _engine.load(buildTimeline(pb.timing));
    if (span > 0 && span < _engine.timeline!.spans.length) _engine.jumpToSpan(span);
    final shown = page == null ? -1 : _pageOrder.indexOf(page);
    if (shown >= 0) _goToDisplayPage(shown);
    setState(() {});
  }

  /// 화면 크기가 바뀌면 페이지가 놓이는 자리도 바뀜. 낡은 사각형을 두면 화면 밖 페이지의
  /// 옛 자리에 필기가 저장될 수 있음. 페인트 콜백이 매 프레임 다시 채우므로 비우는 비용은 없음.
  @override
  void didChangeMetrics() {
    if (mounted) setState(_pageRects.clear);
  }

  /// 앱이 뒤로 가면 Ticker가 서는데 오디오 시각은 계속 흐름.
  /// 그대로 두면 복귀 순간 페이지가 몇 장 건너뜀.
  /// inactive는 알림 배너처럼 잠깐 스치는 상태라 여기서 멈추면 연주가 끊김. 실제로 가려질 때만 멈춤.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _engine.pause();
    }
  }

  /// 구독·Ticker·엔진·복원 값을 정리하고 시스템 바와 광고 칸을 되돌림.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _engine.isPlaying.removeListener(_onPlayingChanged);
    _engine.spanIndex.removeListener(_rememberSpan);
    // 재생 중에 뒤로 나가면 아무도 멈춰 주지 않음. 활성 Ticker를 dispose하면 assert에 걸림
    if (_ticker.isActive) _ticker.stop();
    _ticker.dispose();
    _engine.dispose();
    _liveRevision.dispose();
    _focus.dispose();
    _savedSpan.dispose();
    _savedPage.dispose();
    WakelockPlus.disable();
    // 다른 화면은 시스템 바가 보여야 하므로 되돌림
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Ads.release();
    super.dispose();
  }

  /// 조작 UI 표시 여부를 바꾸고 시스템 바도 함께 맞춤.
  /// 숨길 때 상태바·내비바까지 감춰 악보가 쓸 수 있는 면적을 넓힘.
  void _setChrome(bool visible) {
    if (_chromeVisible != visible) setState(() => _chromeVisible = visible);
    SystemChrome.setEnabledSystemUIMode(
      visible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  /// 조작 UI를 띄우고 자동 숨김 시계를 다시 감음.
  void _showChrome() {
    _setChrome(true);
    _scheduleHide();
  }

  /// 잠시 뒤 조작 UI를 감춤. 그리기 중이거나 멈춰 있으면 그대로 둠.
  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_drawMode || !_engine.isPlaying.value) return;
    _hideTimer = Timer(_autoHide, () {
      if (mounted) _setChrome(false);
    });
  }

  /// 화면 가운데를 눌렀을 때 조작 UI를 보였다 감춤.
  void _toggleChrome() {
    _hideTimer?.cancel();
    _setChrome(!_chromeVisible);
    if (_chromeVisible) _scheduleHide();
  }

  /// 짧은 알림을 띄움. 액션이 없어 저절로 사라지고, 앞 알림은 바로 걷어 쌓이지 않게 함.
  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
  }

  /// 필기 저장 실패를 알림. 획은 화면과 캐시에 남아 있음.
  void _onSaveError(int page, Object error) {
    debugPrint('필기 저장 실패 ($page): $error');
    if (mounted) _notify('필기를 저장하지 못함: $error');
  }

  /// 표시 순서상 위치를 실제 페이지로 옮겨 이동함. 타임라인이 부르는 쪽.
  /// 두 장씩 볼 때 펼침면의 오른쪽 장으로 옮기면 뷰어가 그 장을 가운데로 끌어와
  /// 펼침면이 가로로 밀리므로, 항상 왼쪽 장을 기준으로 감.
  void _goToDisplayPage(int displayIndex) {
    if (displayIndex < 0 || displayIndex >= _pageOrder.length) return;
    _goToPage(_pageOrder[slotOf(displayIndex, _isTwoUp)]);
  }

  /// 지정 물리 페이지로 이동함. 뷰어가 아직 첫 배치 전이면 목표만 기억해 첫 쪽으로 씀.
  void _goToPage(int index) {
    _viewed.go(index);
    _savedPage.value = index;
    if (_viewerReady) _controller.goToPage(pageNumber: index + 1);
  }

  /// 새 뷰어가 처음 띄울 쪽. 준비 전에 받은 이동을 여기서 적용함. 숨긴 쪽이면 첫 표시 쪽으로 감.
  /// 넘기지 않으면 pdfrx가 물리 1쪽으로 가고, 1쪽을 숨긴 악보는 문서 끝으로 붙어 마지막 쪽이 뜸.
  int? _initialPageNumber(PdfDocument document, PdfViewerController controller) {
    final page = _viewed.current;
    final visible = _pageOrder.isEmpty || _pageOrder.contains(page);
    return (visible ? page : _pageOrder.first) + 1;
  }

  /// 뷰어가 첫 배치를 마침. 이후 이동은 바로 보냄.
  void _onViewerReady(PdfDocument document, PdfViewerController controller) => _viewerReady = true;

  /// 뷰어가 알려 준 지금 쪽을 기억함. 손으로 스크롤한 경우도 여기로 옴.
  /// 보낸 이동이 가는 도중에 지나가는 쪽은 버림. 빠른 연속 넘김이 한 번 빠지지 않게 함.
  void _onViewerPage(int? pageNumber) {
    if (pageNumber == null || !_viewed.report(pageNumber - 1)) return;
    _savedPage.value = _viewed.current;
  }

  /// 손으로 뷰어를 끌거나 확대하기 시작함. 이후 뷰어가 알리는 쪽을 그대로 받음.
  void _onViewerTouched(ScaleStartDetails details) => _viewed.touched();

  /// pdfrx가 페이지마다 부르는 페인트 콜백. 사각형을 기록하고 확정된 획을 그림.
  /// pageRect는 확대·이동을 적용하기 전 문서 좌표라 캔버스에도 그대로 쓸 수 있음.
  void _paintPage(Canvas canvas, Rect pageRect, PdfPage page) {
    final index = page.pageNumber - 1;
    _pageRects[index] = pageRect;
    paintStrokes(canvas, pageRect, _strokes.of(index));
  }

  /// 포인터 위치를 페이지 사각형과 같은 문서 좌표로 옮김.
  /// 화면 좌표를 그대로 쓰면 확대·이동한 만큼 필기가 어긋난 자리에 저장됨.
  Offset? _toDocument(PointerEvent e) =>
      _controller.isReady ? _controller.globalToDocument(e.position) : null;

  /// 페달·키보드 입력. 잠금과 무관하게 받음.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final direction = _pedal.directionOf(e.logicalKey);
    if (direction == 0) return KeyEventResult.ignored;
    _step(direction);
    return KeyEventResult.handled;
  }

  /// 페이지를 옮김. 재생 중에는 스팬 단위로 움직여 타임라인과 어긋나지 않음.
  /// 멈춰 있을 때는 표시 순서를 따라 넘기고 재생 위치도 넘긴 방향에서 그 쪽을 연주하는 가장 가까운 회차의 처음으로 옮김.
  /// 그래야 재생을 누를 때 보고 있던 쪽에서 이어지고, 진행바·쪽 번호와 화면이 같은 곳을 가리킴.
  /// 표지·빈 쪽 같은 0마디 쪽은 화면만 그 쪽에 두고 재생 위치는 연주 순서상 다음 실제 쪽의 처음에 둠.
  void _step(int delta) {
    final twoUp = _isTwoUp;
    final tl = _engine.timeline;
    if (tl != null && tl.spans.isNotEmpty && _engine.isPlaying.value) {
      final r = playingStep(
        tl,
        spanIndex: _engine.spanIndex.value,
        now: _engine.position.inMicroseconds / 1e6,
        delta: delta,
        twoUp: twoUp,
        peeking: _peeking,
        turned: _turned,
      );
      _peeking = r.peeking;
      if (r.jump != null) {
        _engine.jumpToSpan(r.jump!);
        // 건너뛰어 온 스팬이라 시계가 잠깐 시작 앞에 있어도 선행 구간으로 치지 않음
        _turned = false;
      } else if (r.show != null) {
        _goToDisplayPage(tl.spans[r.show!].pageIndex);
      }
      return;
    }
    final r = pausedStep(
      tl,
      _pageOrder,
      viewedPage: _viewed.current,
      spanIndex: _engine.spanIndex.value,
      delta: delta,
      twoUp: twoUp,
    );
    if (r == null) return;
    if (r.restart) {
      // 첫 쪽의 처음은 곡의 처음. 카운트인부터 온전히 다시 세도록 처음으로 되돌림
      _engine.stop();
    } else if (r.seek != null) {
      _engine.jumpToSpan(r.seek!);
    }
    // 연주하지 않는 쪽·0마디 쪽은 엔진이 알린 쪽 위에 넘긴 쪽을 보여 줌. 재생을 누르면 엔진 위치의 쪽으로 돌아감
    if (r.show != null) _goToDisplayPage(r.show!);
  }

  /// 스타일러스 전용 모드에서 손가락 입력을 걸러냄.
  bool _accepts(PointerEvent e) =>
      !_stylusOnly ||
      e.kind == PointerDeviceKind.stylus ||
      e.kind == PointerDeviceKind.invertedStylus;

  /// 그리기 시작. 포인터가 놓인 페이지를 정하고 그 페이지에 획을 묶음.
  /// 이미 한 포인터가 그리는 중이면 무시함. 손바닥이 닿아 획이 튀는 것을 막음.
  void _onDown(PointerDownEvent e) {
    if (!_accepts(e) || _drawPointer != null) return;
    final at = _toDocument(e);
    if (at == null) return;
    final page = pageAt(_pageRects, at);
    if (page == null) return;
    _drawPointer = e.pointer;
    _drawingPage = page;
    if (_tool == ReaderTool.eraser) {
      _erase(at, page);
      return;
    }
    final pressure = strokePressure(e);
    _live = Stroke(
      tool: _tool == ReaderTool.highlighter ? StrokeTool.highlighter : StrokeTool.pen,
      color: _tool == ReaderTool.highlighter ? (_color & 0x00FFFFFF) | 0x66000000 : _color,
      width: _width,
      points: [toNormalized(at, _pageRects[page]!)],
      pressures: pressure == null ? null : [pressure],
    );
    _liveRevision.value++;
  }

  /// 획을 이어감. 뷰어를 다시 빌드하지 않도록 오버레이 값만 갈아끼움.
  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _drawPointer || _drawingPage < 0) return;
    final rect = _pageRects[_drawingPage];
    final at = _toDocument(e);
    if (rect == null || at == null) return;
    if (_tool == ReaderTool.eraser) {
      _erase(at, _drawingPage);
      return;
    }
    final cur = _live;
    if (cur == null) return;
    // 제자리에 덧붙임. 매번 리스트를 복사하면 점 수에 제곱으로 비용이 붙음
    cur.points.add(toNormalized(at, rect));
    cur.pressures?.add(strokePressure(e) ?? 0.5);
    // 외곽선 캐시를 직접 무효화함. 객체가 그대로라 크기 비교로는 바뀐 줄 모름
    cur.cachedPath = null;
    _liveRevision.value++;
  }

  /// 획을 확정해 페이지에 넣고 저장함.
  void _onUp(PointerUpEvent e) {
    if (e.pointer != _drawPointer) return;
    final s = _live;
    final page = _drawingPage;
    _cancelStroke();
    if (s == null || page < 0 || s.points.length < 2) return;
    setState(() => _strokes.add(page, s));
  }

  /// 그리던 획을 버림. 시스템이 포인터를 거둬 가거나 획이 끝났을 때 상태를 되돌림.
  void _cancelStroke() {
    _live = null;
    _drawingPage = -1;
    _drawPointer = null;
    _liveRevision.value++;
  }

  /// 닿은 획을 통째로 지움. 픽셀 단위가 아니라 획 단위라 되돌리기가 단순해짐.
  void _erase(Offset document, int page) {
    final rect = _pageRects[page];
    if (rect == null) return;
    final n = toNormalized(document, rect);
    if (_strokes.erase(page, (s) => s.hitTest(n, _eraseTolerance))) setState(() {});
  }

  /// 그리기를 켜고 끔. 잠금과 함께 걸리지 않으므로 잠가 둔 상태면 그리는 동안 잠금이 멈춤을 알림.
  void _toggleDraw() {
    setState(() {
      _drawMode = !_drawMode;
      if (_drawMode) {
        _hideTimer?.cancel();
        _chromeVisible = true;
      } else {
        // Listener가 트리에서 빠지면 그 포인터의 up/cancel이 오지 않음.
        // 정리하지 않으면 _drawPointer가 남아 다음 획이 시작되지 않음
        _cancelStroke();
        _scheduleHide();
      }
    });
    if (_locked) _notify(_drawMode ? '그리는 동안 터치 잠금을 멈춤. 그리기를 끄면 다시 잠김' : '터치 잠금을 다시 켬');
  }

  /// 터치 잠금을 켜고 끔. 그리는 중에 켜면 그리기를 끄고 잠근 뒤 알림. 곡을 바꿔도 유지되게 저장함.
  void _toggleLock() {
    final lock = !_touchLocked;
    final wasDrawing = _drawMode;
    setState(() {
      _locked = lock;
      if (lock && _drawMode) {
        _drawMode = false;
        _cancelStroke();
        _scheduleHide();
      }
    });
    _savePref(kReaderLockKey, _locked);
    if (lock && wasDrawing) _notify('그리기를 끄고 터치를 잠금');
  }

  /// 재생 설정 화면을 열고 돌아오면 타임라인을 다시 읽음.
  /// 설정에서 페이지를 돌렸으면 파일이 바뀌므로 뷰어와 필기 캐시도 버림.
  Future<void> _openSettings() async {
    _engine.pause();
    final at = _engine.spanIndex.value;
    final before = await _pdfStamp();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScoreSettingsPage(
          scoreId: widget.scoreId,
          pdfPath: widget.pdfPath,
          title: widget.title,
        ),
      ),
    );
    if (!mounted) return;
    final changed = await _pdfStamp() != before;
    if (!mounted) return;
    setState(() {
      _pageRects.clear();
      if (changed) {
        // 회전은 PDF를 다시 굽고 필기 좌표까지 돌리므로 뷰어·필기 캐시·되돌리기를 함께 버림.
        // 파일이 그대로면 버리지 않음. 버리면 되돌리기가 다시 읽은 다른 객체를 가리켜 헛돌고,
        // 다시 실행은 같은 획을 두 벌 넣음
        _viewerEpoch++;
        _viewerReady = false;
        _strokes.reset();
      }
    });
    await _loadTimeline();
    // 설정만 보고 나온 경우에도 1쪽으로 튀지 않게 보던 자리로 되돌림
    final spans = _engine.timeline?.spans ?? const [];
    if (spans.isNotEmpty && at > 0) _engine.jumpToSpan(math.min(at, spans.length - 1));
  }

  /// 클릭 음소거를 지금 상태에 맞춤. 빌드 밖에서만 부름.
  void _applyMuted() => _scheduler.muted = !(_clickOn && _clickUsable);

  /// PDF 파일의 지문. 회전으로 파일이 바뀌었는지 판단하는 데 씀. 읽지 못하면 null.
  Future<String?> _pdfStamp() async {
    try {
      final f = File(widget.pdfPath);
      final stat = await f.stat();
      return '${stat.modified.microsecondsSinceEpoch}:${stat.size}';
    } catch (_) {
      return null;
    }
  }

  /// 클릭 소리를 낼 수 있는지. 메트로놈이 유료 기능이라 자동 넘김과 달리 구매를 봄.
  /// 엔진을 못 올린 기기에서도 꺼짐.
  bool get _clickUsable => _audio.ready && ref.read(purchasesProvider).unlocked;

  /// 그리는 중인 페이지의 사각형을 화면 좌표로. 오버레이는 변환 밖에 있어 직접 옮겨야 함.
  Rect? _livePageRect() {
    final r = _pageRects[_drawingPage];
    if (r == null || !_controller.isReady) return null;
    return Rect.fromPoints(
      _controller.documentToLocal(r.topLeft),
      _controller.documentToLocal(r.bottomRight),
    );
  }

  /// 두 장씩 볼지. 사용자가 정하지 않았으면 화면이 가로로 넓을 때만 펼침면으로 둠.
  bool get _isTwoUp {
    final v = _twoUp;
    if (v != null) return v;
    final size = MediaQuery.sizeOf(context);
    return size.width / size.height > 1.3;
  }

  /// 악보가 쓸 영역의 여백. 시스템 바를 숨기면 MediaQuery 여백이 줄어드는데,
  /// 줄어든 값을 그대로 쓰면 악보가 노치 아래로 들어가고 뷰어 크기까지 바뀌어 악보가 흔들림.
  /// 그래서 그 방향에서 본 가장 큰 값을 유지함. 여백은 줄기만 하고 늘지 않으므로 이걸로 충분함.
  EdgeInsets _resolveStagePadding(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final current = MediaQuery.paddingOf(context);
    final known = _stagePaddings[landscape];
    final merged = known == null
        ? current
        : EdgeInsets.fromLTRB(
            math.max(known.left, current.left),
            math.max(known.top, current.top),
            math.max(known.right, current.right),
            math.max(known.bottom, current.bottom),
          );
    _stagePaddings[landscape] = merged;
    return merged;
  }

  /// 반전은 무대용. 조작줄과 카운트인까지 함께 어두워져야 곡 시작 순간 화면이 번쩍이지 않음.
  /// 자식들이 전부 Theme.of를 읽으므로 테마를 갈아 끼우면 한 번에 걸림. 트리 모양은 반전과 무관하게
  /// 고정함. 모양이 바뀌면 아래 뷰어가 새로 만들어져 문서를 다시 열고 1쪽으로 튐.
  @override
  Widget build(BuildContext context) => Theme(
    data: _invert ? _stageTheme : Theme.of(context),
    child: Builder(builder: _buildScaffold),
  );

  /// 어두운 무대용 테마. 매 빌드마다 만들지 않도록 한 번만 잡음.
  late final _stageTheme = batonTheme(Brightness.dark);

  /// 테마가 걸린 자리에서 화면 전체를 그림.
  Widget _buildScaffold(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          // Positioned 자식은 크기 결정에 참여하지 않음. 카운트인이 없을 때 유일한
          // non-positioned 자식이 0 크기가 되어 Stack 전체가 접히므로 부모를 채우게 둠
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: _stage(context)),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(bottom: false, child: PlaybackStrip(engine: _engine)),
            ),
            _topChrome(),
            _bottomChrome(),
            CountInOverlay(remaining: _engine.countIn),
          ],
        ),
      ),
    );
  }

  /// 악보와 그 위에 얹히는 입력 레이어. 노치·홈 인디케이터를 피한 영역 안에 함께 둠.
  /// 필기 좌표는 뷰어의 변환을 거쳐 문서 좌표로 옮기므로 이 여백에 기대지 않음.
  Widget _stage(BuildContext context) => Padding(
    padding: _resolveStagePadding(context),
    child: Stack(
      fit: StackFit.expand,
      children: [
        _viewer(),
        if (_drawMode)
          DrawInputLayer(
            stylusOnly: _stylusOnly,
            onDown: _onDown,
            onMove: _onMove,
            onUp: _onUp,
            onCancel: (e) {
              if (e.pointer == _drawPointer) _cancelStroke();
            },
            child: RepaintBoundary(
              child: ValueListenableBuilder<int>(
                valueListenable: _liveRevision,
                // 확정된 획은 뷰어와 함께 반전됨. 그리는 중인 획도 같이 뒤집지 않으면
                // 검은 펜이 검은 페이지 위에 그려져 손을 뗄 때까지 안 보임
                builder: (_, revision, _) => InvertColors(
                  enabled: _invert,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _LiveStrokePainter(_live, _livePageRect(), revision),
                  ),
                ),
              ),
            ),
          )
        else
          // 잠그면 좌우 넘김 칸을 없앰. 가운데는 남겨 조작줄을 다시 부를 길을 보장함
          TapZones(onCenter: _toggleChrome, onStep: _step, turns: !_touchLocked),
      ],
    ),
  );

  /// 뷰어. 반전 모드에서는 색을 뒤집어 어두운 무대에서 눈부심을 줄임.
  Widget _viewer() => InvertColors(
    enabled: _invert,
    child: PdfViewer(
      // 회전은 같은 경로의 파일을 갈아 끼우므로 문서 캐시 키에 세대를 넣어 다시 읽게 함
      PdfDocumentRefFile(widget.pdfPath, key: PdfDocumentRefKey(widget.pdfPath, [_viewerEpoch])),
      key: ValueKey('${widget.pdfPath}#$_viewerEpoch'),
      controller: _controller,
      params: PdfViewerParams(
        // pdfrx가 자체 Focus를 잡고 화살표·PageDown·Space를 먼저 먹으면
        // 뷰어를 한 번 만진 뒤부터 페달이 죽으므로 키 처리는 이 화면이 독점함
        keyHandlerParams: const PdfViewerKeyHandlerParams(enabled: false),
        // 스타일러스 전용 모드에서는 손가락을 뷰어에 넘겨 스크롤·확대를 살림.
        // 잠그면 팔이 스쳐도 악보가 밀리지 않게 이동·확대를 모두 막음
        panEnabled: !_touchLocked && (!_drawMode || _stylusOnly),
        scaleEnabled: !_touchLocked && (!_drawMode || _stylusOnly),
        margin: 20,
        backgroundColor: _invert
            ? Colors.white
            : Theme.of(context).colorScheme.surfaceContainerLowest,
        // 넘김은 늘 쪽의 위를 맞춤. pdfrx는 물리적 마지막 쪽에만 아래 맞춤을 써서 화면보다 긴 쪽이면
        // 그 쪽의 첫 단이 위로 잘렸음
        pageAnchorEnd: PdfPageAnchor.top,
        sizeDelegateProvider: const PdfViewerSizeDelegateProviderLegacy(
          calculateInitialZoom: _fitWholeRow,
        ),
        layoutPages: makePageLayout(order: _pageOrder, twoUp: _isTwoUp),
        pagePaintCallbacks: [_paintPage],
        calculateInitialPageNumber: _initialPageNumber,
        onViewerReady: _onViewerReady,
        onPageChanged: _onViewerPage,
        onInteractionStart: _onViewerTouched,
      ),
    ),
  );

  /// 상단 조작줄. 숨김 상태에서는 제 높이만큼 위로 밀어 없앰.
  /// 고정 픽셀로 밀면 그리기 도구줄이 펼쳐졌을 때 다 숨지 않으므로 비율로 밀어냄.
  /// 잠그면 배치·위치를 바꾸는 버튼(두 장씩, 재생 설정)을 막음. 재생 중에도 재생 설정은 막음.
  Widget _topChrome() => Positioned(
    left: 0,
    right: 0,
    top: 0,
    child: AnimatedSlide(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      offset: Offset(0, _chromeVisible ? 0 : -1),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: _chromeVisible ? 1 : 0,
        child: _ChromeSurface(
          top: true,
          child: Column(
            // Positioned가 top만 정해 높이가 열려 있으므로 내용 높이만 차지해야 함
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: Text(
                      widget.title ?? '악보',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: _isTwoUp ? '한 장씩' : '두 장씩',
                    isSelected: _isTwoUp,
                    icon: Icon(_isTwoUp ? Icons.import_contacts : Icons.menu_book_outlined),
                    onPressed: _touchLocked
                        ? null
                        : () => setState(() {
                            _twoUp = !_isTwoUp;
                            // 명시값을 저장하므로 이후 화면을 돌려도 저절로 바뀌지 않음
                            _savePref(kReaderTwoUpKey, _twoUp!);
                            // 열 수가 바뀌면 페이지 좌표가 전부 달라짐. 낡은 사각형을 두면
                            // 화면 밖 페이지의 옛 자리에 필기가 저장될 수 있음
                            _pageRects.clear();
                          }),
                  ),
                  IconButton(
                    tooltip: '어두운 무대용 반전',
                    isSelected: _invert,
                    icon: Icon(_invert ? Icons.invert_colors : Icons.invert_colors_off),
                    onPressed: () => setState(() {
                      _invert = !_invert;
                      _savePref(kReaderInvertKey, _invert);
                    }),
                  ),
                  IconButton(
                    tooltip: _drawMode ? '그리기 끄기' : '그리기',
                    isSelected: _drawMode,
                    icon: Icon(_drawMode ? Icons.edit : Icons.edit_outlined),
                    onPressed: _toggleDraw,
                  ),
                  IconButton(
                    tooltip: _touchLocked ? '터치 잠금 해제' : '터치 잠금',
                    isSelected: _touchLocked,
                    icon: Icon(_touchLocked ? Icons.lock : Icons.lock_open_outlined),
                    onPressed: _toggleLock,
                  ),
                  IconButton(
                    tooltip: '재생 설정',
                    icon: const Icon(Icons.tune),
                    onPressed: _canOpenSettings ? _openSettings : null,
                  ),
                ],
              ),
              if (_timingUnset) _timingHint(),
              if (_drawMode)
                DrawToolbar(
                  tool: _tool,
                  color: _color,
                  width: _width,
                  stylusOnly: _stylusOnly,
                  canUndo: _strokes.canUndo,
                  canRedo: _strokes.canRedo,
                  onTool: (t) => setState(() {
                    _tool = t;
                    _savePref(kReaderToolKey, t.index);
                  }),
                  onColor: (c) => setState(() {
                    _color = c;
                    _savePref(kReaderColorKey, c);
                  }),
                  onWidth: (w) => setState(() {
                    _width = w;
                    _savePref(kReaderWidthKey, w);
                  }),
                  onStylusOnly: () => setState(() {
                    _stylusOnly = !_stylusOnly;
                    _savePref(kReaderStylusOnlyKey, _stylusOnly);
                  }),
                  onUndo: () => setState(_strokes.undo),
                  onRedo: () => setState(_strokes.redo),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  /// 마디수를 아직 설정하지 않았음을 알림. 기본값 그대로면 쪽당 8초로 넘어가는데
  /// 사용자는 그것이 설정된 값인지 손대지 않은 값인지 화면에서 구분할 수 없음.
  /// 누르면 재생 설정으로 가므로 재생 설정 버튼과 같이 막음.
  Widget _timingHint() {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _canOpenSettings ? _openSettings : null,
      child: Container(
        width: double.infinity,
        color: scheme.secondaryContainer,
        padding: const EdgeInsets.fromLTRB(kGapL, kGapS, kGapL, kGapS),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: scheme.onSecondaryContainer),
            const SizedBox(width: kGapS),
            Expanded(
              child: Text(
                '페이지별 마디수를 설정해야 제때 넘어감. 지금은 기본값으로 넘어감',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSecondaryContainer),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: scheme.onSecondaryContainer),
          ],
        ),
      ),
    );
  }

  /// 하단 재생줄. 숨김 상태에서는 제 높이만큼 아래로 밀어 없앰.
  Widget _bottomChrome() => Positioned(
    left: 0,
    right: 0,
    bottom: 0,
    child: AnimatedSlide(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      offset: Offset(0, _chromeVisible ? 0 : 1),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: _chromeVisible ? 1 : 0,
        child: _ChromeSurface(
          bottom: true,
          child: PlaybackBar(
            engine: _engine,
            onJumpToSpan: _engine.jumpToSpan,
            onInteract: _showChrome,
            locked: _touchLocked,
            clickAvailable: _clickUsable,
            clickOn: _clickOn && _clickUsable,
            onToggleClick: !_clickUsable
                ? null
                : () => setState(() {
                    _clickOn = !_clickOn;
                    _savePref(kReaderClickKey, _clickOn);
                    _applyMuted();
                  }),
          ),
        ),
      ),
    ),
  );
}

/// 악보 위에 얹는 조작줄 바탕. 살짝 비쳐 악보 위치를 가늠할 수 있게 함.
class _ChromeSurface extends StatelessWidget {
  const _ChromeSurface({required this.child, this.top = false, this.bottom = false});

  final Widget child;

  /// 상태바·제스처바에 가리지 않도록 보호할 방향.
  final bool top;
  final bool bottom;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 악보 위에 뜨는 조작줄이라 반투명이면 흰 악보가 비쳐 버튼이 읽히지 않음.
    // 불투명으로 두고 그림자로만 떠 있음을 표현함
    return Material(
      color: scheme.surface,
      elevation: 8,
      child: SafeArea(top: top, bottom: bottom, child: child),
    );
  }
}

/// 그리는 중인 획만 그림. 확정된 획은 pdfrx의 페인트 콜백이 맡음.
class _LiveStrokePainter extends CustomPainter {
  _LiveStrokePainter(this.stroke, this.pageRect, this.revision);

  final Stroke? stroke;
  final Rect? pageRect;

  /// 획을 제자리에서 고치므로 객체 비교로는 변화를 알 수 없음. 이 값으로 판단함.
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    final s = stroke;
    final r = pageRect;
    if (s == null || r == null) return;
    paintStrokes(canvas, r, [s]);
  }

  @override
  bool shouldRepaint(_LiveStrokePainter old) =>
      old.revision != revision || old.pageRect != pageRect;
}
