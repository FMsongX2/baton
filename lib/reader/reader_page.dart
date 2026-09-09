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

import '../core/db/settings_repo.dart';
import '../core/providers.dart';
import '../metronome/click_scheduler.dart';
import '../score/playback_engine.dart';
import '../score/score_settings_page.dart';
import '../score/timeline.dart';
import '../settings/pedal_keys.dart';
import 'reader_prefs.dart';
import 'annotation/page_coords.dart';
import 'annotation/stroke.dart';
import 'annotation/stroke_painter.dart';
import '../theme.dart';
import 'draw_toolbar.dart';
import 'page_layout.dart';
import 'playback_bar.dart';

/// 어두운 무대용 색 반전. 뷰어와 그리는 중인 획이 같은 필터를 써야 서로 어긋나지 않음.
const _invertFilter = ColorFilter.matrix(<double>[
  -1, 0, 0, 0, 255, //
  0, -1, 0, 0, 255, //
  0, 0, -1, 0, 255, //
  0, 0, 0, 1, 0, //
]);

/// 조작 UI를 띄워 두는 시간. 지나면 다시 악보만 남김.
const _autoHide = Duration(seconds: 4);

/// 필기 한 번의 변경. 실행취소는 이 기록을 뒤집어 되돌림.
class _Op {
  _Op(this.page, this.stroke, this.added);

