// 악보 재생 설정 화면. 페이지별 마디수가 자동 넘김의 정확도를 결정하므로 입력하면서
// 바로 옆에서 해당 페이지를 볼 수 있게 뷰어를 함께 둠. 썸네일을 따로 렌더하지 않음.

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../cloud/api_client.dart';
import '../core/db/database.dart';
import '../core/providers.dart';
import '../core/storage/paths.dart';
import '../theme.dart';
import 'score_repo.dart';
import 'thumbnail.dart';
import 'timeline.dart';

class ScoreSettingsPage extends ConsumerStatefulWidget {
  const ScoreSettingsPage({super.key, required this.scoreId, required this.pdfPath, this.title});

  final int scoreId;
  final String pdfPath;
  final String? title;

  @override
  ConsumerState<ScoreSettingsPage> createState() => _ScoreSettingsPageState();
}

class _ScoreSettingsPageState extends ConsumerState<ScoreSettingsPage> {
  final _viewer = PdfViewerController();

  /// 이 화면 전용 알림 창구. 화면과 함께 사라지므로 되돌리기 같은 동작이 폐기된 State에 묶이지 않음.
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  /// 쪽별 마디수 칸의 초점. 다음 쪽 칸으로 넘기려고 여기서 들고 있음. 키는 물리 페이지 인덱스.
  final _barFocus = <int, FocusNode>{};

  /// 마지막으로 시작한 다시 읽기. 앞선 읽기가 늦게 끝나 새 값을 옛 값으로 덮지 않게 함.
  int _reloadSeq = 0;

  /// 회전으로 파일이 바뀌면 올려서 뷰어 캐시를 버리게 함.
  int _viewerEpoch = 0;

  /// 파일이나 설정을 바꾸는 작업(회전·AI 분석) 중. 회전 중에는 화면을 떠날 수 없고,
  /// AI 분석 중 뒤로가기는 분석을 멈춘 뒤 화면을 닫음.
  bool _busy = false;

  /// AI 분석을 시작해 끝날 때까지 켜 둠. _busy는 확인 뒤에야 켜져 그 전에 또 누르면 분석이 둘 돎.
  bool _aiRunning = false;
  String _busyLabel = '';
  bool _hasUndo = false;

  /// 진행 중인 AI 분석을 멈추는 신호. 분석 중에만 있음.
  Completer<void>? _stopAnalysis;

  /// 분석이 멈춘 뒤 화면을 닫을지. 분석 중 뒤로가기가 켬.
  bool _leaveAfterStop = false;

  /// 설정을 읽지 못한 사유. null이 아니면 스피너 대신 이걸 보여 줌.
  String? _loadError;

  Score? _score;
  List<ScorePage> _pages = const [];
  int _selected = 0;

  /// 화면에 보여줄 물리 페이지 인덱스, 표시 순서대로.
  List<int> _order = const [];

