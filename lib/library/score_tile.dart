// 라이브러리 격자의 한 칸. 악보는 첫 페이지 썸네일로, 폴더는 아이콘으로 보여 줌.
// 썸네일이 없는 악보는 이 자리에서 만들어 캐시하되 가져오는 중인 행은 기다림. updatedAt이 바뀌면 다시 찾음.

import 'dart:io';

import 'package:flutter/material.dart';

import '../core/db/database.dart';
import '../core/db/tables.dart';
import '../core/storage/paths.dart';
import '../score/thumbnail.dart';
import '../theme.dart';

class ScoreTile extends StatefulWidget {
  /// 격자 칸 하나. 가져오기를 돌리는 화면은 [importStartedAt]을 넘겨 그 사이 생긴 행의 표지를 기다리게 함.
  const ScoreTile({
    super.key,
    required this.node,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    this.onSettings,
    this.importStartedAt,
  });

  final Node node;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onSettings;

  /// 이 화면에서 도는 가져오기의 시작 시각. 그 초 이후에 생겨 아직 touch되지 않은 악보 행은
  /// 가져오기가 PDF를 옮기고 표지를 만드는 중이라 칸이 따로 만들지 않음.
  final DateTime? importStartedAt;

  @override
  State<ScoreTile> createState() => _ScoreTileState();
}

class _ScoreTileState extends State<ScoreTile> {
  File? _thumb;

  /// 보여 주는 썸네일 파일의 수정 시각. 같은 경로의 파일이 바뀌었는지 가리는 데 씀.
  DateTime? _thumbModified;
  bool _checked = false;

  /// 찾기를 시작할 때마다 올림. 늦게 끝난 앞선 찾기의 결과를 버리는 데 씀.
  int _resolving = 0;

  /// 악보 칸이면 썸네일을 찾기 시작함.
  @override
  void initState() {
    super.initState();
    if (widget.node.kind == NodeKind.score) _resolveThumb();
  }

  /// 칸이 다른 노드를 받으면 앞 노드의 썸네일을 버리고 새로 찾음. 안 그러면 이름과 표지가 어긋남.
  /// 같은 노드라도 updatedAt이 바뀌면 다시 찾음. 가져오기가 끝나 표지가 생겼거나 회전으로 바뀐 경우.
  /// 가져오기를 기다리던 칸(만드는 중)은 touch 없이 가져오기가 끝나도 다시 찾음. touch가 실패해도
  /// 만드는 중에 머물지 않게 함. 실패로 확정된 칸은 다시 찾지 않음. 찾으면 깨진 PDF를 가져오기마다 렌더함.
  @override
  void didUpdateWidget(ScoreTile old) {
    super.didUpdateWidget(old);
    final node = widget.node;
    final importEnded = old.importStartedAt != null && widget.importStartedAt == null;
    if (node.id != old.node.id || node.kind != old.node.kind) {
      _resolving++;
      _thumb = null;
      _thumbModified = null;
      _checked = false;
    } else if (node.updatedAt == old.node.updatedAt &&
        !(importEnded && _thumb == null && !_checked)) {
      return;
    }
    if (node.kind == NodeKind.score) _resolveThumb();
  }

  /// 캐시된 썸네일을 찾고, 없으면 한 번 만들어 봄. 실패하면 대체 그림으로 둠.
  /// 가져오는 중인 행은 만들지 않고 만드는 중으로 둠. 가져오기가 끝나 touch하면 다시 찾음.
  /// 찾는 사이 칸이 다른 노드로 바뀌었거나 더 새 찾기가 시작됐으면 결과를 버림.
  Future<void> _resolveThumb() async {
    final ticket = ++_resolving;
    bool current() => mounted && ticket == _resolving;
    final id = widget.node.id;
    final importing = _isImporting();
    final file = File(AppPaths.abs(AppPaths.thumbnail(id)));
    var modified = await _modifiedAt(file);
    if (modified == null && !importing) {
      final pdf = File(AppPaths.abs(AppPaths.sourcePdf(id)));
      if (await pdf.exists() && await generateThumbnail(pdf.path, file.path)) {
        modified = await _modifiedAt(file);
      }
    }
    if (!current()) return;
    if (modified == null) {
      setState(() {
        _thumb = null;
        _thumbModified = null;
        _checked = !importing;
      });
      return;
    }
    // 같은 경로라 캐시가 옛 그림을 돌려줌. 파일이 바뀐 경우에만 버려 스크롤마다 다시 읽지 않게 함
    if (_thumbModified != null && modified != _thumbModified) await FileImage(file).evict();
    if (!current()) return;
    setState(() {
      _thumb = file;
      _thumbModified = modified;
    });
  }

