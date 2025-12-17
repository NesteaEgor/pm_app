import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../../core/storage/token_storage.dart';
import 'chat_api.dart';
import 'chat_message.dart';
import 'chat_read.dart';

// imports
import '../members/project_members_api.dart';
import '../members/project_members_screen.dart';

class _PendingSend {
  final String clientMessageId;
  final String text;

  int attempts = 0;
  DateTime lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  _PendingSend({
    required this.clientMessageId,
    required this.text,
  });
}

class ProjectChatScreen extends StatefulWidget {
  final String projectId;
  final String projectName;
  final ChatApi chatApi;
  final TokenStorage tokenStorage;

  // widget field
  final ProjectMembersApi projectMembersApi;

  const ProjectChatScreen({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.chatApi,
    required this.tokenStorage,
    required this.projectMembersApi,
  });

  @override
  State<ProjectChatScreen> createState() => _ProjectChatScreenState();
}

class _ProjectChatScreenState extends State<ProjectChatScreen> {
  final _items = <ChatMessage>[];
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  bool _loading = true;
  bool _sending = false;
  bool _loadingMore = false;
  Object? _error;

  StompClient? _stomp;
  bool _wsConnected = false;

  // pending-index for replacing optimistic messages
  final Map<String, int> _pendingIndexByClientId = {};

  // outbox for retries
  final Map<String, _PendingSend> _outbox = {};
  Timer? _retryTimer;

  String? _myUserId;

  // read receipts: userId -> lastReadMessageAt (time of message that user read up to)
  final Map<String, DateTime> _lastReadMessageAtByUser = {};

  // throttling read-send
  String? _lastReadSentMessageId;
  DateTime _lastReadSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _init();
    _scroll.addListener(_onScroll);