  /// 표시 순서상 위치별 반복 횟수. playOrder를 사람이 다루기 쉬운 형태로 바꾼 것.
  List<int> _repeats = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// 마디수 칸 초점을 모두 버리고 진행 중인 AI 분석을 멈춤. 닫힌 화면의 분석이 뒤늦게 반영되지 않게 함.
  @override
  void dispose() {
    final stop = _stopAnalysis;
    if (stop != null && !stop.isCompleted) stop.complete();
    for (final f in _barFocus.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// DB에서 설정과 페이지 행, 표시 순서를 다시 읽음. 마디수를 칠 때마다 불리므로
  /// 더 나중에 시작한 읽기가 있으면 결과를 버림.
  /// 실패하면 사유를 남김. 그냥 두면 스피너가 영원히 돌아 사용자가 앱이 멈췄다고 판단함.
  Future<void> _reload() async {
    final seq = ++_reloadSeq;
    try {
      final repo = ref.read(scoreRepoProvider);
      final s = await repo.score(widget.scoreId);
      final p = await repo.pages(widget.scoreId);
      if (!mounted || seq != _reloadSeq) return;
      if (s == null) {
        setState(() => _loadError = '악보 설정을 찾지 못함');
        return;
      }
      final undo = await ref.read(aiAnalysisProvider).hasUndo(widget.scoreId);
      if (!mounted || seq != _reloadSeq) return;
      final order = parsePageOrder(s.pageOrderJson, p.length);
      _hasUndo = undo;
      setState(() {
        _loadError = null;
        _score = s;
        _pages = p;
        _order = order;
        _repeats = repeatsFromPlayOrder(
          parsePlayOrder(s.playOrderJson, order.length),
          order.length,
        );
      });
    } catch (e) {
      if (mounted && seq == _reloadSeq) setState(() => _loadError = '$e');
    }
  }

  /// 이 화면 전용 창구로 알림을 띄움. 동작이 달려도 시간이 지나면 닫힘.
  /// Flutter 3.29부터 동작 달린 스낵바는 기본으로 계속 남으므로 persist를 끔.
  void _notify(String text, {SnackBarAction? action, Duration? duration}) {
    _messenger.currentState?.showSnackBar(
      SnackBar(
        content: Text(text),
        action: action,
        duration: duration ?? const Duration(seconds: 4),
        persist: false,
      ),
    );
  }

  /// 뷰어를 그 쪽으로 옮기고 목록에 선택 표시함. 마디를 세는 쪽과 보이는 쪽이 어긋나지 않게 함.
  void _focusPage(int pageIndex) {
    if (_selected != pageIndex) setState(() => _selected = pageIndex);
    if (_viewer.isReady) _viewer.goToPage(pageNumber: pageIndex + 1);
  }

  /// 쪽 마디수 칸의 초점. 처음 부를 때 만들고 dispose에서 버림.
  FocusNode _barFocusOf(int pageIndex) =>
      _barFocus.putIfAbsent(pageIndex, () => FocusNode(debugLabel: 'bars-$pageIndex'));

  /// 표시 순서를 저장하고 다시 읽음. 반복은 길이가 달라지므로 함께 맞춤.
  Future<void> _saveOrder(List<int> order, List<int> repeats) async {
    final repo = ref.read(scoreRepoProvider);
    await repo.setPageOrder(widget.scoreId, order);
    await repo.setPlayOrder(widget.scoreId, playOrderFromRepeats(repeats));
    await _reload();
  }

  /// 현재 설정으로 계산한 총 연주 시간. 설정이 맞는지 바로 확인하는 용도.
  Duration get _totalDuration {
    final s = _score;
    if (s == null || _order.isEmpty) return Duration.zero;
    final visible = [for (final i in _order) _pages[i]];
    final t = buildTimeline(
      ScoreTiming(
        bpm: s.bpm,
        clicksPerBar: s.clicksPerBar,
        countInBars: s.countInBars,
        leadBeats: s.leadBeats,
        pages: [
          for (final p in visible)
            PageTiming(barCount: p.barCount, bpm: p.bpm, clicksPerBar: p.clicksPerBar),
        ],
        playOrder: playOrderFromRepeats(_repeats),
      ),
    );
    return secondsToDuration(t.totalSeconds);
  }

  /// 악보 전체 설정을 고치고 다시 읽음.
  Future<void> _update({
    double? bpm,
    int? timeSigNum,
    int? timeSigDen,
    int? clicksPerBar,
    int? countInBars,
    double? leadBeats,
  }) async {
    await ref
        .read(scoreRepoProvider)
        .updateSettings(
          widget.scoreId,
          bpm: bpm,
          timeSigNum: timeSigNum,
          timeSigDen: timeSigDen,
          clicksPerBar: clicksPerBar,
          countInBars: countInBars,
          leadBeats: leadBeats,
        );
    await _reload();
  }

  /// 박자표를 바꾸면 마디당 클릭 수 기본값도 함께 맞춰 줌.
  Future<void> _setTimeSignature(int num, int den) =>
      _update(timeSigNum: num, timeSigDen: den, clicksPerBar: defaultClicksPerBar(num, den));

  /// 곡 템포를 숫자로 직접 받음. 범위를 벗어나면 대화상자에서 알리고 닫지 않음.
  Future<void> _askBpm(Score s) async {
    final values = await _askNumbers('곡 템포', [
      _NumberSpec('BPM', initial: s.bpm.round(), min: kMinBpm.round(), max: kMaxBpm.round()),
    ]);
    if (values != null) await _update(bpm: values.first.toDouble());
  }

  /// 곡 전체 마디수를 받아 보이는 쪽에 균등 배분함. 숨긴 쪽과 0마디로 둔 쪽(표지)은 뺌.
  /// 쪽별로 넣은 값을 덮어쓰므로 이전 값으로 되돌리는 동작을 알림에 붙임.
  Future<void> _distribute() async {
    final targets = barDistributionTargets(_order, _pages);
    if (targets.isEmpty) return;
    final skipped = _order.length - targets.length;
    final values = await _askNumbers('전체 마디수 배분', [
      _NumberSpec(
        '곡 전체 마디수',
        min: 1,
        max: targets.length * kMaxBarsPerPage,
        hint:
            '보이는 ${targets.length}쪽에 나눔${skipped > 0 ? '. 0마디인 $skipped쪽은 뺌' : ''}. '
            '쪽별로 넣은 값을 덮어씀',
      ),
    ], confirm: '배분');
    if (values == null) return;
    final before = {for (final i in targets) i: _pages[i].barCount};
    final repo = ref.read(scoreRepoProvider);
    await repo.distributeBars(widget.scoreId, values.first);
    await _reload();
    _notify(
      '${targets.length}쪽에 나눔',
      action: SnackBarAction(
        label: '되돌리기',
        onPressed: () async {
          for (final e in before.entries) {
            await repo.updatePage(widget.scoreId, e.key, barCount: e.value);
          }
          await _reload();
        },
      ),
    );
  }

  /// 뷰어와 설정 목록. 읽기 실패면 사유와 다시 시도를, 작업 중에는 뒤로가기를 막음.
  @override
  Widget build(BuildContext context) {
    final s = _score;
    final wide = MediaQuery.sizeOf(context).width > 720;
    final viewer = PdfViewer(
      // 회전으로 파일이 바뀌므로 문서 캐시 키에 세대를 넣어 옛 내용을 다시 쓰지 않게 함
      PdfDocumentRefFile(widget.pdfPath, key: PdfDocumentRefKey(widget.pdfPath, [_viewerEpoch])),
      key: ValueKey('${widget.pdfPath}#$_viewerEpoch'),
      controller: _viewer,
      params: const PdfViewerParams(margin: 12),
    );
    final panel = _loadError != null
        ? EmptyState(
            icon: Icons.error_outline,
            title: '설정을 읽지 못함',
            message: _loadError,
            action: FilledButton(onPressed: _reload, child: const Text('다시 시도')),
          )
        : s == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            children: [
              _scoreSection(s),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(kGapL, kGapM, kGapS, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '페이지별 마디수',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _distribute,
                      icon: const Icon(Icons.calculate_outlined, size: 18),
                      label: const Text('균등 배분'),
                    ),
                  ],
                ),
              ),
              // 옛 마디수 대화상자에 있던 규칙. 도돌이표를 빼고 세면 넘김이 일러짐
              Padding(
                padding: const EdgeInsets.fromLTRB(kGapL, 0, kGapL, kGapS),
                child: Text(
                  '그 쪽을 보는 동안 흐르는 마디 수로 셈. 쪽 안의 도돌이표는 되풀이되는 만큼 더하고, 표지는 0',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              _orderedPages(),
              if (_order.length < _pages.length) _hiddenPages(),
              const SizedBox(height: 24),
            ],
          );

    return PopScope(
      // 회전·AI 분석은 파일과 설정을 바꾸는 작업. 끝나기 전에 나가면 리더가 반쯤 바뀐 상태를 읽고
      // 회전 전 좌표로 캐시한 필기를 회전된 필기 위에 덮어씀. AI 분석은 오래 걸릴 수 있어
      // 뒤로가기를 멈춤으로 받고, 멈춘 뒤에 닫음
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelAnalysis(leave: true);
      },
      child: ScaffoldMessenger(key: _messenger, child: _scaffold(s, viewer, panel, wide)),
    );
  }

  /// 화면 골격. 작업 중에는 본문을 진행 표시로 바꿈.
  Widget _scaffold(Score? s, Widget viewer, Widget panel, bool wide) => Scaffold(
    appBar: AppBar(
      // 리더 상단도 곡 제목이라 제목만 두면 어느 화면인지 구분이 안 됨
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('재생 설정'),
          if (widget.title != null)
            Text(
              widget.title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      actions: [
        if (_hasUndo)
          IconButton(
            tooltip: 'AI 반영 되돌리기',
            icon: const Icon(Icons.undo),
            onPressed: _busy ? null : _undoAi,
          ),
        if (ref.watch(coinWalletProvider).available)
          IconButton(
            tooltip: 'AI로 마디수 읽기',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: _busy ? null : _analyzeWithAi,
          ),
      ],
      bottom: PreferredSize(
        // 글꼴을 키운 기기에서 칩이 잘리지 않도록 배율만큼 높이를 늘림
        preferredSize: Size.fromHeight(MediaQuery.textScalerOf(context).scale(40)),
        child: _summary(s),
      ),
    ),
    // 아래·좌우만 보호함. 위는 AppBar가 이미 처리함
    body: SafeArea(
      top: false,
      child: _busy
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: kGapL),
                  Text(_busyLabel),
                  if (_stopAnalysis != null) ...[
                    const SizedBox(height: kGapL),
                    OutlinedButton(onPressed: _cancelAnalysis, child: const Text('취소')),
                  ],
                ],
              ),
            )
          : wide
          ? Row(
              children: [
                Expanded(child: viewer),
                SizedBox(width: 380, child: panel),
              ],
            )
          : Column(
              children: [
                Expanded(flex: 2, child: viewer),
                Expanded(flex: 3, child: panel),
              ],
            ),
    ),
  );

  /// 상단 요약 줄. 설정을 바꿀 때마다 결과가 어떻게 변하는지 바로 보이게 함.
  /// 높이가 고정이라 줄바꿈은 잘림. 큰 글꼴에서는 가로로 밀어 보게 함.
  Widget _summary(Score? s) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(kGapL, 0, kGapL, kGapM),
    child: Row(
      children: [
        _summaryChip(Icons.schedule, _fmt(_totalDuration)),
        const SizedBox(width: kGapS),
        _summaryChip(Icons.description_outlined, '${_order.length}쪽'),
        const SizedBox(width: kGapS),
        if (s != null) _summaryChip(Icons.speed, '${s.bpm.round()} BPM'),
      ],
    ),
  );

  /// 요약 줄의 항목 하나.
  Widget _summaryChip(IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: kGapM, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: kGapXs + 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(fontFeatures: kTabular),
          ),
        ],
      ),
    );
  }

  /// 악보 전체에 적용되는 설정들.
  /// 칩 묶음을 ListTile의 trailing에 넣으면 제목이 한 글자씩 접히므로 아래 줄로 내림.
  Widget _scoreSection(Score s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            const Text('템포'),
            const SizedBox(width: 12),
            // 슬라이더로는 96 같은 값을 짚기 어려움. 숫자를 눌러 바로 넣게 함
            TextButton.icon(
              onPressed: () => _askBpm(s),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text('${s.bpm.round()} BPM', style: Theme.of(context).textTheme.titleMedium),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGapS),
        child: Row(
          children: [
            IconButton(
              tooltip: '템포 1 낮춤',
              icon: const Icon(Icons.remove),
              onPressed: () => _update(bpm: _bpmStep(s.bpm, -1)),
            ),
            Expanded(
              child: Slider(
                min: 30,
                max: 300,
                divisions: 270,
                value: s.bpm.clamp(30, 300),
                label: s.bpm.round().toString(),
                onChanged: (v) => setState(() => _score = s.copyWith(bpm: v)),
                onChangeEnd: (v) => _update(bpm: v),
              ),
            ),
            IconButton(
              tooltip: '템포 1 올림',
              icon: const Icon(Icons.add),
              onPressed: () => _update(bpm: _bpmStep(s.bpm, 1)),
            ),
          ],
        ),
      ),
      _settingRow('박자표', '${s.timeSigNum}/${s.timeSigDen} · 마디당 클릭 ${s.clicksPerBar}', [
        for (final ts in const [
          [4, 4],
          [3, 4],
          [2, 4],
          [5, 4],
          [6, 8],
          [7, 8],
          [12, 8],
        ])
          ChoiceChip(
            label: Text('${ts[0]}/${ts[1]}'),
            selected: s.timeSigNum == ts[0] && s.timeSigDen == ts[1],
            onSelected: (_) => _setTimeSignature(ts[0], ts[1]),
          ),
      ]),
      _settingRow('마디당 클릭', '박자표에서 정한 값을 덮어씀. 5/4·7/8처럼 특이한 박자에 씀', [
        for (final n in const [2, 3, 4, 5, 6, 7])
          ChoiceChip(
            label: Text('$n'),
            selected: s.clicksPerBar == n,
            onSelected: (_) => _update(clicksPerBar: n),
          ),
      ]),
      _settingRow('카운트인', '시작 전에 ${s.countInBars}마디를 미리 셈', [
        for (final n in const [0, 1, 2])
          ChoiceChip(
            label: Text('$n'),
            selected: s.countInBars == n,
            onSelected: (_) => _update(countInBars: n),
          ),
      ]),
      _settingRow('선행 넘김', '페이지 끝 ${s.leadBeats.round()}박 전에 넘김', [
        for (final n in const [0.0, 1.0, 2.0, 4.0])
          ChoiceChip(
            label: Text(n.round().toString()),
            selected: s.leadBeats == n,
            onSelected: (_) => _update(leadBeats: n),
          ),
      ]),
    ],
  );

  /// 제목·설명 아래에 선택 칩을 한 줄로 놓는 설정 항목.
  Widget _settingRow(String title, String subtitle, List<Widget> chips) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: chips),
      ],
    ),
  );

  /// 표시 중인 페이지를 순서 변경 가능한 목록으로 보여줌.
  Widget _orderedPages() => ReorderableListView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    buildDefaultDragHandles: false,
    itemCount: _order.length,
    // onReorderItem은 제거된 항목을 감안해 newIndex를 이미 보정해서 줌
    onReorderItem: (from, to) {
      final order = [..._order];
      final repeats = [..._repeats];
      order.insert(to, order.removeAt(from));
      repeats.insert(to, repeats.removeAt(from));
      _saveOrder(order, repeats);
    },
    itemBuilder: (_, i) => _pageTile(_pages[_order[i]], i),
  );

  /// 숨긴 페이지 목록. 되살릴 수 있게 따로 보여줌.
  Widget _hiddenPages() {
    final hidden = [
      for (var i = 0; i < _pages.length; i++)
        if (!_order.contains(i)) i,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('숨긴 페이지')),
        for (final i in hidden)
          ListTile(
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: const Text('숨김'),
            trailing: TextButton(
              onPressed: () => _saveOrder([..._order, i], [..._repeats, 1]),
              child: const Text('되살리기'),
            ),
          ),
      ],
    );
  }

  /// 페이지 한 장의 마디수 입력 줄. 줄을 누르거나 칸에 들어가면 뷰어가 그 페이지로 이동함.
  /// 칸에서 다음을 누르면 표시 순서상 다음 쪽 칸으로 넘어가 모달 없이 이어서 넣음.
  Widget _pageTile(ScorePage p, int slot) {
    final s = _score!;
    final bpm = p.bpm ?? s.bpm;
    final cpb = p.clicksPerBar ?? s.clicksPerBar;
    final seconds = p.barCount * barSeconds(cpb, bpm);
    final repeat = slot < _repeats.length ? _repeats[slot] : 1;
    final isLast = slot == _order.length - 1;
    return ListTile(
      key: ValueKey(p.pageIndex),
      selected: _selected == p.pageIndex,
      leading: ReorderableDragStartListener(
        index: slot,
        child: CircleAvatar(child: Text('${p.pageIndex + 1}')),
      ),
      title: _BarsField(
        pageNumber: p.pageIndex + 1,
        value: p.barCount,
        focusNode: _barFocusOf(p.pageIndex),
        isLast: isLast,
        onChanged: (bars) => _setBars(p, bars),
        onFocusPage: () => _focusPage(p.pageIndex),
        onNext: () {
          final next = _order.indexOf(p.pageIndex) + 1;
          if (next > 0 && next < _order.length) _barFocusOf(_order[next]).requestFocus();
        },
      ),
      subtitle: Text(
        '${(seconds * repeat).toStringAsFixed(1)}초'
        '${repeat > 1 ? '  ·  $repeat회 반복' : ''}'
        '${p.bpm != null ? '  ·  ${p.bpm!.toStringAsFixed(0)} BPM' : ''}'
        '${p.clicksPerBar != null ? '  ·  마디당 ${p.clicksPerBar}' : ''}',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          switch (v) {
            case 'rotate-cw':
              _rotate(p.pageIndex, 1);
            case 'rotate-ccw':
              _rotate(p.pageIndex, 3);
            case 'bars':
              _barFocusOf(p.pageIndex).requestFocus();
            case 'tempo':
              _askPageTempo(p);
            case 'tempo-clear':
              _clearPageOverride(p, bpm: true);
            case 'clicks-clear':
              _clearPageOverride(p, clicks: true);
            case 'hide':
              final order = [..._order]..removeAt(slot);
              final repeats = [..._repeats]..removeAt(slot);
              if (order.isEmpty) return;
              _saveOrder(order, repeats);
            case 'repeat+':
              final repeats = [..._repeats];
              repeats[slot] = (repeats[slot] + 1).clamp(1, 9);
              _saveOrder(_order, repeats);
            case 'repeat-':
              final repeats = [..._repeats];
              repeats[slot] = (repeats[slot] - 1).clamp(1, 9);
              _saveOrder(_order, repeats);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'rotate-cw',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.rotate_right),
              title: Text('오른쪽으로 90도'),
            ),
          ),
          const PopupMenuItem(
            value: 'rotate-ccw',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.rotate_left),
              title: Text('왼쪽으로 90도'),
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'bars', child: Text('마디수 입력')),
          const PopupMenuItem(value: 'tempo', child: Text('이 페이지만 템포·박 바꾸기')),
          if (p.bpm != null)
            const PopupMenuItem(value: 'tempo-clear', child: Text('이 페이지 템포 되돌리기')),
          if (p.clicksPerBar != null)
            const PopupMenuItem(value: 'clicks-clear', child: Text('이 페이지 박 되돌리기')),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'repeat+', child: Text('반복 늘리기')),
          const PopupMenuItem(value: 'repeat-', child: Text('반복 줄이기')),
          const PopupMenuItem(value: 'hide', child: Text('이 페이지 숨기기')),
        ],
      ),
      onTap: () => _focusPage(p.pageIndex),
    );
  }

  /// AI 분석 진입점. 확인 대화상자가 뜨기 전 두 번 눌러 분석이 둘 돌면 멈춤이 하나만 멈추므로 막음.
  Future<void> _analyzeWithAi() async {
    if (_aiRunning) return;
    _aiRunning = true;
    try {
      await _runAiAnalysis();
    } finally {
      _aiRunning = false;
    }
  }

  /// 남은 쪽의 코인을 확인받고 악보 전체를 AI에 넘겨 쪽별 마디수와 템포를 반영함.
  Future<void> _runAiAnalysis() async {
    // 추정이 틀릴 수 있어 반영 전 상태를 스냅샷으로 남기고 결과에 확신도를 함께 알림
    if (_busy) return;
    final wallet = ref.read(coinWalletProvider);
    final pageCount = _pages.length;
    if (pageCount == 0) return;

    // 첫 실행이 오프라인이었으면 아직 기기 등록이 안 됐을 수 있음
    if (!wallet.ready) await wallet.refresh();
    if (!mounted) return;
    if (!wallet.ready) {
      _notify(wallet.lastError ?? '서버에 연결하지 못함');
      return;
    }

    // 앞서 끊긴 분석을 이어받으면 결과를 받은 쪽은 코인이 들지 않으므로 남은 쪽으로 판정함.
    // 보냈지만 답을 못 받은 쪽(멈춤 등)은 서버가 같은 id로 코인 없이 줄 수 있어 막지 않고 알리기만 함.
    // 서버가 처리하지 못해 코인이 다시 들고 잔액이 모자라면 서버가 402로 막음
    final charge = await ref
        .read(aiAnalysisProvider)
        .pagesToCharge(
          widget.scoreId,
          pageCount: pageCount,
          perCall: wallet.pricing?.maxPagesPerCall ?? 8,
        );
    if (!mounted) return;
    final toCharge = charge.charged;
    final cost = wallet.costFor(toCharge);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('AI로 마디수 읽기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$pageCount쪽을 분석함. 코인 $cost개를 씀 (남은 코인 ${wallet.balance}개).'),
            if (charge.pending > 0) ...[
              const SizedBox(height: kGapM),
              Text(
                '앞서 보내고 답을 못 받은 ${charge.pending}쪽은 서버가 처리했으면 코인 없이 받고, '
                '처리하지 못했으면 코인 ${wallet.costFor(charge.pending)}개가 더 듦.',
              ),
            ],
            const SizedBox(height: kGapM),
            Text(
              '읽은 값은 바로 설정에 들어감. 틀린 곳이 있으면 되돌리거나 직접 고칠 수 있음.\n'
              '템포는 악보에 적혀 있을 때만 반영함.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(
            onPressed: wallet.canAfford(toCharge) ? () => Navigator.pop(c, true) : null,
            child: Text(wallet.canAfford(toCharge) ? '분석' : '코인 부족'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final stop = Completer<void>();
    setState(() {
      _busy = true;
      _busyLabel = '악보를 그림으로 바꾸는 중';
      _stopAnalysis = stop;
      _leaveAfterStop = false;
    });
    try {
      final result = await ref
          .read(aiAnalysisProvider)
          .analyzeAndApply(
            wallet.token!,
            scoreId: widget.scoreId,
            pdfPath: widget.pdfPath,
            pageCount: pageCount,
            maxPagesPerCall: wallet.pricing?.maxPagesPerCall ?? 8,
            cancel: stop,
            onProgress: (stage, done, total) {
              // 멈춘 뒤에도 버려진 렌더가 진행을 알릴 수 있어 무시함
              if (!mounted || stop.isCompleted) return;
              setState(() {
                _busyLabel = stage == 'render'
                    ? '악보를 그림으로 바꾸는 중 ($done/$total)'
                    : 'AI가 읽는 중 ($done/$total)';
              });
            },
          );
      // 끝까지 못 간 경우의 잔액은 실패한 묶음의 환불을 반영하지 않은 값이라 다시 물어봄
      if (result.partialReason != null) {
        await wallet.refresh();
      } else {
        wallet.setBalance(result.balance);
      }
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      _notify(
        '${result.appliedPages}쪽 반영'
        '${result.bpmApplied ? ', 템포도 읽음' : ''}'
        '${result.lowConfidence > 0 ? ' · 확신이 낮은 ${result.lowConfidence}쪽은 확인 권함' : ''}'
        '${result.missingPages.isNotEmpty ? '\n${result.missingPages.join(', ')}쪽은 읽지 못함' : ''}'
        '${result.partialReason != null ? '\n뒷부분은 읽지 못함: ${result.partialReason}' : ''}',
        action: SnackBarAction(label: '되돌리기', onPressed: _undoAi),
        duration: const Duration(seconds: 8),
      );
    } on AnalysisCancelled {
      // 멈추기 전에 빠진 코인을 잔액에 반영함. 화면을 닫아도 지갑은 앱 전역이라 기다리지 않음
      unawaited(wallet.refresh());
      if (!_leaveAfterStop) _notify('분석을 멈춤. 다시 누르면 이미 쓴 코인으로 이어서 읽음');
    } catch (e) {
      _notify('분석 실패: $e');
    } finally {
      if (mounted) {
        final leave = _leaveAfterStop;
        setState(() {
          _busy = false;
          _busyLabel = '';
          _stopAnalysis = null;
          _leaveAfterStop = false;
        });
        if (leave) Navigator.of(context).pop();
      }
    }
  }

  /// 진행 중인 AI 분석을 멈춤. leave면 멈춘 뒤 화면을 닫음. 분석 중이 아니면 아무것도 안 함.
  void _cancelAnalysis({bool leave = false}) {
    final stop = _stopAnalysis;
    if (stop == null) return;
    if (leave) _leaveAfterStop = true;
    if (!stop.isCompleted) stop.complete();
  }

  /// AI가 바꾸기 직전 상태로 되돌림.
  Future<void> _undoAi() async {
    final ok = await ref.read(aiAnalysisProvider).undo(widget.scoreId);
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    _notify(ok ? '이전 설정으로 되돌림' : '되돌릴 내용이 없음');
  }

  /// 페이지를 90도 돌림. PDF에 구우므로 시간이 걸려 무엇을 기다리는지 진행 표시에 적고,
  /// 끝나면 뷰어 캐시와 썸네일을 함께 버림. 도중에 화면이 닫혀도 라이브러리 칸에는 알림.
  Future<void> _rotate(int pageIndex, int quarterTurns) async {
    if (_busy) return;
    // 화면이 닫힌 뒤에는 ref를 읽을 수 없으므로 기다리기 전에 잡아 둠
    final library = ref.read(libraryRepoProvider);
    setState(() {
      _busy = true;
      _busyLabel = '페이지를 돌리는 중';
    });
    try {
      await ref.read(scoreRepoProvider).rotatePage(widget.scoreId, pageIndex, quarterTurns);
      final thumb = File(AppPaths.abs(AppPaths.thumbnail(widget.scoreId)));
      if (await thumb.exists()) await thumb.delete();
      await generateThumbnail(widget.pdfPath, thumb.path);
      imageCache.clear();
      imageCache.clearLiveImages();
      // 라이브러리 칸은 노드가 바뀌어야 표지를 다시 읽음. 파일만 바꾸면 옛 표지가 남음.
      // 이 화면의 수명과 무관하므로 닫혔는지 보기 전에 알림
      await library.touch([widget.scoreId]);
      if (!mounted) return;
      setState(() => _viewerEpoch++);
      await _reload();
    } catch (e) {
      _notify('회전 실패: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = '';
        });
      }
    }
  }

  /// 페이지 마디수를 바꾸고 다시 읽음.
  Future<void> _setBars(ScorePage p, int bars) async {
    await ref.read(scoreRepoProvider).updatePage(widget.scoreId, p.pageIndex, barCount: bars);
    await _reload();
  }

  /// 숫자 입력 대화상자를 띄움. 모든 칸이 범위 안이어야 닫힘. 취소하면 null.
  Future<List<int>?> _askNumbers(String title, List<_NumberSpec> specs, {String confirm = '확인'}) =>
      showDialog<List<int>>(
        context: context,
        builder: (_) => _NumbersDialog(title: title, specs: specs, confirm: confirm),
      );

  /// 이 페이지에서만 쓸 템포와 마디당 클릭 수를 한 대화상자에서 받음. 곡 중간에 템포가 바뀔 때 씀.
  /// 바꾼 항목만 오버라이드로 남김. 손대지 않은 값까지 박으면 뒤에 곡 템포·박을 바꿔도 이 쪽만 옛 값으로 돎.
  Future<void> _askPageTempo(ScorePage p) async {
    final s = _score!;
    final shownBpm = (p.bpm ?? s.bpm).round();
    final shownClicks = p.clicksPerBar ?? s.clicksPerBar;
    final values = await _askNumbers('${p.pageIndex + 1}쪽 템포·박', [
      _NumberSpec(
        'BPM',
        initial: shownBpm,
        min: kMinBpm.round(),
        max: kMaxBpm.round(),
        hint: '이 페이지부터가 아니라 이 페이지에만 적용됨. 곡 템포와 같게 두면 곡 템포를 따라감',
      ),
      _NumberSpec('마디당 클릭 수', initial: shownClicks, min: 1, max: 16, hint: '곡 설정과 같게 두면 곡 설정을 따라감'),
    ]);
    if (values == null) return;
    await ref
        .read(scoreRepoProvider)
        .updatePage(
          widget.scoreId,
          p.pageIndex,
          bpm: pageOverride(values[0].toDouble(), shown: shownBpm, inherited: s.bpm),
          clicksPerBar: pageOverride(values[1], shown: shownClicks, inherited: s.clicksPerBar),
        );
    await _reload();
  }

  /// 페이지 오버라이드를 하나씩 지워 악보 기본값을 상속하게 함. 템포와 박을 따로 풂.
  Future<void> _clearPageOverride(ScorePage p, {bool bpm = false, bool clicks = false}) async {
    await ref
        .read(scoreRepoProvider)
        .updatePage(
          widget.scoreId,
          p.pageIndex,
          bpm: bpm ? const Value(null) : const Value.absent(),
          clicksPerBar: clicks ? const Value(null) : const Value.absent(),
        );
    await _reload();
  }
}

