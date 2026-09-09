// 라이브러리 화면. 악보는 이름보다 생김새로 알아보므로 썸네일 격자를 기본으로 둠.
// 데이터 변경은 전부 LibraryRepo를 거치고 여기서는 화면 상태만 들고 있음.

import 'dart:async';
import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/db/database.dart';
import '../core/db/tables.dart';
import '../core/providers.dart';
import '../core/storage/paths.dart';
import '../reader/reader_page.dart';
import '../score/import/import_service.dart';
import '../score/score_settings_page.dart';
import '../theme.dart';
import 'library_repo.dart';
import 'score_tile.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, this.folderId, this.title});

  /// null이면 루트.
  final int? folderId;
  final String? title;

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

  /// 임포트 진행 중. 끝나기 전에 또 누르면 같은 파일이 두 번 들어옴.
  bool _importing = false;
  late Future<List<Node>> _future;

  LibraryRepo get _repo => ref.read(libraryRepoProvider);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 검색어가 있으면 전체 검색, 없으면 현재 폴더의 자식을 읽음.
  Future<List<Node>> _load() =>
      _query.isEmpty ? _repo.children(widget.folderId) : _repo.search(_query);

  /// 목록을 다시 읽고 선택을 비움. 임포트 도중 화면을 떠났을 수 있어 살아 있을 때만 함.
  void _reload() {
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selectionMode = false;
      _future = _load();
    });
  }

  /// 새 폴더 이름을 받아 만듦.
  Future<void> _createFolder() async {
    final name = await _askText('새 폴더', '폴더 이름');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.createFolder(name.trim(), parentId: widget.folderId);
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
      await _repo.rename(node.id, name.trim());
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
    try {
      await _repo.moveToTrash(ids);
      _reload();
      messenger.showSnackBar(
        SnackBar(
          content: Text('${ids.length}개를 휴지통으로 보냄'),
          action: SnackBarAction(
            label: '되돌리기',
            onPressed: () async {
              await _repo.restore(ids);
              _reload();
            },
          ),
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
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LibraryPage(folderId: node.id, title: node.name),
        ),
      );
      _reload();
      return;
    }
    final score = await ref.read(scoreRepoProvider).score(node.id);
    if (score == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReaderPage(scoreId: node.id, pdfPath: AppPaths.abs(score.fileRel), title: node.name),
      ),
    );
    _reload();
  }

  /// 악보의 재생 설정 화면을 연다.
  Future<void> _openSettings(Node node) async {
    final score = await ref.read(scoreRepoProvider).score(node.id);
    if (score == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScoreSettingsPage(
          scoreId: node.id,
          pdfPath: AppPaths.abs(score.fileRel),
          title: node.name,
        ),
      ),
    );
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

  /// 임포트를 돌리며 진행 표시를 띄우고 실패 사유를 알려 줌.
  /// 임포트를 돌리며 진행 표시를 띄우고 실패 사유를 알려 줌.
  /// 끝나기 전에 또 누르면 같은 파일이 두 번 들어오므로 잠금.
  /// 임포트 직후는 마디수가 기본값이라 그대로 재생하면 쪽당 8초로 넘어감. 다음 행동을 붙임.
  Future<void> _runImport(Future<void> Function(ImportService svc) job) async {
    if (_importing) return;
    setState(() => _importing = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: kGapL),
              Expanded(child: Text('악보를 가져오는 중')),
            ],
          ),
        ),
      ),
    );
    try {
      await job(ImportService(ref.read(dbProvider), ref.read(scoreRepoProvider)));
      navigator.pop();
      _reload();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('가져왔음. 페이지별 마디수를 설정해야 제때 넘어감'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: '설정', onPressed: _openLatestSettings),
        ),
      );
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('가져오기 실패: $e')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 방금 들인 악보의 재생 설정을 엶. 목록에서 가장 최근에 만들어진 악보를 고름.
  Future<void> _openLatestSettings() async {
    final items = await _load();
    final scores = items.where((n) => n.kind == NodeKind.score).toList();
    if (scores.isEmpty || !mounted) return;
    scores.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _openSettings(scores.first);
  }

  /// PDF 파일을 골라 들임. 여러 개를 고르면 각각 별도 악보가 됨.
  Future<void> _importPdf() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final paths = [
      for (final f in picked)
        if (f.path != null) f.path!,
    ];
    if (paths.isEmpty || !mounted) return;
    await _runImport((svc) async {
      for (final path in paths) {
        await svc.importPdf(File(path), parentId: widget.folderId);
      }
    });
  }

  /// 이미지 여러 장을 한 악보로 들임.
  Future<void> _importImages() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty || !mounted) return;
    final name = await _askText('악보 이름', '이름', initial: '새 악보');
    if (name == null || name.trim().isEmpty) return;
    await _runImport(
      (svc) => svc.importImages(
        [for (final x in picked) File(x.path)],
        name: name.trim(),
        parentId: widget.folderId,
      ),
    );
  }

  /// 카메라 스캐너로 찍어 들임. 엣지 검출과 보정은 OS 스캐너가 처리함.
  Future<void> _importScan() async {
    final paths = await CunningDocumentScanner.getPictures();
    if (paths == null || paths.isEmpty || !mounted) return;
    final name = await _askText('악보 이름', '이름', initial: '스캔한 악보');
    if (name == null || name.trim().isEmpty) return;
    await _runImport(
      (svc) => svc.importImages(
        [for (final p in paths) File(p)],
        name: name.trim(),
        parentId: widget.folderId,
      ),
    );
  }

  /// 선택 모드를 켜고 끔.
  void _toggleSelection(int id) => setState(() {
    _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
  });

  @override
  Widget build(BuildContext context) {
    final selecting = _selectionMode || _selected.isNotEmpty;
    return Scaffold(
      appBar: selecting ? _selectionBar() : _normalBar(),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<Node>>(
          future: _future,
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
              _future = _load();
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
            _future = _load();
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
            final list = await _future;
            final node = list.firstWhere((n) => n.id == _selected.first);
            await _rename(node);
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
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(kGapM, kGapM, kGapM, 96),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: kGapM,
        mainAxisSpacing: kGapM,
        childAspectRatio: 0.72,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final n = items[i];
        return ScoreTile(
          node: n,
          selected: _selected.contains(n.id),
          selectionMode: selecting,
          onTap: () => selecting ? _toggleSelection(n.id) : _open(n),
          onLongPress: () => setState(() {
            _selectionMode = true;
            _selected.add(n.id);
          }),
          onSettings: n.kind == NodeKind.score ? () => _openSettings(n) : null,
        );
      },
    );
  }
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
