import 'dart:convert';
import 'package:flutter/material.dart';

import '../../core/storage/token_storage.dart';
import '../members/project_members_api.dart';

import 'comment.dart';
import 'comments_api.dart';

class CommentsScreen extends StatefulWidget {
  final String projectId;
  final String taskId;
  final String taskTitle;
  final CommentsApi commentsApi;

  // теперь ВСЕГДА передаём — чтобы работало "по-настоящему"
  final TokenStorage tokenStorage;
  final ProjectMembersApi projectMembersApi;

  const CommentsScreen({
    super.key,
    required this.projectId,
    required this.taskId,
    required this.taskTitle,
    required this.commentsApi,
    required this.tokenStorage,
    required this.projectMembersApi,
  });

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  bool _loading = true;
  bool _sending = false;
  Object? _error;

  List<Comment> _items = [];

  String? _myUserId;
  bool _iAmOwner = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _initRole();
    await _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initRole() async {
    try {
      final token = await widget.tokenStorage.readToken();
      _myUserId = _tryReadSubFromJwt(token);
      if (_myUserId == null) return;

      final members = await widget.projectMembersApi.list(widget.projectId);
      final me = members.where((m) => m.userId == _myUserId).toList();
      final owner = me.isNotEmpty && me.first.role == 'OWNER';

      if (mounted) setState(() => _iAmOwner = owner);
    } catch (_) {
      // если не удалось — просто считаем что не OWNER
    }
  }

  String? _tryReadSubFromJwt(String? token) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length < 2) return null;

    try {
      final payload = parts[1];
      final norm = base64.normalize(payload);
      final jsonStr = utf8.decode(base64Url.decode(norm));
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return map['sub']?.toString();
    } catch (_) {
      return null;
    }
  }

  bool _canDelete(Comment c) {
    final isMine = _myUserId != null && c.authorId == _myUserId;
    return isMine || _iAmOwner;
  }

  String _fmt(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.commentsApi.list(
        projectId: widget.projectId,
        taskId: widget.taskId,
      );

      if (!mounted) return;
      setState(() {
        _items = res;
        _loading = false;
      });

      _jumpToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async => _load();

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      final created = await widget.commentsApi.create(
        projectId: widget.projectId,
        taskId: widget.taskId,
        text: text,
      );

      _ctrl.clear();

      if (!mounted) return;
      setState(() => _items = [..._items, created]);

      _jumpToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(Comment c) async {
    if (!_canDelete(c)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Удалять можно только свои комментарии (или OWNER).')),
      );
      return;
    }

    try {
      await widget.commentsApi.delete(
        projectId: widget.projectId,
        taskId: widget.taskId,
        commentId: c.id,
      );

      if (!mounted) return;
      setState(() {
        _items = _items.where((x) => x.id != c.id).toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Комментарии: ${widget.taskTitle}${_iAmOwner ? ' • OWNER' : ''}'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: Builder(
                builder: (_) {
                  if (_loading) return const Center(child: CircularProgressIndicator());

                  if (_error != null) {
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const SizedBox(height: 80),
                        Text('Ошибка:\n$_error', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        Center(
                          child: FilledButton(
                            onPressed: _load,
                            child: const Text('Повторить'),
                          ),
                        ),
                      ],
                    );
                  }

                  if (_items.isEmpty) {
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: const [
                        SizedBox(height: 80),
                        Center(
                          child: Text(
                            'Пока нет комментариев.\nНапиши первый 🙂',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    );
                  }

                  return ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final c = _items[i];
                      final canDel = _canDelete(c);

                      return ListTile(
                        title: Text(c.text),
                        subtitle: Text(_fmt(c.createdAt)),
                        trailing: IconButton(
                          tooltip: canDel ? 'Удалить' : 'Удалить можно только свой',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: canDel ? () => _delete(c) : null,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: const InputDecoration(
                      hintText: 'Комментарий...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sending ? null : _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('Отправить'),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