/// 곡 템포를 한 BPM씩 옮긴 값. 소수 템포는 먼저 정수로 맞추고, 다룰 수 있는 범위 안에서 멈춤.
double _bpmStep(double bpm, int delta) =>
    (bpm.round() + delta).clamp(kMinBpm.round(), kMaxBpm.round()).toDouble();

/// 쪽 하나의 마디수 칸과 −/+ 단추. 칠 때마다 저장해 다음을 누르지 않고 나가도 값을 잃지 않음.
/// 칸에 들어가거나 단추를 누르면 onFocusPage로 뷰어를 그 쪽에 맞춤.
class _BarsField extends StatefulWidget {
  /// 초점 노드는 부모가 만들고 버림. 이 칸은 듣기만 함.
  const _BarsField({
    required this.pageNumber,
    required this.value,
    required this.focusNode,
    required this.isLast,
    required this.onChanged,
    required this.onFocusPage,
    required this.onNext,
  });

  /// 1부터 세는 쪽 번호. 보조 기술이 읽을 이름에 씀.
  final int pageNumber;

  /// DB에 저장된 마디수.
  final int value;
  final FocusNode focusNode;

  /// 표시 순서상 마지막 쪽이면 키보드 동작을 '완료'로 둠.
  final bool isLast;
  final Future<void> Function(int bars) onChanged;
  final VoidCallback onFocusPage;
  final VoidCallback onNext;

