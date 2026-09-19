// 라이브러리 화면. 악보는 이름보다 생김새로 알아보므로 썸네일 격자를 기본으로 둠.
// 데이터 변경은 전부 LibraryRepo를 거치고, 목록은 DB 감시 쿼리를 따라감. 여기서는 화면 상태만 들고 있음.

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/db/database.dart';
import '../core/db/tables.dart';
import '../core/progress_dialog.dart';
import '../core/providers.dart';
import '../core/storage/paths.dart';
import '../reader/reader_page.dart';
import '../score/import/import_service.dart';
import '../score/import/import_sources.dart';
import '../score/score_repo.dart';
import '../score/score_settings_page.dart';
import '../theme.dart';
import 'library_repo.dart';
import 'score_tile.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, this.folderId, this.title, this.active = true});

  /// null이면 루트.
  final int? folderId;
  final String? title;

  /// 지금 보이는 탭인지. 숨은 탭이 뒤로가기를 가로채지 않게 함.
  final bool active;

  /// 프로세스가 죽었다 살아나도 Navigator가 인자만으로 다시 만들 수 있는 폴더 화면 경로.
  /// 폴더 화면이 복원돼야 그 위에서 연 리더도 복원됨. entry-point 표시는 릴리스 복원에 필요함.
  @pragma('vm:entry-point')
  static Route<void> restorableRoute(BuildContext context, Object? arguments) {
    final args = (arguments! as Map).cast<String, Object?>();
    return MaterialPageRoute(
      builder: (_) =>
          LibraryPage(folderId: args['folderId']! as int, title: args['title'] as String?),
    );
  }

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _selected = <int>{};
  final _searchController = TextEditingController();

  String _query = '';
  bool _searching = false;

  /// 선택 모드. 롱프레스 말고도 들어올 길이 있어야 함.
  bool _selectionMode = false;

  /// 도는 임포트의 시작 시각. 칸이 이 뒤에 생긴 행의 표지를 가져오기에 맡기는 데 씀.
  DateTime? _importStartedAt;

  /// 임포트 진행 중. 끝나기 전에 또 누르면 같은 파일이 두 번 들어옴.
  bool get _importing => _importStartedAt != null;
  late Stream<List<Node>> _stream;

  /// 보고 있는 폴더가 살아 있는지 감시함. 루트는 감시하지 않음.
  StreamSubscription<bool>? _aliveSub;

  LibraryRepo get _repo => ref.read(libraryRepoProvider);

  /// 목록 감시를 걸고, 폴더 화면이면 그 폴더가 휴지통으로 가는지도 감시함.
  @override
  void initState() {
    super.initState();
    _stream = _watch();
    final folderId = widget.folderId;
    if (folderId != null) {
      _aliveSub = _repo.watchAlive(folderId).listen((alive) {
        if (!alive) _leave();
      });
    } else {
      // 앱이 막 뜬 루트 화면에서만 봄. 폴더마다 보면 같은 복구를 여러 번 물음
      WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostImport());
    }
  }

  /// 검색창과 폴더 감시를 정리함.
  @override
  void dispose() {
    _aliveSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// 검색어가 있으면 전체 검색, 없으면 현재 폴더의 자식을 감시함.
  /// 다른 탭·화면(휴지통 되살리기·영구 삭제, 가져오기)에서 바꿔도 목록이 따라옴.
  Stream<List<Node>> _watch() =>
      _query.isEmpty ? _repo.watchChildren(widget.folderId) : _repo.watchSearch(_query);

  /// 선택을 비우고 목록 감시를 새로 검. 임포트 도중 화면을 떠났을 수 있어 살아 있을 때만 함.
  void _reload() {
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selectionMode = false;
      _stream = _watch();
    });
  }

  /// 선택과 검색을 함께 끝냄. 뒤로가기가 화면 대신 이 모드들을 닫을 때 씀.
  void _exitModes() => setState(() {
    _selected.clear();
    _selectionMode = false;
    if (_searching) {
      _searching = false;
      _searchController.clear();
      _query = '';
      _stream = _watch();
    }
  });

  /// 보고 있던 폴더(또는 그 조상)가 휴지통으로 가면 이 화면을 닫음. 검색 결과에서 자기 폴더를
  /// 버릴 수 있음. 남아 있으면 빈 폴더로 보여 거기 들인 악보가 목록에도 휴지통에도 안 보이게 됨.
  void _leave() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  /// 새 폴더 이름을 받아 만듦.
  Future<void> _createFolder() async {
    final name = await _askText('새 폴더', '폴더 이름');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // 입력 칸 한도는 글자(grapheme) 단위, DB는 UTF-16 단위라 이모지가 든 이름은 칸을 통과해도 넘침
      await _repo.createFolder(clampNodeName(name), parentId: widget.folderId);
      _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('폴더를 만들지 못함: $e')));
    }
  }

  /// 항목 하나의 이름을 바꿈.
  Future<void> _rename(Node node) async {
    final name = await _askText('이름 변경', '새 이름', initial: node.name);
    if (name == null || name.trim().isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.rename(node.id, clampNodeName(name));
      _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('이름을 바꾸지 못함: $e')));
    }
  }

  /// 선택된 항목을 휴지통으로 보냄. 폴더는 하위까지 함께 감.
  /// 선택 항목을 휴지통으로 보냄. 30일 되돌릴 수 있는 조작이라 모달 대신 되돌리기를 붙임.
  /// 진짜 파괴적인 것은 휴지통의 영구 삭제이고 거기에는 확인이 있음.
  Future<void> _trash() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    // 되돌리기는 이 화면이 닫힌 뒤(자기 폴더를 버린 경우 포함)에도 눌리므로 저장소를 미리 잡아 둠
    final repo = _repo;
    try {
      await repo.moveToTrash(ids);
      _reload();
      // 앞선 알림이 남아 있으면 그 되돌리기를 이번 것으로 알고 누르게 됨
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${ids.length}개를 휴지통으로 보냄'),
            // 액션이 있으면 Flutter 3.47은 저절로 닫지 않아 모든 화면을 따라다니며 뒤 알림을 막음
            persist: false,
            action: SnackBarAction(label: '되돌리기', onPressed: () => repo.restore(ids)),
          ),
        );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('옮기지 못함: $e')));
    }
  }

  /// 폴더를 골라 선택 항목을 옮김. 자기 하위로 옮기려 하면 저장소가 막고 사유를 보여줌.
  Future<void> _move() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final target = await showDialog<_MoveTarget>(
      context: context,
      builder: (_) => const _FolderPickerDialog(),
    );
    if (target == null) return;
    try {
      await _repo.move(ids, target.folderId);
      _reload();
    } on ArgumentError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message.toString())));
    }
  }

  /// 짧은 텍스트 입력 다이얼로그. 취소하면 null.
  Future<String?> _askText(String title, String label, {String? initial}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: kMaxNodeNameLength,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('확인')),
        ],
      ),
    );
  }

  /// 폴더면 들어가고 악보면 리더를 연다.
  Future<void> _open(Node node) async {
    if (node.kind == NodeKind.folder) {
      // 폴더도 복원 가능한 경로로 열어야 그 안에서 연 리더가 프로세스 종료 뒤 돌아옴.
      // 목록은 감시 쿼리라 돌아온 뒤 다시 읽을 필요가 없음
      Navigator.restorablePush(
        context,
        LibraryPage.restorableRoute,
        arguments: <String, Object?>{'folderId': node.id, 'title': node.name},
      );
      return;
    }
    final score = await ref.read(scoreRepoProvider).score(node.id);
    if (score == null || !mounted) return;
    // 연습 중 다른 앱에 다녀온 사이 프로세스가 죽어도 보던 악보와 쪽으로 돌아오도록 복원 가능한 경로로 엶
    Navigator.restorablePush(
      context,
      ReaderPage.restorableRoute,
      arguments: ReaderPage.routeArguments(
        scoreId: node.id,
        fileRel: score.fileRel,
        title: node.name,
      ),
    );
  }

  /// 악보의 재생 설정 화면을 연다.
  Future<void> _openSettings(Node node) async {
    await _pushScoreSettings(Navigator.of(context), ref.read(scoreRepoProvider), node);
    _reload();
  }

  /// 임포트 방법을 고르는 시트. 어느 경로든 결과는 정규화 PDF 하나로 수렴함.
  Future<void> _showImportSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF 가져오기'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('이미지 가져오기'),
              subtitle: const Text('여러 장을 고르면 순서대로 한 악보가 됨'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('카메라로 스캔'),
              subtitle: const Text('가장자리를 자동으로 잡아 반듯하게 폄'),
              onTap: () => Navigator.pop(ctx, 'scan'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('새 폴더'),
              onTap: () => Navigator.pop(ctx, 'folder'),
            ),
            const SizedBox(height: kGapS),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'folder':
        await _createFolder();
      case 'pdf':
        await _importPdf();
      case 'image':
        await _importImages();
      case 'scan':
        await _importScan();
    }
  }

  /// 임포트를 돌리며 진행 표시를 띄우고 결과를 알려 줌.
  /// 끝나기 전에 또 누르면 같은 파일이 두 번 들어오므로 잠금.
  /// 파일마다 따로 돌려 하나가 실패해도 나머지는 들임. 들인 악보는 감시 중인 목록에 바로 나타남.
  /// 칸은 행이 생기는 순간 그려져 그때는 PDF·표지가 아직 없음. 칸은 시작 시각 뒤에 생긴 행의 표지를
  /// 만들지 않고 기다리며, 다 들인 뒤 노드를 건드리면 표지를 다시 찾음.
  /// 임포트 직후는 마디수가 기본값이라 그대로 재생하면 쪽당 8초로 넘어감. 다음 행동을 붙임.
  Future<void> _runImport(List<Future<int> Function(ImportService svc)> jobs) async {
    if (_importing) return;
    setState(() => _importStartedAt = DateTime.now());
    final messenger = ScaffoldMessenger.of(context);
    // 알림의 '설정'은 이 화면이 닫힌 뒤에도 눌리므로 ref·context 대신 잡아 둔 것만 씀
    final navigator = Navigator.of(context);
    final library = _repo;
    final scores = ref.read(scoreRepoProvider);
    final svc = ImportService(ref.read(dbProvider), scores);
    try {
      final result = await runWithProgress(context, '악보를 가져오는 중', () async {
        final imported = await runEach([for (final job in jobs) () => job(svc)]);
        await library.touch(imported.ids);
        return imported;
      });
      messenger.hideCurrentSnackBar();
      if (result.ids.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text('가져오기 실패: ${importErrorMessage(result.errors.first)}')),
        );
        return;
      }
      final summary = result.errors.isEmpty
          ? (result.ids.length == 1 ? '가져왔음' : '${result.ids.length}개 가져왔음')
          : '${result.ids.length}개 가져옴 · ${result.errors.length}개 실패: ${importErrorMessage(result.errors.first)}';
      messenger.showSnackBar(
        SnackBar(
          content: Text('$summary. 페이지별 마디수를 설정해야 제때 넘어감'),
          duration: const Duration(seconds: 6),
          // 액션이 있으면 Flutter 3.47은 duration을 무시하고 남음. 리더 재생줄을 덮으므로 닫히게 함
          persist: false,
          action: SnackBarAction(
            label: '설정',
            onPressed: () async {
              final node = await library.node(result.ids.first);
              if (node != null) await _pushScoreSettings(navigator, scores, node);
            },
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(importErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _importStartedAt = null);
    }
  }

  /// PDF 파일을 골라 들임. 여러 개를 고르면 각각 별도 악보가 됨. 끝나면 선택기 사본을 지움.
  Future<void> _importPdf() async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
    } catch (e) {
      _showImportError(e);
      return;
    }
    final paths = [
      for (final f in picked)
        if (f.path != null) f.path!,
    ];
    if (paths.isEmpty || !mounted) return;
    try {
      await _runImport([
        for (final path in paths) (svc) => svc.importPdf(File(path), parentId: widget.folderId),
      ]);
    } finally {
      await discardImportSources(ImportSource.files, paths);
    }
  }

  /// 이미지 여러 장을 한 악보로 들임.
  Future<void> _importImages() async {
    final List<XFile> picked;
    try {
      picked = await ImagePicker().pickMultiImage();
    } catch (e) {
      _showImportError(e);
      return;
    }
    if (picked.isEmpty) return;
    await _importImageFiles(ImportSource.images, [for (final x in picked) x.path]);
  }

  /// 카메라 스캐너로 찍어 들임. 엣지 검출과 보정은 OS 스캐너가 처리함.
  /// 취소·실패해도 스캐너 저장소를 비움. Android 폴백 스캐너는 취소해도 찍은 원본을 남기고, 두면
  /// 다음 실행 때 끝내지 못한 가져오기로 물음.
  Future<void> _importScan() async {
    final List<String>? paths;
    try {
      paths = await scanPages();
    } catch (e) {
      await discardImportSources(ImportSource.scan, const []);
      _showImportError(e);
      return;
    }
    if (paths == null || paths.isEmpty) {
      await discardImportSources(ImportSource.scan, const []);
      return;
    }
    await _importImageFiles(ImportSource.scan, paths);
  }

  /// 사진·스캔 결과에 이름을 받아 한 악보로 들임. 취소·성공·실패 모두 원천 사본을 지움.
  Future<void> _importImageFiles(ImportSource source, List<String> paths) async {
    try {
      final name = await _askImportName(source);
      if (name != null) await _importNamed(paths, name);
    } finally {
      await discardImportSources(source, paths);
    }
  }

  /// 가져올 악보 이름을 물음. 닫거나 비워 두거나 그사이 화면이 닫히면 null.
  Future<String?> _askImportName(ImportSource source) async {
    if (!mounted) return null;
    final initial = source == ImportSource.scan ? '스캔한 악보' : '새 악보';
    final name = (await _askText('악보 이름', '이름', initial: initial))?.trim();
    return name == null || name.isEmpty || !mounted ? null : name;
  }

  /// 이미지 여러 장을 받은 이름의 한 악보로 들임. 원천 사본은 호출자가 지움.
  Future<void> _importNamed(List<String> paths, String name) => _runImport([
    (svc) =>
        svc.importImages([for (final p in paths) File(p)], name: name, parentId: widget.folderId),
  ]);

  /// Android에서 스캐너·사진 선택기를 연 사이 Activity가 죽어 버려진 결과를 되찾아 이어서 들임.
  /// 먼저 시작한 가져오기가 끝난 뒤에 묻고, '버리기'를 고르거나 가져오기를 돌려야 끝남. 이름 입력을
  /// 닫으면 다시 물음. 미뤄 둘 수 없음. 사진은 이미 플러그인 기록이 지워졌고, 스캔은 다음 스캔이
  /// 끝나며 스캐너 저장소를 통째로 비울 때 함께 지워짐. 답하기 전에 화면이 닫히면 사본을 남김.
  Future<void> _recoverLostImport() async {
    final lost = await ref.read(findLostImportProvider)();
    if (lost == null) return;
    // 도는 중에 _runImport를 부르면 조용히 떨궈지고 되찾은 사본만 지워짐
    while (_importing) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
    }
    final what = lost.source == ImportSource.scan
        ? '스캔한 ${lost.paths.length}쪽'
        : '고른 사진 ${lost.paths.length}장';
    while (true) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        // 뒤로가기로 닫히면 답 없이 버려짐. 잘못 눌러 잃지 않게 막음
        builder: (c) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('끝내지 못한 가져오기'),
            content: Text('앱이 닫히는 사이 $what이 남아 있음. 악보로 가져올 수 있음.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('버리기')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('가져오기')),
            ],
          ),
        ),
      );
      if (ok != true) {
        await discardImportSources(lost.source, lost.paths);
        return;
      }
      // 이름 입력은 창 밖 탭·뒤로가기로 닫힘. 닫혔다고 버리지 않고 처음 물음으로 돌아감
      final name = await _askImportName(lost.source);
      if (name == null) continue;
      try {
        await _importNamed(lost.paths, name);
      } finally {
        await discardImportSources(lost.source, lost.paths);
      }
      return;
    }
  }

  /// 선택기·스캐너가 던진 오류를 할 수 있는 행동과 함께 알림.
  void _showImportError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(importErrorMessage(e))));
  }

  /// 선택 모드를 켜고 끔.
  void _toggleSelection(int id) => setState(() {
    _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
  });

  /// 상단바·목록 격자·추가 버튼. 목록은 DB 감시 결과를 그대로 그림.
  @override
  Widget build(BuildContext context) {
    final selecting = _selectionMode || _selected.isNotEmpty;
    return Scaffold(
      appBar: selecting ? _selectionBar() : _normalBar(),
      // 선택·검색 중 뒤로가기는 화면을 닫지 않고 그 모드만 끝냄. 숨은 탭일 때는 끼어들지 않음
      body: PopScope(
        canPop: !(widget.active && (selecting || _searching)),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && widget.active) _exitModes();
        },
        child: SafeArea(
          top: false,
          child: StreamBuilder<List<Node>>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) return _loadFailed('${snap.error}');
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snap.data!;
              if (items.isEmpty) return _emptyState();
              return _grid(items);
            },
          ),
        ),
      ),
      floatingActionButton: selecting
          ? null
          : FloatingActionButton.extended(
              onPressed: _importing ? null : _showImportSheet,
              icon: const Icon(Icons.add),
              label: const Text('악보 추가'),
            ),
    );
  }

  /// 평소 상단바. 검색은 아이콘으로 두고 누를 때만 펼쳐 목록 공간을 지킴.
  PreferredSizeWidget _normalBar() => AppBar(
    title: _searching
        ? TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(hintText: '악보·폴더 검색', border: InputBorder.none),
            onChanged: (v) => setState(() {
              _query = v;
              _stream = _watch();
            }),
          )
        : Text(widget.title ?? '악보'),
    actions: [
      // 삭제·이름변경·옮기기가 롱프레스에만 있으면 있는 줄을 모름
      IconButton(
        tooltip: '선택',
        icon: const Icon(Icons.checklist),
        onPressed: () => setState(() => _selectionMode = true),
      ),
      IconButton(
        tooltip: _searching ? '검색 닫기' : '검색',
        icon: Icon(_searching ? Icons.close : Icons.search),
        onPressed: () => setState(() {
          _searching = !_searching;
          if (!_searching) {
            _searchController.clear();
            _query = '';
            _stream = _watch();
          }
        }),
      ),
    ],
  );

  /// 선택 모드 상단바.
  PreferredSizeWidget _selectionBar() => AppBar(
    leading: IconButton(
      tooltip: '선택 해제',
      icon: const Icon(Icons.close),
      onPressed: () => setState(() {
        _selected.clear();
        _selectionMode = false;
      }),
    ),
    title: Text(_selected.isEmpty ? '항목을 고름' : '${_selected.length}개 선택'),
    actions: [
      if (_selected.length == 1)
        IconButton(
          tooltip: '이름 변경',
          icon: const Icon(Icons.drive_file_rename_outline),
          onPressed: () async {
            final node = await _repo.node(_selected.first);
            if (node != null) await _rename(node);
          },
        ),
      IconButton(
        tooltip: '옮기기',
        icon: const Icon(Icons.drive_file_move_outlined),
        onPressed: _selected.isEmpty ? null : _move,
      ),
      IconButton(
        tooltip: '휴지통으로',
        icon: const Icon(Icons.delete_outline),
        onPressed: _selected.isEmpty ? null : _trash,
      ),
    ],
  );

  /// 목록을 읽지 못했을 때. 스피너를 영원히 돌리면 앱이 멈춘 것으로 보임.
  Widget _loadFailed(String message) => EmptyState(
    icon: Icons.error_outline,
    title: '목록을 읽지 못함',
    message: message,
    action: FilledButton(onPressed: _reload, child: const Text('다시 시도')),
  );

  /// 검색 결과가 없을 때와 폴더가 빌 때를 구분해 다음 행동을 안내함.
  Widget _emptyState() => _query.isNotEmpty
      ? EmptyState(icon: Icons.search_off, title: '검색 결과 없음', message: '"$_query"와 맞는 악보나 폴더가 없음')
      : EmptyState(
          icon: Icons.library_music_outlined,
          title: widget.folderId == null ? '아직 악보가 없음' : '빈 폴더',
          message: 'PDF나 사진을 가져오거나 카메라로 바로 스캔할 수 있음',
          action: FilledButton.icon(
            onPressed: _showImportSheet,
            icon: const Icon(Icons.add),
            label: const Text('악보 추가'),
          ),
        );

  /// 화면 폭에 맞춰 열 수를 늘림. 태블릿 가로에서 한 화면에 더 많이 보이게 함.
  Widget _grid(List<Node> items) {
    final selecting = _selectionMode || _selected.isNotEmpty;
    final width = MediaQuery.sizeOf(context).width;
    final columns = (width / 190).floor().clamp(2, 6);
    final indexOf = {for (var i = 0; i < items.length; i++) items[i].id: i};
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(kGapM, kGapM, kGapM, 96),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: kGapM,
        mainAxisSpacing: kGapM,
        childAspectRatio: 0.72,
      ),
      itemCount: items.length,
      // 칸이 빠지거나 끼어도 뒤쪽 칸의 상태(표지)를 새로 만들지 않고 새 자리로 옮기게 함
      findChildIndexCallback: (key) => indexOf[(key as ValueKey<int>).value],
      itemBuilder: (_, i) {
        final n = items[i];
        // 목록이 바뀌어도 칸의 상태(썸네일)가 다른 노드로 넘어가지 않게 노드에 묶음
        return ScoreTile(
          key: ValueKey(n.id),
          node: n,
          selected: _selected.contains(n.id),
          selectionMode: selecting,
          onTap: () => selecting ? _toggleSelection(n.id) : _open(n),
          onLongPress: () => setState(() {
            _selectionMode = true;
            _selected.add(n.id);
          }),
          onSettings: n.kind == NodeKind.score ? () => _openSettings(n) : null,
          importStartedAt: _importStartedAt,
        );
      },
    );
  }
}