    // retry loop
    _retryTimer = Timer.periodic(const Duration(seconds: 2), (_) => _flushOutbox());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    _stomp?.deactivate();
    super.dispose();
  }

  void _openMembers() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectMembersScreen(
          projectId: widget.projectId,
          projectName: widget.projectName,
          api: widget.projectMembersApi,
          tokenStorage: widget.tokenStorage,
        ),
      ),
    );
  }

  void _onScroll() {
    // пагинация назад
    if (_scroll.position.pixels <= 80 && !_loadingMore && _items.isNotEmpty) {
      _loadMore();
    }

    // если юзер у низа — отметим прочтение
    _maybeSendRead();
  }

  Future<void> _init() async {
    final token = await widget.tokenStorage.readToken();
    _myUserId = _tryReadSubFromJwt(token);

    await _loadInitial();
    await _loadReadsInitial(); // 👈 new
    await _connectWs();

    // если уже внизу — отправим read
    _maybeSendRead(force: true);
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

  String _newClientMessageId() {
    final r = Random();
    String hex(int n) => n.toRadixString(16).padLeft(2, '0');
    final bytes = List.generate(16, (_) => r.nextInt(256));
    return '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}-'
        '${hex(bytes[4])}${hex(bytes[5])}-'
        '${hex(bytes[6])}${hex(bytes[7])}-'
        '${hex(bytes[8])}${hex(bytes[9])}-'
        '${hex(bytes[10])}${hex(bytes[11])}${hex(bytes[12])}${hex(bytes[13])}${hex(bytes[14])}${hex(bytes[15])}';
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await widget.chatApi.history(projectId: widget.projectId, limit: 30);
      if (!mounted) return;

      setState(() {
        _items
          ..clear()
          ..addAll(list);
        _loading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
        _maybeSendRead(force: true);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _loadReadsInitial() async {
    try {
      final reads = await widget.chatApi.reads(projectId: widget.projectId);
      if (!mounted) return;

      setState(() {
        _lastReadMessageAtByUser.clear();
        for (final r in reads) {
          if (r.userId == _myUserId) continue; // нам не надо считать себя
          final at = r.lastReadMessageAt;
          if (at != null) _lastReadMessageAtByUser[r.userId] = at.toLocal();
        }
      });
    } catch (_) {
      // не критично
    }
  }

  Future<void> _loadMore() async {
    if (_items.isEmpty) return;

    setState(() => _loadingMore = true);
    try {
      final before = _items.first.createdAt;
      final older = await widget.chatApi.history(
        projectId: widget.projectId,
        before: before,
        limit: 30,
      );

      if (!mounted) return;

      if (older.isNotEmpty) {
        final prevOffset = _scroll.position.pixels;
        setState(() {
          _items.insertAll(0, older);
          _rebuildPendingIndex();
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(prevOffset + 200);
          }
        });
      }
    } catch (_) {
      // тихо
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _rebuildPendingIndex() {
    _pendingIndexByClientId.clear();
    for (var i = 0; i < _items.length; i++) {
      final m = _items[i];
      if (m.status == ChatSendStatus.sending && m.clientMessageId != null) {
        _pendingIndexByClientId[m.clientMessageId!] = i;
      }
    }
  }

  Future<void> _connectWs() async {
    final token = await widget.tokenStorage.readToken();
    if (token == null || token.isEmpty) return;

    final wsUrl = 'ws://127.0.0.1:8080/ws';

    final client = StompClient(
      config: StompConfig(
        url: wsUrl,
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        onConnect: (frame) {
          _wsConnected = true;
          _onConnect(frame);
          _flushOutbox();
          _maybeSendRead(force: true);
        },
        onDisconnect: (_) {
          _wsConnected = false;
        },
        onWebSocketError: (dynamic err) {
          _wsConnected = false;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('WS error: $err')),
          );
        },
        onStompError: (StompFrame f) {
          _wsConnected = false;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('WS ошибка: ${f.body}')),
          );
        },
        reconnectDelay: const Duration(seconds: 2),
      ),
    );

    setState(() => _stomp = client);
    client.activate();
  }

  void _onConnect(StompFrame frame) {
    final msgTopic = '/topic/projects/${widget.projectId}/messages';
    final readTopic = '/topic/projects/${widget.projectId}/reads';

    // 1) сообщения
    _stomp?.subscribe(
      destination: msgTopic,
      callback: (StompFrame f) {
        if (f.body == null) return;

        final jsonMap = jsonDecode(f.body!) as Map<String, dynamic>;
        final msg = ChatMessage.fromJson(jsonMap);

        if (!mounted) return;

        final type = jsonMap['eventType']?.toString(); // CREATED / UPDATED / DELETED
        final cid = jsonMap['clientMessageId']?.toString();

        // ACK created по clientMessageId — подтверждаем pending
        if ((type == null || type == 'CREATED') &&
            cid != null &&
            _pendingIndexByClientId.containsKey(cid)) {
          final idx = _pendingIndexByClientId[cid]!;
          setState(() {
            _items[idx] = _items[idx].copyWith(
              id: msg.id,
              createdAt: msg.createdAt,
              status: ChatSendStatus.sent,
              authorName: msg.authorName,
              text: msg.text,
              editedAt: msg.editedAt,
              deletedAt: msg.deletedAt,
            );
            _pendingIndexByClientId.remove(cid);
            _outbox.remove(cid);
          });

          _scrollToBottomSoft();
          _maybeSendRead(force: true);
          return;
        }

        // UPDATED / DELETED — обновляем по id
        if ((type == 'UPDATED' || type == 'DELETED') && msg.id != null) {
          final i = _items.indexWhere((x) => x.id == msg.id);
          if (i != -1) {
            setState(() {
              _items[i] = _items[i].copyWith(
                text: msg.text,
                editedAt: msg.editedAt,
                deletedAt: msg.deletedAt,
                authorName: msg.authorName,
              );
            });
          }
          return;
        }

        // иначе добавляем
        setState(() => _items.add(msg));
        _scrollToBottomSoft();
        _maybeSendRead(force: true);
      },
    );

    // 2) read receipts
    _stomp?.subscribe(
      destination: readTopic,
      callback: (StompFrame f) {
        if (f.body == null) return;

        final jsonMap = jsonDecode(f.body!) as Map<String, dynamic>;
        final r = ChatRead.fromJson(jsonMap);

        if (!mounted) return;
        if (r.userId == _myUserId) return;

        final at = r.lastReadMessageAt?.toLocal();
        if (at == null) return;

        setState(() {
          _lastReadMessageAtByUser[r.userId] = at;
        });
      },
    );
  }

  void _scrollToBottomSoft() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 140,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _enqueueAndTrySend(String text) {
    final clientId = _newClientMessageId();

    final pending = ChatMessage.pending(
      clientMessageId: clientId,
      projectId: widget.projectId,
      authorId: _myUserId ?? 'me',
      authorName: 'You',
      text: text,
    );

    setState(() {
      _items.add(pending);
      _pendingIndexByClientId[clientId] = _items.length - 1;
      _outbox[clientId] = _PendingSend(clientMessageId: clientId, text: text);
    });

    _scrollToBottomSoft();
    _flushOutbox();
  }

  void _flushOutbox() {
    if (!_wsConnected || _stomp == null) return;
    if (_outbox.isEmpty) return;

    final now = DateTime.now();

    for (final entry in _outbox.entries.toList()) {
      final cid = entry.key;
      final p = entry.value;

      final canTry = now.difference(p.lastAttempt) >= const Duration(seconds: 2);
      if (!canTry) continue;
      if (p.attempts >= 20) continue;

      try {
        p.attempts += 1;
        p.lastAttempt = now;

        _stomp!.send(
          destination: '/app/projects/${widget.projectId}/messages',
          body: jsonEncode({
            'text': p.text,
            'clientMessageId': cid,
          }),
        );
      } catch (_) {
        // попробуем позже
      }
    }
  }

  bool _isNearBottom() {
    if (!_scroll.hasClients) return false;
    final max = _scroll.position.maxScrollExtent;
    final cur = _scroll.position.pixels;
    return (max - cur) <= 120;
  }

  ChatMessage? _latestReadableMessage() {
    // последнее подтверждённое сообщение (с id), чтобы read было стабильным
    for (var i = _items.length - 1; i >= 0; i--) {
      final m = _items[i];
      if (m.id != null && m.status == ChatSendStatus.sent) return m;
    }
    return null;
  }

  void _maybeSendRead({bool force = false}) {
    if (!_wsConnected || _stomp == null) return;
    if (_items.isEmpty) return;

    if (!force && !_isNearBottom()) return;

    final last = _latestReadableMessage();
    if (last == null || last.id == null) return;

    final now = DateTime.now();
    if (!force) {
      // throttle: не чаще раза в секунду
      if (now.difference(_lastReadSentAt) < const Duration(seconds: 1)) return;
      // и не шлём одно и то же
      if (_lastReadSentMessageId == last.id) return;
    }

    _lastReadSentMessageId = last.id;
    _lastReadSentAt = now;

    try {
      _stomp!.send(
        destination: '/app/projects/${widget.projectId}/read',
        body: jsonEncode({'messageId': last.id}),
      );
    } catch (_) {
      // не критично
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      _enqueueAndTrySend(text);
      _ctrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _canManageMessage(ChatMessage m) {
    final isMine = _myUserId != null && m.authorId == _myUserId;
    if (!isMine) return false;
    if (m.status != ChatSendStatus.sent) return false;
    if (m.id == null) return false;
    if (m.isDeleted) return false;
    return true;
  }

  Future<void> _openMessageMenu(ChatMessage m) async {
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Редактировать'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || act == null) return;

    if (act == 'edit') {
      await _editMessage(m);
    } else if (act == 'delete') {
      await _deleteMessage(m);
    }
  }

  Future<void> _editMessage(ChatMessage m) async {
    if (m.id == null) return;

    final ctrl = TextEditingController(text: m.text);

    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Редактировать'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    final text = (newText ?? '').trim();
    if (text.isEmpty) return;

    // optimistic
    setState(() {
      final i = _items.indexWhere((x) => x.id == m.id);
      if (i != -1) {
        _items[i] = _items[i].copyWith(
          text: text,
          editedAt: DateTime.now(),
        );
      }
    });

    try {
      _stomp?.send(
        destination: '/app/projects/${widget.projectId}/messages/${m.id}/edit',
        body: jsonEncode({'text': text}),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не отредактировалось: $e')),
      );
    }
  }

  Future<void> _deleteMessage(ChatMessage m) async {
    if (m.id == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        content: const Text('Сообщение будет помечено как удалённое.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );

    if (!mounted || ok != true) return;

    // optimistic
    setState(() {
      final i = _items.indexWhere((x) => x.id == m.id);
      if (i != -1) {
        _items[i] = _items[i].copyWith(
          text: 'Сообщение удалено',
          deletedAt: DateTime.now(),
        );
      }
    });

    try {
      _stomp?.send(
        destination: '/app/projects/${widget.projectId}/messages/${m.id}/delete',
        body: jsonEncode({}),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалилось: $e')),
      );
    }
  }

  String _fmtTime(DateTime d) {
    final local = d.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  int _readCountForMessage(ChatMessage m) {
    // считаем прочитавших по времени последнего read-message у каждого юзера
    int c = 0;
    for (final entry in _lastReadMessageAtByUser.entries) {
      final at = entry.value;
      if (at.isAfter(m.createdAt) || at.isAtSameMomentAs(m.createdAt)) {
        c += 1;
      }
    }
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 80),
        Text('Ошибка:\n$_error', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(child: FilledButton(onPressed: _loadInitial, child: const Text('Повторить'))),
      ],
    )
        : ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (_loadingMore && i == 0) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final idx = _loadingMore ? i - 1 : i;
        final m = _items[idx];

        final isMine = _myUserId != null && m.authorId == _myUserId;
        final align = isMine ? Alignment.centerRight : Alignment.centerLeft;

        final statusText = m.status == ChatSendStatus.sending ? 'sending…' : '';
        final edited = m.editedAt != null && !m.isDeleted;
        final deleted = m.isDeleted;

        final canManage = _canManageMessage(m);

        final readCount = (isMine && !deleted && m.status == ChatSendStatus.sent) ? _readCountForMessage(m) : 0;
        final showRead = isMine && readCount > 0 && m.status == ChatSendStatus.sent && !deleted;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Align(
            alignment: align,
            child: GestureDetector(
              onLongPress: canManage ? () => _openMessageMenu(m) : null,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.authorName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.text,
                      style: deleted
                          ? TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                        fontStyle: FontStyle.italic,
                      )
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _fmtTime(m.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        if (edited) ...[
                          const SizedBox(width: 10),
                          Text(
                            'edited',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                        if (statusText.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                        if (showRead) ...[
                          const SizedBox(width: 10),
                          Text(
                            'прочитано: $readCount',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Чат: ${widget.projectName}'),
        // AppBar actions
        actions: [
          IconButton(
            tooltip: 'Участники проекта',
            icon: const Icon(Icons.group_outlined),
            onPressed: _openMembers,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: body),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: const InputDecoration(
                      hintText: 'Сообщение...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sending ? null : _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Отправить'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