  /// 입력 버퍼와 저장 대기 수를 든 상태를 만듦.
  @override
  State<_BarsField> createState() => _BarsFieldState();
}

class _BarsFieldState extends State<_BarsField> {
  late final _text = TextEditingController(text: '${widget.value}');

  /// 저장을 기다리는 입력 수. 그동안 들어온 값은 이 칸이 보낸 값의 메아리라 치는 중인 글자를 덮지 않음.
  var _pending = 0;

  /// 초점 변화를 듣기 시작함.
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  /// 저장된 값이 밖에서 바뀌었으면(배분·AI·되돌리기) 칸에 반영하고 전부 골라 둠.
  /// 저장 대기 중이거나 초점 있는 칸을 비워 새 값을 치는 중이면 두고 봄. 빈 칸은 초점을 잃을 때 채움.
  @override
  void didUpdateWidget(covariant _BarsField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
    final typed = int.tryParse(_text.text);
    // 늦게 끝난 저장의 메아리가 지운 글자를 되살리면 이어 친 숫자가 옛 값 뒤에 붙음
    if (_pending > 0 || typed == widget.value || (typed == null && widget.focusNode.hasFocus)) {
      return;
    }
    final shown = '${widget.value}';
    _text.value = TextEditingValue(
      text: shown,
      selection: TextSelection(baseOffset: 0, extentOffset: shown.length),
    );
  }