  final int page;
  final Stroke stroke;
  final bool added;
}

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.pdfPath, required this.scoreId, this.title});

  final String pdfPath;
  final int scoreId;
  final String? title;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _controller = PdfViewerController();
  final _focus = FocusNode();

  late final _audio = ref.read(audioProvider);
  late final _clock = _audio.createClock();
  late final _scheduler = ClickScheduler(_audio.soloud, _clock);
  late final _engine = PlaybackEngine(_clock, _scheduler);
  late final Ticker _ticker;

  /// 페이지 인덱스별 뷰어 좌표 사각형. 페인트 콜백이 매 프레임 채움.
  final _pageRects = <int, Rect>{};

  /// 페이지 인덱스별 확정된 획. 열어본 페이지만 채움.
  final _strokes = <int, List<Stroke>>{};

  /// 아직 읽는 중인 페이지의 작업. 읽기가 끝나기 전에 저장하면 DB의 기존 획을 지움.
  final _loading = <int, Future<void>>{};

  /// 필기 캐시의 세대. 캐시를 비울 때 올림.
  /// 진행 중이던 읽기가 비워진 캐시에 결과를 얹고, 그 사이 시작된 두 번째 읽기가 또 얹으면
  /// 같은 획이 두 벌 쌓이고 저장 대기까지 무너짐. 자기 세대가 아니면 아무것도 하지 않게 함.
  int _strokeEpoch = 0;

  /// 그리는 중인 획. 점을 덧붙이기만 하고 통째로 복사하지 않음.
  /// 이동 이벤트마다 리스트를 복사하면 획이 길어질수록 프레임이 밀림.
  Stroke? _live;

  /// 오버레이만 다시 그리게 하는 신호. 획을 제자리에서 고치므로 값 비교로는 변화를 알 수 없음.
  final _liveRevision = ValueNotifier<int>(0);

  /// 지금 획을 그리고 있는 포인터. 손바닥이나 두 번째 손가락이 끼어들어 획이 튀지 않게 함.
  int? _drawPointer;

  final _undo = <_Op>[];
  final _redo = <_Op>[];

  /// 뷰어 캐시를 버리고 다시 열게 할 때 바꿈. 회전처럼 파일이 바뀐 뒤에 씀.
  int _viewerEpoch = 0;

  Timer? _hideTimer;
  bool _chromeVisible = true;
  bool _drawMode = false;
  bool _stylusOnly = false;
  bool _invert = false;

  /// 연주 잠금. 켜면 화면 탭으로 페이지가 넘어가지 않음. 페달과 키는 그대로 받음.
  /// 보면대에 눕힌 태블릿에 팔이 스쳐 페이지가 넘어가는 것이 이 앱에서 가장 비싼 사고임.
  bool _locked = false;

  /// 재생 설정을 한 번도 손대지 않았는지. 기본값 그대로면 쪽당 8초로 넘어가 버림.
  bool _timingUnset = false;

  /// null이면 화면 비율에 맡김. 태블릿 가로처럼 넓은 화면은 펼침면이 자연스러움.
  bool? _twoUp;
  bool _clickOn = true;
  ReaderTool _tool = ReaderTool.pen;
  int _color = 0xFF1A1A1A;
  double _width = 0.003;
  int _drawingPage = -1;
  int _currentPage = 0;

  /// 표시 인덱스에서 물리 페이지 인덱스로 가는 지도. 타임라인은 표시 인덱스로만 말함.
  List<int> _pageOrder = const [];

  /// 페달 넘김 키. 설정에서 바꾼 값을 화면을 열 때 읽어 옴.
  PedalKeys _pedal = PedalKeys.defaults;

  /// 지우개 판정 반경. 페이지 폭 대비 비율.
  static const _eraseTolerance = 0.012;

  /// 방향별로 본 가장 큰 화면 여백. 가로/세로를 따로 둠.
  final _stagePaddings = <bool, EdgeInsets>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 곡 사이에 멈춰도 화면이 꺼지면 손으로 깨워야 함. 리더에 있는 동안 계속 켜 둠
    WakelockPlus.enable();
    _scheduler.accent = _audio.accent;
    _scheduler.tick = _audio.tick;
    _engine.onPageChanged = _goToDisplayPage;
    _ticker = createTicker((_) => _engine.tick());
    _engine.isPlaying.addListener(_onPlayingChanged);
    _loadTimeline();
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

  /// 저장된 표시·필기 설정을 읽어 화면에 반영함. 곡마다 다시 켜지 않아도 되게 함.
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

  /// 재생 상태에 맞춰 프레임 콜백과 화면 켜둠을 켜고 끔.
  void _onPlayingChanged() {
    if (_engine.isPlaying.value) {
      if (!_ticker.isActive) _ticker.start();
      _scheduleHide();
    } else {
      if (_ticker.isActive) _ticker.stop();
      _showChrome();
    }
  }

  /// DB의 재생 설정과 표시 순서를 읽어 타임라인을 걸음.
  Future<void> _loadTimeline() async {
    final pb = await ref.read(scoreRepoProvider).playback(widget.scoreId);
    if (!mounted || pb == null) return;
    _pageOrder = pb.pageOrder;
    _timingUnset = pb.timingUnset;
    // 표시 순서가 바뀌면 페이지가 놓이는 자리도 바뀜
    _pageRects.clear();
    _engine.load(buildTimeline(pb.timing));
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _engine.isPlaying.removeListener(_onPlayingChanged);
    // 재생 중에 뒤로 나가면 아무도 멈춰 주지 않음. 활성 Ticker를 dispose하면 assert에 걸림
    if (_ticker.isActive) _ticker.stop();
    _ticker.dispose();
    _engine.dispose();
    _liveRevision.dispose();
    _focus.dispose();
    WakelockPlus.disable();
    // 다른 화면은 시스템 바가 보여야 하므로 되돌림
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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

  /// 페이지의 필기를 아직 안 읽었으면 읽어 옴. 읽는 동안에는 빈 목록으로 그림.
  /// 읽기가 끝나면 그 사이에 그린 획 뒤에 붙임. 통째로 갈아 끼우면 그 획이 사라짐.
  List<Stroke> _strokesOf(int page) {
    final cached = _strokes[page];
    if (cached != null) return cached;
    final list = <Stroke>[];
    final epoch = _strokeEpoch;
    _strokes[page] = list;
    _loading[page] = ref
        .read(scoreRepoProvider)
        .strokes(widget.scoreId, page)
        .then((loaded) {
          if (!mounted || epoch != _strokeEpoch || loaded.isEmpty) return;
          _strokes[page] = [...loaded, ...?_strokes[page]];
          setState(() {});
        })
        .whenComplete(() {
          if (epoch == _strokeEpoch) _loading.remove(page);
        });
    return list;
  }

  /// 필기 캐시를 버리고 진행 중이던 읽기를 무효로 만듦.
  void _resetStrokes() {
    _strokeEpoch++;
    _strokes.clear();
    _loading.clear();
  }

  /// 한 페이지의 필기를 저장함. 획이 끝날 때마다 불러 중간에 앱이 죽어도 잃지 않게 함.
  /// 아직 읽는 중이면 기다림. 먼저 쓰면 DB에 있던 획을 방금 그린 하나로 덮어씀.
  Future<void> _persist(int page) async {
    // repo를 await 앞에서 잡아 둠. 뒤에서 잡으면 화면이 사라진 뒤 ref를 읽을 수 없어
    // mounted 검사가 필요해지고, 그 검사가 저장 자체를 건너뛰어 방금 그은 획이 사라짐
    final repo = ref.read(scoreRepoProvider);
    final strokes = _strokes[page] ?? const <Stroke>[];
    try {
      await _loading[page];
      await repo.saveStrokes(widget.scoreId, page, strokes);
    } catch (e) {
      debugPrint('필기 저장 실패 ($page): $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('필기를 저장하지 못함: $e')));
      }
    }
  }

  /// 표시 순서상 위치를 실제 페이지로 옮겨 이동함. 타임라인이 부르는 쪽.
  /// 두 장씩 볼 때 펼침면의 오른쪽 장으로 옮기면 뷰어가 그 장을 가운데로 끌어와
  /// 펼침면이 가로로 밀리므로, 항상 왼쪽 장을 기준으로 감.
  void _goToDisplayPage(int displayIndex) {
    if (displayIndex < 0 || displayIndex >= _pageOrder.length) return;
    final slot = _isTwoUp ? displayIndex - (displayIndex % 2) : displayIndex;
    _goToPage(_pageOrder[slot]);
  }

  /// 지정 물리 페이지로 이동함. 페달 입력과 화면 이동이 공용으로 씀.
  void _goToPage(int index) {
    _currentPage = index;
    if (_controller.isReady) _controller.goToPage(pageNumber: index + 1);
  }

  /// pdfrx가 페이지마다 부르는 페인트 콜백. 사각형을 기록하고 확정된 획을 그림.
  /// pageRect는 확대·이동을 적용하기 전 문서 좌표라 캔버스에도 그대로 쓸 수 있음.
  void _paintPage(Canvas canvas, Rect pageRect, PdfPage page) {
    final index = page.pageNumber - 1;
    _pageRects[index] = pageRect;
    paintStrokes(canvas, pageRect, _strokesOf(index));
  }

  /// 포인터 위치를 페이지 사각형과 같은 문서 좌표로 옮김.
  /// 화면 좌표를 그대로 쓰면 확대·이동한 만큼 필기가 어긋난 자리에 저장됨.
  Offset? _toDocument(PointerEvent e) =>
      _controller.isReady ? _controller.globalToDocument(e.position) : null;

  /// 페달·키보드 입력. 재생 중이면 재생 순서를 따라 옮겨 카운트가 어긋나지 않게 함.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final direction = _pedal.directionOf(e.logicalKey);
    if (direction == 0) return KeyEventResult.ignored;
    _step(direction);
    return KeyEventResult.handled;
  }

  /// 페이지를 옮김. 재생 중에는 스팬 단위로 움직여 타임라인과 어긋나지 않음.
  /// 멈춰 있을 때는 물리 인덱스가 아니라 표시 순서를 따라가 숨긴 페이지로 빠지지 않음.
  /// 두 장씩 보는 중에는 펼침면 단위로 옮김.
  void _step(int delta) {
    final twoUp = _isTwoUp;
    final step = delta * (twoUp ? 2 : 1);
    final tl = _engine.timeline;
    if (tl != null && tl.spans.isNotEmpty && _engine.isPlaying.value) {
      _engine.jumpToSpan(_nextSpan(tl, _engine.spanIndex.value, delta, twoUp));
      return;
    }
    if (_pageOrder.isEmpty) return;
    final found = _pageOrder.indexOf(_currentPage);
    // 목록에 없는 페이지를 보고 있으면 방향에 맞는 끝에서 다시 시작함
    var slot = found < 0 ? (step > 0 ? -1 : _pageOrder.length) : found;
    if (twoUp && found >= 0) slot -= slot % 2;
    final next = slot + step;
    if (next < 0 || next >= _pageOrder.length) return;
    _goToDisplayPage(next);
  }

  /// 한 번 눌렀을 때 갈 스팬. 두 장씩 볼 때는 지금과 다른 펼침면이 나올 때까지 건너뜀.
  /// 반복이 있으면 스팬 인덱스와 표시 순서의 홀짝이 어긋나므로 표시 순서로 짝을 맞춤.
  int _nextSpan(Timeline tl, int current, int delta, bool twoUp) {
    if (!twoUp) return current + delta;
    int spreadOf(int i) => tl.spans[i].pageIndex - (tl.spans[i].pageIndex % 2);
    final from = spreadOf(current);
    var i = current + delta;
    while (i >= 0 && i < tl.spans.length && spreadOf(i) == from) {
      i += delta;
    }
    return i;
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
    _live = Stroke(
      tool: _tool == ReaderTool.highlighter ? StrokeTool.highlighter : StrokeTool.pen,
      color: _tool == ReaderTool.highlighter ? (_color & 0x00FFFFFF) | 0x66000000 : _color,
      width: _width,
      points: [toNormalized(at, _pageRects[page]!)],
      pressures: [e.pressure],
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
    cur.pressures?.add(e.pressure);
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
    setState(() {
      _strokesOf(page).add(s);
      _undo.add(_Op(page, s, true));
      _redo.clear();
    });
    _persist(page);
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
    final list = _strokesOf(page);
    final hit = list.where((s) => s.hitTest(n, _eraseTolerance)).toList();
    if (hit.isEmpty) return;
    setState(() {
      for (final s in hit) {
        list.remove(s);
        _undo.add(_Op(page, s, false));
      }
      _redo.clear();
    });
    _persist(page);
  }

  /// 마지막 변경을 되돌림.
  void _undoOnce() {
    if (_undo.isEmpty) return;
    final op = _undo.removeLast();
    setState(() {
      final list = _strokesOf(op.page);
      op.added ? list.remove(op.stroke) : list.add(op.stroke);
      _redo.add(op);
    });
    _persist(op.page);
  }

  /// 되돌린 변경을 다시 적용함.
  void _redoOnce() {
    if (_redo.isEmpty) return;
    final op = _redo.removeLast();
    setState(() {
      final list = _strokesOf(op.page);
      op.added ? list.add(op.stroke) : list.remove(op.stroke);
      _undo.add(op);
    });
    _persist(op.page);
  }

  /// 재생 설정 화면을 열고 돌아오면 타임라인과 뷰어를 다시 읽음.
  /// 설정에서 페이지를 돌렸을 수 있어 뷰어 캐시도 버림.
  Future<void> _openSettings() async {
    _engine.pause();
    final at = _engine.spanIndex.value;
    // 회전은 PDF를 다시 굽고 필기 좌표까지 돌리므로 캐시와 되돌리기가 반드시 무효화돼야 함
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
      _resetStrokes();
      _pageRects.clear();
      if (changed) {
        // 파일이 바뀐 경우에만. 설정을 보기만 하고 나와도 되돌리기가 사라지면 이유가 없음
        _viewerEpoch++;
        _undo.clear();
        _redo.clear();
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

  @override
  Widget build(BuildContext context) {
    // 반전은 무대용임. 조작줄과 카운트인까지 함께 어두워져야 곡 시작 순간 화면이 번쩍이지 않음.
    // 자식들이 전부 Theme.of를 읽으므로 테마를 갈아 끼우면 한 번에 걸림
    if (_invert) {
      return Theme(
        data: _stageTheme,
        child: Builder(builder: _buildScaffold),
      );
    }
    return _buildScaffold(context);
  }

  /// 어두운 무대용 테마. 매 빌드마다 만들지 않도록 한 번만 잡음.
  late final _stageTheme = batonTheme(Brightness.dark);

  Widget _buildScaffold(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 구매 상태가 늦게 도착해도 소리 여부와 버튼 표시가 따라오게 함. 빌드 중에 대입하면
    // muted 세터가 오디오 예약을 취소해 프레임 도중에 부수효과가 남
    ref.listen(purchasesProvider, (_, _) {
      if (!mounted) return;
      setState(_applyMuted);
    });
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
          Listener(
            // 펜만 받을 때는 손가락 이벤트를 아래 뷰어로 흘려보냄
            behavior: _stylusOnly ? HitTestBehavior.translucent : HitTestBehavior.opaque,
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerCancel: (e) {
              if (e.pointer == _drawPointer) _cancelStroke();
            },
            child: RepaintBoundary(
              child: ValueListenableBuilder<int>(
                valueListenable: _liveRevision,
                builder: (_, revision, _) {
                  final overlay = CustomPaint(
                    size: Size.infinite,
                    painter: _LiveStrokePainter(_live, _livePageRect(), revision),
                  );
                  // 확정된 획은 뷰어와 함께 반전됨. 그리는 중인 획도 같이 뒤집지 않으면
                  // 검은 펜이 검은 페이지 위에 그려져 손을 뗄 때까지 안 보임
                  return _invert
                      ? ColorFiltered(colorFilter: _invertFilter, child: overlay)
                      : overlay;
                },
              ),
            ),
          )
        else
          _tapZones(),
      ],
    ),
  );

  /// 뷰어. 반전 모드에서는 색을 뒤집어 감싸 어두운 무대에서 눈부심을 줄임.
  Widget _viewer() {
    final viewer = PdfViewer(
      // 회전은 같은 경로의 파일을 갈아 끼우므로 문서 캐시 키에 세대를 넣어 다시 읽게 함
      PdfDocumentRefFile(widget.pdfPath, key: PdfDocumentRefKey(widget.pdfPath, [_viewerEpoch])),
      key: ValueKey('${widget.pdfPath}#$_viewerEpoch'),
      controller: _controller,
      params: PdfViewerParams(
        // pdfrx가 자체 Focus를 잡고 화살표·PageDown·Space를 먼저 먹으면
        // 뷰어를 한 번 만진 뒤부터 페달이 죽으므로 키 처리는 이 화면이 독점함
        keyHandlerParams: const PdfViewerKeyHandlerParams(enabled: false),
        // 스타일러스 전용 모드에서는 손가락을 뷰어에 넘겨 스크롤·확대를 살림
        panEnabled: !_drawMode || _stylusOnly,
        scaleEnabled: !_drawMode || _stylusOnly,
        margin: 20,
        backgroundColor: _invert
            ? Colors.white
            : Theme.of(context).colorScheme.surfaceContainerLowest,
        layoutPages: makePageLayout(order: _pageOrder, twoUp: _isTwoUp),
        pagePaintCallbacks: [_paintPage],
        onPageChanged: (n) {
          if (n != null) _currentPage = n - 1;
        },
      ),
    );
    if (!_invert) return viewer;
    return ColorFiltered(colorFilter: _invertFilter, child: viewer);
  }

  /// 화면을 셋으로 나눠 좌우는 페이지 이동, 가운데는 조작 UI 토글에 씀.
  /// 드래그는 아래 뷰어로 흘려보내 확대·이동을 막지 않음.
  Widget _tapZones() => Row(
    children: [
      // 잠그면 좌우 존을 아예 만들지 않음. 가운데는 남겨 조작줄을 다시 부를 길을 보장함
      if (!_locked)
        Expanded(
          child: Semantics(
            button: true,
            label: '이전 페이지',
            child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => _step(-1)),
          ),
        ),
      Expanded(
        flex: 2,
        child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _toggleChrome),
      ),
      if (!_locked)
        Expanded(
          child: Semantics(
            button: true,
            label: '다음 페이지',
            child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => _step(1)),
          ),
        ),
    ],
  );

  /// 상단 조작줄. 숨김 상태에서는 제 높이만큼 위로 밀어 없앰.
  /// 고정 픽셀로 밀면 그리기 도구줄이 펼쳐졌을 때 다 숨지 않으므로 비율로 밀어냄.
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
                    onPressed: () => setState(() {
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
                    onPressed: () => setState(() {
                      _drawMode = !_drawMode;
                      if (_drawMode) {
                        _locked = false;
                        _hideTimer?.cancel();
                        _chromeVisible = true;
                      } else {
                        // Listener가 트리에서 빠지면 그 포인터의 up/cancel이 오지 않음.
                        // 정리하지 않으면 _drawPointer가 남아 다음 획이 시작되지 않음
                        _cancelStroke();
                        _scheduleHide();
                      }
                    }),
                  ),
                  IconButton(
                    tooltip: _locked ? '터치 잠금 해제' : '터치 잠금',
                    isSelected: _locked,
                    icon: Icon(_locked ? Icons.lock : Icons.lock_open_outlined),
                    onPressed: () => setState(() => _locked = !_locked),
                  ),
                  IconButton(
                    tooltip: '재생 설정',
                    icon: const Icon(Icons.tune),
                    onPressed: _openSettings,
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
                  canUndo: _undo.isNotEmpty,
                  canRedo: _redo.isNotEmpty,
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
                  onUndo: _undoOnce,
                  onRedo: _redoOnce,
                ),
            ],
          ),
        ),
      ),
    ),
  );

  /// 마디수를 아직 설정하지 않았음을 알림. 기본값 그대로면 쪽당 8초로 넘어가는데
  /// 사용자는 그것이 설정된 값인지 손대지 않은 값인지 화면에서 구분할 수 없음.
  Widget _timingHint() {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _openSettings,
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
