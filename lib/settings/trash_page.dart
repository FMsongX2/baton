// 휴지통. 삭제는 곧바로 파일을 지우지 않으므로 여기서 되살리거나 완전히 지움.
// 보관 기간이 지난 항목은 앱을 열 때 자동으로 사라지고, 여기서 먼저 지울 수도 있음.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/database.dart';
import '../core/db/tables.dart';
import '../core/providers.dart';
import '../library/library_repo.dart';
import '../theme.dart';

class TrashPage extends ConsumerStatefulWidget {
  const TrashPage({super.key});

  @override
  ConsumerState<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends ConsumerState<TrashPage> {
  late Future<List<Node>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = ref.read(libraryRepoProvider).trash();
  }

  /// 목록을 다시 읽음.
  void _reload() => setState(() => _future = ref.read(libraryRepoProvider).trash());

  /// 남은 보관 일수. 0 이하면 다음에 앱을 열 때 사라짐.
  int _daysLeft(DateTime deletedAt) =>
      kTrashRetention.inDays - DateTime.now().difference(deletedAt).inDays;

  /// 지우기 전에 한 번 묻는다. 되돌릴 수 없는 동작이라 대상 수를 함께 보여 줌.
  Future<bool> _confirm(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
              foregroundColor: Theme.of(c).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('영구 삭제'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// 고른 항목을 파일까지 완전히 지움.
  Future<void> _purge(List<int> ids, String message) async {
    if (_busy || ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!await _confirm('영구 삭제', message) || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(libraryRepoProvider).purge(ids);
      if (mounted) _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('휴지통')),
    body: SafeArea(
      top: false,
      child: ContentWidth(
        child: FutureBuilder<List<Node>>(
          future: _future,
          builder: (_, snap) {
            if (snap.hasError) {
              return EmptyState(
                icon: Icons.error_outline,
                title: '휴지통을 읽지 못함',
                message: '${snap.error}',
                action: FilledButton(onPressed: _reload, child: const Text('다시 시도')),
              );
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final items = snap.data!;
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.delete_outline,
                title: '휴지통이 비어 있음',
                message: '지운 악보는 ${kTrashRetention.inDays}일 동안 여기 남았다가 자동으로 사라짐',
              );
            }
            return ListView.builder(
              itemCount: items.length + 1,
              itemBuilder: (_, i) {
                if (i == items.length) return _emptyAllTile(items);
                return _tile(items[i]);
              },
            );
          },
        ),
      ),
    ),
  );

  /// 항목 한 줄. 되살리기와 영구 삭제를 함께 둠.
  Widget _tile(Node n) {
    final left = n.deletedAt == null ? kTrashRetention.inDays : _daysLeft(n.deletedAt!);
    return ListTile(
      leading: Icon(
        n.kind == NodeKind.folder ? Icons.folder_outlined : Icons.library_music_outlined,
      ),
      title: Text(n.name),
      subtitle: Text(left <= 0 ? '곧 사라짐' : '$left일 뒤 사라짐'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await ref.read(libraryRepoProvider).restore([n.id]);
                    if (mounted) _reload();
                  },
            child: const Text('되살리기'),
          ),
          IconButton(
            tooltip: '영구 삭제',
            icon: const Icon(Icons.delete_forever_outlined),
            onPressed: _busy ? null : () => _purge([n.id], '"${n.name}"을(를) 파일까지 지움. 되돌릴 수 없음.'),
          ),
        ],
      ),
    );
  }

  /// 휴지통 전체를 비우는 줄. 목록 끝에 둬서 실수로 먼저 누르지 않게 함.
  Widget _emptyAllTile(List<Node> items) => Padding(
    padding: const EdgeInsets.fromLTRB(kGapL, kGapXl, kGapL, kGapXl),
    child: OutlinedButton.icon(
      onPressed: _busy
          ? null
          : () => _purge([for (final n in items) n.id], '${items.length}개 항목을 파일까지 지움. 되돌릴 수 없음.'),
      icon: const Icon(Icons.delete_forever_outlined),
      label: const Text('휴지통 비우기'),
      style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
    ),
  );
}