  /// 초점 듣기를 멈추고 입력 버퍼를 버림. 초점 노드는 부모 소유라 버리지 않음.
  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    _text.dispose();
    super.dispose();
  }

  /// 초점을 얻으면 뷰어를 이 쪽으로 옮기고 글자를 전부 골라 바로 덮어쓰게 함.
  /// 잃을 때 칸이 비어 있으면 저장된 값으로 되돌림.
  void _onFocus() {
    if (widget.focusNode.hasFocus) {
      widget.onFocusPage();
      _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    } else if (int.tryParse(_text.text) == null) {
      _text.text = '${widget.value}';
    }
  }

  /// 값을 저장함. 저장이 끝나기 전의 화면 갱신이 치는 중인 글자를 덮지 않게 셈.
  Future<void> _commit(int bars) async {
    _pending++;
    try {
      await widget.onChanged(bars);
    } finally {
      _pending--;
    }
  }

  /// −/+ 단추. 칸에 보이는 값을 기준으로 한 마디씩 바꾸고 저장함.
  void _step(int delta) {
    widget.onFocusPage();
    final next = ((int.tryParse(_text.text) ?? widget.value) + delta).clamp(0, kMaxBarsPerPage);
    _text.text = '$next';
    _commit(next);
  }

  /// −, 숫자 칸, + 한 줄. 숫자 칸은 누르기 쉽게 최소 48dp 높이를 둠.
  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: '${widget.pageNumber}쪽 마디수 줄임',
        icon: const Icon(Icons.remove),
        onPressed: widget.value <= 0 ? null : () => _step(-1),
      ),
      Expanded(
        child: Semantics(
          label: '${widget.pageNumber}쪽 마디수',
          child: TextField(
            controller: _text,
            focusNode: widget.focusNode,
            // iOS 숫자 패드에는 다음·완료 키가 없음. signed면 리턴 키가 있는 숫자 자판이 뜸
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            textInputAction: widget.isLast ? TextInputAction.done : TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              // 재생이 받는 상한(999)을 넘는 값은 칠 수 없게 함. 표시값과 재생값이 달라지지 않음
              LengthLimitingTextInputFormatter('$kMaxBarsPerPage'.length),
            ],
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFeatures: kTabular),
            decoration: const InputDecoration(
              isDense: true,
              suffixText: '마디',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: kGapS, vertical: kGapS),
              constraints: BoxConstraints(minHeight: kMinInteractiveDimension),
            ),
            onChanged: (v) {
              final bars = int.tryParse(v);
              if (bars != null) _commit(bars);
            },
            // 기본 동작은 같은 줄의 + 단추로 초점을 옮기므로 다음 쪽 칸으로 직접 보냄
            onEditingComplete: widget.isLast ? null : widget.onNext,
          ),
        ),
      ),
      IconButton(
        tooltip: '${widget.pageNumber}쪽 마디수 늘림',
        icon: const Icon(Icons.add),
        onPressed: () => _step(1),
      ),
    ],
  );
}