/// 작업을 차례로 돌려 만든 id와 실패를 모음. 하나가 실패해도 나머지는 계속함.
/// 여러 PDF 중 하나가 깨졌다고 뒤 파일을 버리면, 다시 고를 때 앞 파일이 두 벌 들어옴.
@visibleForTesting
Future<({List<int> ids, List<Object> errors})> runEach(List<Future<int> Function()> jobs) async {
  final ids = <int>[];
  final errors = <Object>[];
  for (final job in jobs) {
    try {
      ids.add(await job());
    } catch (e) {
      errors.add(e);
    }
  }
  return (ids: ids, errors: errors);
}

/// 악보의 재생 설정 화면을 엶. 가져오기 알림처럼 목록 화면이 사라진 뒤에도 불리므로
/// context·ref 대신 넘겨받은 navigator와 저장소만 씀.
Future<void> _pushScoreSettings(NavigatorState navigator, ScoreRepo scores, Node node) async {
  final score = await scores.score(node.id);
  if (score == null || !navigator.mounted) return;
  await navigator.push(
    MaterialPageRoute(
      builder: (_) => ScoreSettingsPage(
        scoreId: node.id,
        pdfPath: AppPaths.abs(score.fileRel),
        title: node.name,
      ),
    ),
  );
}

/// 이동 대상. 루트를 고른 경우를 null과 구분하려고 감쌈.
class _MoveTarget {
  const _MoveTarget(this.folderId);