  /// 이 칸의 노드가 지금 가져오는 중인 행인지. 가져오기가 시작된 뒤 생겼고 touch 전이면 그렇게 봄.
  /// 생성 시각으로 거르므로 전에 들어와 표지가 빠진 악보는 가져오는 동안에도 칸이 만듦.
  bool _isImporting() {
    final since = widget.importStartedAt?.millisecondsSinceEpoch;
    final node = widget.node;
    if (since == null || node.updatedAt != node.createdAt) return false;
    // 생성 시각은 초 단위로 저장되므로 시작 시각을 초로 내려 비교함. 안 내리면 같은 초에 생긴 행을 놓침
    return node.createdAt.millisecondsSinceEpoch >= since - since % 1000;
  }

  /// 파일의 수정 시각. 없으면 null.
  static Future<DateTime?> _modifiedAt(File file) async {
    final stat = await file.stat();
    return stat.type == FileSystemEntityType.notFound ? null : stat.modified;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isFolder = widget.node.kind == NodeKind.folder;

    return Semantics(
      label: widget.node.name,
      selected: widget.selected,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: isFolder ? _folderFace(scheme) : _scoreFace(scheme),
                  ),
                  if (widget.selected)
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: scheme.primary.withValues(alpha: 0.28),
                        border: Border.all(color: scheme.primary, width: 2.5),
                      ),
                      alignment: Alignment.topRight,
                      padding: const EdgeInsets.all(kGapS),
                      child: Icon(Icons.check_circle, color: scheme.primary, size: 26),
                    ),
                  if (!widget.selectionMode && widget.onSettings != null)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Material(
                        color: scheme.surface.withValues(alpha: 0.9),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: widget.onSettings,
                          // 보이는 원은 그대로 두고 누를 수 있는 면만 48로 넓힘.
                          // 바로 옆이 악보 열기 영역이라 작으면 오탭이 양방향으로 남
                          // 최소 터치 타깃 48. 바로 옆이 악보 열기 영역이라
                          // 작으면 오탭이 양방향으로 남
                          child: Tooltip(
                            message: '재생 설정',
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(Icons.tune, size: 18, color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: kGapS),
            Text(
              widget.node.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }

  /// 폴더 칸. 악보 썸네일과 한눈에 구분되도록 채운 면으로 둠.
  Widget _folderFace(ColorScheme scheme) => ColoredBox(
    color: scheme.surfaceContainerHighest,
    child: Center(child: Icon(Icons.folder_rounded, size: 52, color: scheme.primary)),
  );

  /// 악보 칸. 썸네일이 준비되기 전과 실패한 경우를 나눠서 보여 줌.
  Widget _scoreFace(ColorScheme scheme) {
    final thumb = _thumb;
    if (thumb != null) {
      return Image.file(
        thumb,
        // 파일이 바뀌면 새로 읽도록 그림 상태를 새로 만듦. 같은 FileImage면 이미 받은 그림을 계속 씀
        key: ValueKey(_thumbModified),
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        errorBuilder: (_, _, _) => _placeholder(scheme, failed: true),
      );
    }
    return _placeholder(scheme, failed: _checked);
  }

  /// 썸네일 자리를 대신 채움. 만드는 중과 실패를 구분해 표시함.
  Widget _placeholder(ColorScheme scheme, {required bool failed}) => ColoredBox(
    color: scheme.surfaceContainerHighest,
    child: Center(
      child: failed
          ? Icon(Icons.description_outlined, size: 44, color: scheme.outline)
          : SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: scheme.outline),
            ),
    ),
  );
}