/// 숫자 입력 칸 하나의 명세. 범위를 벗어나면 대화상자를 닫지 않고 칸 아래에 알림.
class _NumberSpec {
  /// hint는 칸 아래 도움말. initial이 없으면 빈 칸으로 엶.
  const _NumberSpec(this.label, {this.initial, required this.min, required this.max, this.hint});

  final String label;
  final int? initial;
  final int min;
  final int max;
  final String? hint;
}

/// 숫자 여러 개를 한 번에 받는 대화상자. 모든 칸이 범위 안이어야 값 목록을 돌려주며 닫힘.
/// 틀린 값을 조용히 버리면 사용자는 저장된 줄 앎.
class _NumbersDialog extends StatefulWidget {
  /// confirm은 확인 단추 글자. 칸은 specs 순서대로 놓임.
  const _NumbersDialog({required this.title, required this.specs, required this.confirm});

  final String title;
  final List<_NumberSpec> specs;
  final String confirm;

  /// 칸마다 입력 버퍼와 오류 문구를 든 상태를 만듦.
  @override
  State<_NumbersDialog> createState() => _NumbersDialogState();
}

class _NumbersDialogState extends State<_NumbersDialog> {
  late final _controllers = [
    for (final s in widget.specs) TextEditingController(text: s.initial?.toString() ?? ''),
  ];
  late final _errors = List<String?>.filled(widget.specs.length, null);

