// 악보 재생 설정 화면. 페이지별 마디수가 자동 넘김의 정확도를 결정하므로 입력하면서
// 바로 옆에서 해당 페이지를 볼 수 있게 뷰어를 함께 둠. 썸네일을 따로 렌더하지 않음.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

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

  /// 회전으로 파일이 바뀌면 올려서 뷰어 캐시를 버리게 함.
  int _viewerEpoch = 0;
  bool _busy = false;
  String _busyLabel = '';
  bool _hasUndo = false;

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

  /// DB에서 설정과 페이지 행, 표시 순서를 다시 읽음.
  /// 실패하면 사유를 남김. 그냥 두면 스피너가 영원히 돌아 사용자가 앱이 멈췄다고 판단함.
  Future<void> _reload() async {
    try {
      final repo = ref.read(scoreRepoProvider);
      final s = await repo.score(widget.scoreId);
      final p = await repo.pages(widget.scoreId);
      if (!mounted) return;
      if (s == null) {
        setState(() => _loadError = '악보 설정을 찾지 못함');
        return;
      }
      final undo = await ref.read(aiAnalysisProvider).hasUndo(widget.scoreId);
      if (!mounted) return;
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
      if (mounted) setState(() => _loadError = '$e');
    }
  }

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

  /// 전체 마디수를 받아 페이지에 균등 배분함.
  Future<void> _distribute() async {
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('전체 마디수 배분'),
          content: TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '곡 전체 마디수'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('배분')),
          ],
        );
      },
    );
    final total = int.tryParse(text ?? '');
    if (total == null) return;
    await ref.read(scoreRepoProvider).distributeBars(widget.scoreId, total);
    await _reload();
  }

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
              _orderedPages(),
              if (_order.length < _pages.length) _hiddenPages(),
              const SizedBox(height: 24),
            ],
          );

    return Scaffold(
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
  }

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
            Text('${s.bpm.round()} BPM', style: Theme.of(context).textTheme.titleMedium),
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

  /// 페이지 한 장의 마디수 입력 줄. 탭하면 뷰어가 그 페이지로 이동함.
  Widget _pageTile(ScorePage p, int slot) {
    final s = _score!;
    final bpm = p.bpm ?? s.bpm;
    final cpb = p.clicksPerBar ?? s.clicksPerBar;
    final seconds = p.barCount * barSeconds(cpb, bpm);
    final repeat = slot < _repeats.length ? _repeats[slot] : 1;
    return ListTile(
      key: ValueKey(p.pageIndex),
      selected: _selected == p.pageIndex,
      leading: ReorderableDragStartListener(
        index: slot,
        child: CircleAvatar(child: Text('${p.pageIndex + 1}')),
      ),
      title: Row(
        children: [
          IconButton(
            tooltip: '${p.pageIndex + 1}쪽 마디수 줄임',
            icon: const Icon(Icons.remove),
            onPressed: p.barCount <= 0 ? null : () => _setBars(p, p.barCount - 1),
          ),
          // 20마디를 +로 넣게 하지 않음. 숫자를 눌러 바로 입력할 수 있게 둠
          InkWell(
            onTap: () => _askBars(p),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: kGapS, vertical: kGapXs),
              child: SizedBox(
                width: MediaQuery.textScalerOf(context).scale(56),
                child: Text(
                  '${p.barCount}마디',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFeatures: kTabular),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '${p.pageIndex + 1}쪽 마디수 늘림',
            icon: const Icon(Icons.add),
            onPressed: () => _setBars(p, p.barCount + 1),
          ),
        ],
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
              _askBars(p);
            case 'tempo':
              _askPageTempo(p);
            case 'tempo-clear':
              _clearPageTempo(p);
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
          if (p.bpm != null || p.clicksPerBar != null)
            const PopupMenuItem(value: 'tempo-clear', child: Text('이 페이지 템포 되돌리기')),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'repeat+', child: Text('반복 늘리기')),
          const PopupMenuItem(value: 'repeat-', child: Text('반복 줄이기')),
          const PopupMenuItem(value: 'hide', child: Text('이 페이지 숨기기')),
        ],
      ),
      onTap: () {
        setState(() => _selected = p.pageIndex);
        if (_viewer.isReady) _viewer.goToPage(pageNumber: p.pageIndex + 1);
      },
    );
  }

  /// 코인을 써서 악보 전체를 AI에 넘기고 쪽별 마디수와 템포를 받아 반영함.
  /// 추정이 틀릴 수 있어 반영 전 상태를 스냅샷으로 남기고 결과에 확신도를 함께 알림.
  Future<void> _analyzeWithAi() async {
    if (_busy) return;
    final wallet = ref.read(coinWalletProvider);
    final pageCount = _pages.length;
    if (pageCount == 0) return;

    final messenger = ScaffoldMessenger.of(context);
    // 첫 실행이 오프라인이었으면 아직 기기 등록이 안 됐을 수 있음
    if (!wallet.ready) await wallet.refresh();
    if (!mounted) return;
    if (!wallet.ready) {
      messenger.showSnackBar(SnackBar(content: Text(wallet.lastError ?? '서버에 연결하지 못함')));
      return;
    }

    final cost = wallet.costFor(pageCount);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('AI로 마디수 읽기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$pageCount쪽을 분석함. 코인 $cost개를 씀 (남은 코인 ${wallet.balance}개).'),
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
            onPressed: wallet.canAfford(pageCount) ? () => Navigator.pop(c, true) : null,
            child: Text(wallet.canAfford(pageCount) ? '분석' : '코인 부족'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _busyLabel = '악보를 그림으로 바꾸는 중';
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
            onProgress: (stage, done, total) {
              if (!mounted) return;
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
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${result.appliedPages}쪽 반영'
            '${result.bpmApplied ? ', 템포도 읽음' : ''}'
            '${result.lowConfidence > 0 ? ' · 확신이 낮은 ${result.lowConfidence}쪽은 확인 권함' : ''}'
            '${result.partialReason != null ? '\n뒷부분은 읽지 못함: ${result.partialReason}' : ''}',
          ),
          action: SnackBarAction(label: '되돌리기', onPressed: _undoAi),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('분석 실패: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// AI가 바꾸기 직전 상태로 되돌림.
  Future<void> _undoAi() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(aiAnalysisProvider).undo(widget.scoreId);
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(ok ? '이전 설정으로 되돌림' : '되돌릴 내용이 없음')));
  }

  /// 페이지를 90도 돌림. PDF에 구우므로 시간이 걸려 진행 표시를 띄우고,
  /// 끝나면 뷰어 캐시와 썸네일을 함께 버림.
  Future<void> _rotate(int pageIndex, int quarterTurns) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(scoreRepoProvider).rotatePage(widget.scoreId, pageIndex, quarterTurns);
      final thumb = File(AppPaths.abs(AppPaths.thumbnail(widget.scoreId)));
      if (await thumb.exists()) await thumb.delete();
      await generateThumbnail(widget.pdfPath, thumb.path);
      imageCache.clear();
      imageCache.clearLiveImages();
      if (!mounted) return;
      setState(() => _viewerEpoch++);
      await _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('회전 실패: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 페이지 마디수를 바꾸고 다시 읽음.
  Future<void> _setBars(ScorePage p, int bars) async {
    await ref.read(scoreRepoProvider).updatePage(widget.scoreId, p.pageIndex, barCount: bars);
    await _reload();
  }

  /// 숫자를 직접 받는 공용 대화상자. 취소하거나 숫자가 아니면 null.
  Future<int?> _askNumber(String title, String label, {int? initial, String? hint}) async {
    final controller = TextEditingController(text: initial?.toString() ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, helperText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    return int.tryParse(text ?? '');
  }

  /// 페이지 마디수를 직접 입력받음. +/-로 스무 번 누르지 않아도 되게 함.
  Future<void> _askBars(ScorePage p) async {
    final bars = await _askNumber(
      '${p.pageIndex + 1}쪽 마디수',
      '마디수',
      initial: p.barCount,
      hint: '페이지 안 도돌이표는 되풀이되는 만큼 더해서 셈. 표지는 0',
    );
    if (bars == null || bars < 0) return;
    await _setBars(p, bars);
  }

  /// 이 페이지에서만 쓸 템포와 마디당 클릭 수를 받음. 곡 중간에 템포가 바뀔 때 씀.
  Future<void> _askPageTempo(ScorePage p) async {
    final s = _score!;
    final bpm = await _askNumber(
      '${p.pageIndex + 1}쪽 템포',
      'BPM',
      initial: (p.bpm ?? s.bpm).round(),
      hint: '이 페이지부터가 아니라 이 페이지에만 적용됨',
    );
    if (bpm == null || bpm < 20 || bpm > 400 || !mounted) return;
    final cpb = await _askNumber(
      '${p.pageIndex + 1}쪽 마디당 클릭',
      '마디당 클릭 수',
      initial: p.clicksPerBar ?? s.clicksPerBar,
    );
    if (cpb == null || cpb < 1 || cpb > 16) return;
    await ref
        .read(scoreRepoProvider)
        .updatePage(widget.scoreId, p.pageIndex, bpm: bpm.toDouble(), clicksPerBar: cpb);
    await _reload();
  }

  /// 페이지 템포 오버라이드를 지워 악보 기본값을 상속하게 함.
  Future<void> _clearPageTempo(ScorePage p) async {
    await ref.read(scoreRepoProvider).updatePage(widget.scoreId, p.pageIndex, clearOverrides: true);
    await _reload();
  }
}

/// 분:초 표기. 한 시간을 넘는 곡은 없다고 보고 분으로만 표시함.
String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