  final int? folderId;
}

/// 폴더만 훑어 이동 대상을 고르는 다이얼로그. 루트부터 한 단계씩 내려감.
class _FolderPickerDialog extends ConsumerStatefulWidget {
  const _FolderPickerDialog();

  @override
  ConsumerState<_FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends ConsumerState<_FolderPickerDialog> {
  final _stack = <Node>[];

  /// 현재 보고 있는 폴더. 비었으면 루트.
  int? get _current => _stack.isEmpty ? null : _stack.last.id;

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(libraryRepoProvider);
    return AlertDialog(
      title: Text(_stack.isEmpty ? '루트' : _stack.map((n) => n.name).join(' / ')),
      content: SizedBox(
        width: 320,
        height: 360,
        child: FutureBuilder<List<Node>>(
          future: repo.children(_current),
          builder: (_, snap) {
            if (snap.hasError) return Center(child: Text('폴더를 읽지 못함: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final folders = snap.data!.where((n) => n.kind == NodeKind.folder).toList();
            return ListView(
              children: [
                if (_stack.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.arrow_upward),
                    title: const Text('상위로'),
                    onTap: () => setState(_stack.removeLast),
                  ),
                for (final f in folders)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(f.name),
                    onTap: () => setState(() => _stack.add(f)),
                  ),
                if (folders.isEmpty && _stack.isEmpty) const ListTile(title: Text('하위 폴더 없음')),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _MoveTarget(_current)),
          child: Text(_stack.isEmpty ? '루트로 이동' : '여기로 이동'),
        ),
      ],
    );
  }
}