  /// 입력 버퍼를 버림.
  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// 모든 칸을 검사해 틀린 칸에 사유를 달고, 모두 맞으면 값 목록을 돌려주며 닫음.
  void _submit() {
    final values = <int>[];
    setState(() {
      for (var i = 0; i < widget.specs.length; i++) {
        final spec = widget.specs[i];
        final v = int.tryParse(_controllers[i].text);
        final ok = v != null && v >= spec.min && v <= spec.max;
        _errors[i] = ok ? null : '${spec.min}~${spec.max} 사이로 넣어야 함';
        if (ok) values.add(v);
      }
    });
    if (values.length == widget.specs.length) Navigator.pop(context, values);
  }

  /// 칸들을 세로로 놓은 대화상자. 앞 칸에서 다음을 누르면 뒤 칸으로, 마지막 칸에서는 확인으로 감.
  @override
  Widget build(BuildContext context) {
    final last = widget.specs.length - 1;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i <= last; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : kGapM),
                child: TextField(
                  controller: _controllers[i],
                  autofocus: i == 0,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: i == last ? TextInputAction.done : TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: widget.specs[i].label,
                    helperText: widget.specs[i].hint,
                    helperMaxLines: 3,
                    errorText: _errors[i],
                  ),
                  onSubmitted: i == last ? (_) => _submit() : null,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(onPressed: _submit, child: Text(widget.confirm)),
      ],
    );
  }
}

/// 분:초 표기. 한 시간을 넘는 곡은 없다고 보고 분으로만 표시함.
String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
