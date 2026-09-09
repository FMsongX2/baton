// 라이브러리 격자의 한 칸. 악보는 첫 페이지 썸네일로, 폴더는 아이콘으로 보여 줌.
// 썸네일이 아직 없는 예전 악보는 이 자리에서 만들어 캐시함.

import 'dart:io';

import 'package:flutter/material.dart';

import '../core/db/database.dart';
import '../core/db/tables.dart';
import '../core/storage/paths.dart';
import '../score/thumbnail.dart';
import '../theme.dart';

class ScoreTile extends StatefulWidget {
  const ScoreTile({
    super.key,
    required this.node,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    this.onSettings,
  });

  final Node node;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onSettings;

  @override
  State<ScoreTile> createState() => _ScoreTileState();
}

class _ScoreTileState extends State<ScoreTile> {
  File? _thumb;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    if (widget.node.kind == NodeKind.score) _resolveThumb();
  }

  /// 캐시된 썸네일을 찾고, 없으면 한 번 만들어 봄. 실패하면 대체 그림으로 둠.
  Future<void> _resolveThumb() async {
    final file = File(AppPaths.abs(AppPaths.thumbnail(widget.node.id)));
    if (await file.exists()) {
      if (mounted) setState(() => _thumb = file);
      return;
    }
    final pdf = File(AppPaths.abs(AppPaths.sourcePdf(widget.node.id)));
    if (await pdf.exists()) {
      final ok = await generateThumbnail(pdf.path, file.path);
      if (ok && mounted) {
        setState(() => _thumb = file);
        return;
      }
    }
    if (mounted) setState(() => _checked = true);
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
