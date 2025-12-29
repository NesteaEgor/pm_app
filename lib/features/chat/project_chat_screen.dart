import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/storage/token_storage.dart';
import '../profile/profile_api.dart';
import 'chat_api.dart';
import 'chat_message.dart';
import 'chat_read.dart';

import '../members/project_members_api.dart';
import '../members/project_members_screen.dart';

class _PendingSend {
  final String clientMessageId;
  final String text;
  final List<String> attachmentIds;

  int attempts = 0;
  DateTime lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  _PendingSend({
    required this.clientMessageId,
    required this.text,
    required this.attachmentIds,
  });
}

class _TypingEvent {
  final String projectId;
  final String userId;
  final String userName;
  final bool typing;

  _TypingEvent({
    required this.projectId,
    required this.userId,
    required this.userName,
    required this.typing,
  });

  factory _TypingEvent.fromJson(Map<String, dynamic> json) {
    return _TypingEvent(
      projectId: json['projectId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      userName: (json['userName'] ?? 'Unknown').toString(),
      typing: json['typing'] == true,
    );
  }
}

class _ReactionEvent {
  final String projectId;
  final String messageId;
  final String emoji;

  final Map<String, int>? reactions;

  final String? userId;
  final bool? added;

  _ReactionEvent({
    required this.projectId,
    required this.messageId,
    required this.emoji,
    required this.reactions,
    required this.userId,
    required this.added,
  });

  factory _ReactionEvent.fromJson(Map<String, dynamic> json) {
    Map<String, int>? rx;
    final raw = json['reactions'];
    if (raw is Map) {
      rx = raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }

    return _ReactionEvent(
      projectId: json['projectId']?.toString() ?? '',
      messageId: json['messageId']?.toString() ?? '',
      emoji: json['emoji']?.toString() ?? '',
      reactions: rx,
      userId: json['userId']?.toString(),
      added: json['added'] is bool ? json['added'] as bool : null,
    );
  }
}

class ProjectChatScreen extends StatefulWidget {
  final String projectId;
  final String projectName;
  final ChatApi chatApi;
  final TokenStorage tokenStorage;

  final ProjectMembersApi projectMembersApi;
  final ProfileApi profileApi;

  const ProjectChatScreen({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.chatApi,
    required this.tokenStorage,
    required this.projectMembersApi,
    required this.profileApi,
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

  final Map<String, int> _pendingIndexByClientId = {};
  final Map<String, _PendingSend> _outbox = {};
  Timer? _retryTimer;

  String? _myUserId;

  final Map<String, DateTime> _lastReadMessageAtByUser = {};
  final Map<String, String> _userNameByUserId = {};

  String? _lastReadSentMessageId;
  DateTime _lastReadSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  final Map<String, DateTime> _typingUntilByUser = {};
  final Map<String, String> _typingNameByUser = {};
  Timer? _typingGcTimer;
  Timer? _typingStopDebounce;
  DateTime _lastTypingSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _typingSent = false;

  final List<ChatAttachment> _composerAttachments = [];
  final Set<String> _uploadingNames = {};

  String? _token;

  bool _iAmOwner = false;

  @override
  void initState() {
    super.initState();
    _init();
    _scroll.addListener(_onScroll);

    _retryTimer = Timer.periodic(const Duration(seconds: 2), (_) => _flushOutbox());

    _typingGcTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      final now = DateTime.now();
      final toRemove = <String>[];
      for (final e in _typingUntilByUser.entries) {
        if (!e.value.isAfter(now)) toRemove.add(e.key);
      }
      if (toRemove.isNotEmpty && mounted) {
        setState(() {
          for (final id in toRemove) {
            _typingUntilByUser.remove(id);
            _typingNameByUser.remove(id);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _typingGcTimer?.cancel();
    _typingStopDebounce?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    _stomp?.deactivate();
    super.dispose();
  }

  String? _avatarUrlForUserId(String? userId) {
    final id = (userId ?? '').trim();
    if (id.isEmpty) return null;

    const base = 'http://5.129.215.252:8081';
    final full = '$base/api/users/$id/avatar';

    final t = (_token ?? '').trim();
    if (t.isEmpty) return full;

    final uri = Uri.parse(full);
    final qp = Map<String, String>.from(uri.queryParameters);
    qp['token'] = t;
    return uri.replace(queryParameters: qp).toString();
  }

  Widget _buildUserAvatar(String? userId, {double radius = 16}) {
    final cs = Theme.of(context).colorScheme;
    final url = _avatarUrlForUserId(userId);

    Widget fallback() => CircleAvatar(
      radius: radius,
      backgroundColor: cs.surfaceContainerHighest,
      child: Icon(Icons.person_rounded, size: radius + 4, color: cs.onSurfaceVariant),
    );

    if (url == null) return fallback();

    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.surfaceContainerHighest,
      child: ClipOval(
        child: Image.network(
          url,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback(),
        ),
      ),
    );
  }

  Map<String, String> _authHeaders() {
    final t = (_token ?? '').trim();
    if (t.isEmpty) return const {};
    return {'Authorization': 'Bearer $t'};
  }

  String _externalDownloadUrl(ChatAttachment a) {
    final base = _attachmentUrl(a);
    final t = (_token ?? '').trim();
    if (t.isEmpty) return base;

    final uri = Uri.parse(base);
    final qp = Map<String, String>.from(uri.queryParameters);
    qp['token'] = t;

    return uri.replace(queryParameters: qp).toString();
  }

  void _openMembers() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => ProjectMembersScreen(
          projectId: widget.projectId,
          projectName: widget.projectName,
          api: widget.projectMembersApi,
          tokenStorage: widget.tokenStorage,
          profileApi: widget.profileApi,
        ),
      ),
    );
  }

  void _onScroll() {
    if (_scroll.position.pixels <= 80 && !_loadingMore && _items.isNotEmpty) {
      _loadMore();
    }
    _maybeSendRead();
  }

  Future<void> _init() async {
    final token = await widget.tokenStorage.readToken();
    _token = token;
    _myUserId = _tryReadSubFromJwt(token);

    await _loadMyRole();
    await _loadInitial();
    await _loadReadsInitial();
    await _connectWs();

    _maybeSendRead(force: true);
  }

  Future<void> _loadMyRole() async {
    try {
      if (_myUserId == null) return;
      final members = await widget.projectMembersApi.list(widget.projectId);
      final me = members.where((m) => m.userId == _myUserId).toList();
      final owner = me.isNotEmpty && me.first.role == 'OWNER';
      if (mounted) setState(() => _iAmOwner = owner);
    } catch (_) {}
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
        _userNameByUserId.clear();
        for (final r in reads) {
          if (r.userId == _myUserId) continue;
          final at = r.lastReadMessageAt;
          if (at != null) _lastReadMessageAtByUser[r.userId] = at.toLocal();

          final name = r.userName;
          if (name != null && name.isNotEmpty) _userNameByUserId[r.userId] = name;
        }
      });
    } catch (_) {}
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
    final token = (_token ?? await widget.tokenStorage.readToken());
    if (token == null || token.isEmpty) return;

    final wsUrl = 'ws://5.129.215.252:8081/ws';

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
    final typingTopic = '/topic/projects/${widget.projectId}/typing';
    final reactionsTopic = '/topic/projects/${widget.projectId}/reactions';

    _stomp?.subscribe(
      destination: msgTopic,
      callback: (StompFrame f) {
        if (f.body == null) return;

        final jsonMap = jsonDecode(f.body!) as Map<String, dynamic>;
        final msg = ChatMessage.fromJson(jsonMap);

        if (!mounted) return;

        final type = jsonMap['eventType']?.toString();
        final cid = jsonMap['clientMessageId']?.toString();

        if ((type == null || type == 'CREATED') && cid != null && _pendingIndexByClientId.containsKey(cid)) {
          final idx = _pendingIndexByClientId[cid]!;
          setState(() {
            final old = _items[idx];
            _items[idx] = old.copyWith(
              id: msg.id,
              createdAt: msg.createdAt,
              status: ChatSendStatus.sent,
              authorName: msg.authorName,
              text: msg.text,
              editedAt: msg.editedAt,
              deletedAt: msg.deletedAt,
              attachments: msg.attachments.isNotEmpty ? msg.attachments : old.attachments,
              reactions: msg.reactions.isNotEmpty ? msg.reactions : old.reactions,
              myReactions: msg.myReactions.isNotEmpty ? msg.myReactions : old.myReactions,
            );
            _pendingIndexByClientId.remove(cid);
            _outbox.remove(cid);
          });

          _scrollToBottomSoft();
          _maybeSendRead(force: true);
          return;
        }

        if ((type == 'UPDATED' || type == 'DELETED') && msg.id != null) {
          final i = _items.indexWhere((x) => x.id == msg.id);
          if (i != -1) {
            setState(() {
              final old = _items[i];
              _items[i] = old.copyWith(
                text: msg.text,
                editedAt: msg.editedAt,
                deletedAt: msg.deletedAt,
                authorName: msg.authorName,
                attachments: msg.attachments.isNotEmpty ? msg.attachments : old.attachments,
                reactions: msg.reactions.isNotEmpty ? msg.reactions : old.reactions,
                myReactions: msg.myReactions.isNotEmpty ? msg.myReactions : old.myReactions,
              );
            });
          }
          return;
        }

        setState(() => _items.add(msg));
        _scrollToBottomSoft();
        _maybeSendRead(force: true);
      },
    );

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
          final name = r.userName;
          if (name != null && name.isNotEmpty) _userNameByUserId[r.userId] = name;
        });
      },
    );

    _stomp?.subscribe(
      destination: typingTopic,
      callback: (StompFrame f) {
        if (f.body == null) return;
        final jsonMap = jsonDecode(f.body!) as Map<String, dynamic>;
        final ev = _TypingEvent.fromJson(jsonMap);

        if (!mounted) return;
        if (ev.userId.isEmpty) return;
        if (ev.userId == _myUserId) return;

        setState(() {
          if (ev.typing) {
            _typingUntilByUser[ev.userId] = DateTime.now().add(const Duration(seconds: 4));
            _typingNameByUser[ev.userId] = ev.userName;
          } else {
            _typingUntilByUser.remove(ev.userId);
            _typingNameByUser.remove(ev.userId);
          }
        });
      },
    );

    _stomp?.subscribe(
      destination: reactionsTopic,
      callback: (StompFrame f) {
        if (f.body == null) return;
        final jsonMap = jsonDecode(f.body!) as Map<String, dynamic>;
        final ev = _ReactionEvent.fromJson(jsonMap);

        if (!mounted) return;
        if (ev.messageId.isEmpty) return;

        final i = _items.indexWhere((x) => x.id == ev.messageId);
        if (i == -1) return;

        setState(() {
          final old = _items[i];
          final newReactions = Map<String, int>.from(old.reactions);
          final newMy = Set<String>.from(old.myReactions);

          if (ev.reactions != null) {
            newReactions
              ..clear()
              ..addAll(ev.reactions!);
          } else if (ev.emoji.isNotEmpty && ev.added != null && ev.userId != null) {
            final cur = newReactions[ev.emoji] ?? 0;
            final next = ev.added! ? (cur + 1) : (cur - 1);
            if (next <= 0) {
              newReactions.remove(ev.emoji);
            } else {
              newReactions[ev.emoji] = next;
            }

            if (ev.userId == _myUserId) {
              if (ev.added!) {
                newMy.add(ev.emoji);
              } else {
                newMy.remove(ev.emoji);
              }
            }
          }

          _items[i] = old.copyWith(reactions: newReactions, myReactions: newMy);
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

  void _enqueueAndTrySend({
    required String text,
    required List<ChatAttachment> attachments,
  }) {
    final clientId = _newClientMessageId();
    final attachmentIds = attachments.map((a) => a.id).where((x) => x.isNotEmpty).toList();

    final pending = ChatMessage.pending(
      clientMessageId: clientId,
      projectId: widget.projectId,
      authorId: _myUserId ?? 'me',
      authorName: 'You',
      text: text,
      attachments: attachments,
    );

    setState(() {
      _items.add(pending);
      _pendingIndexByClientId[clientId] = _items.length - 1;
      _outbox[clientId] = _PendingSend(
        clientMessageId: clientId,
        text: text,
        attachmentIds: attachmentIds,
      );
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

        final body = <String, dynamic>{
          'text': p.text,
          'clientMessageId': cid,
        };
        if (p.attachmentIds.isNotEmpty) {
          body['attachmentIds'] = p.attachmentIds;
        }

        _stomp!.send(
          destination: '/app/projects/${widget.projectId}/messages',
          body: jsonEncode(body),
        );
      } catch (_) {}
    }
  }

  bool _isNearBottom() {
    if (!_scroll.hasClients) return false;
    final max = _scroll.position.maxScrollExtent;
    final cur = _scroll.position.pixels;
    return (max - cur) <= 140;
  }

  ChatMessage? _latestReadableMessage() {
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
      if (now.difference(_lastReadSentAt) < const Duration(seconds: 1)) return;
      if (_lastReadSentMessageId == last.id) return;
    }

    _lastReadSentMessageId = last.id;
    _lastReadSentAt = now;

    try {
      _stomp!.send(
        destination: '/app/projects/${widget.projectId}/read',
        body: jsonEncode({'messageId': last.id}),
      );
    } catch (_) {}
  }

  void _onComposerChanged(String value) {
    if (!_wsConnected || _stomp == null) return;

    final now = DateTime.now();
    final shouldSendStart = !_typingSent || now.difference(_lastTypingSentAt) >= const Duration(milliseconds: 900);

    if (shouldSendStart) {
      _sendTyping(true);
    }

    _typingStopDebounce?.cancel();
    _typingStopDebounce = Timer(const Duration(milliseconds: 1200), () {
      _sendTyping(false);
    });
  }

  void _sendTyping(bool typing) {
    if (!_wsConnected || _stomp == null) return;

    if (typing == _typingSent && DateTime.now().difference(_lastTypingSentAt) < const Duration(seconds: 1)) {
      return;
    }

    _typingSent = typing;
    _lastTypingSentAt = DateTime.now();

    try {
      _stomp!.send(
        destination: '/app/projects/${widget.projectId}/typing',
        body: jsonEncode({'typing': typing}),
      );
    } catch (_) {}
  }

  String? _typingLineText() {
    final now = DateTime.now();
    final ids = _typingUntilByUser.entries
        .where((e) => e.value.isAfter(now))
        .map((e) => e.key)
        .where((id) => id != _myUserId)
        .toList();

    if (ids.isEmpty) return null;

    final names = ids.map((id) => _typingNameByUser[id] ?? 'Кто-то').toList();
    if (names.length == 1) return '${names[0]} печатает…';
    if (names.length == 2) return '${names[0]} и ${names[1]} печатают…';
    return '${names[0]}, ${names[1]} и ещё ${names.length - 2} печатают…';
  }

  void _toggleReaction(ChatMessage m, String emoji) {
    if (m.id == null || m.isDeleted) return;
    if (!_wsConnected || _stomp == null) return;

    final i = _items.indexWhere((x) => x.id == m.id);
    if (i != -1) {
      setState(() {
        final old = _items[i];
        final rx = Map<String, int>.from(old.reactions);
        final my = Set<String>.from(old.myReactions);

        final had = my.contains(emoji);
        if (had) {
          my.remove(emoji);
          final cur = rx[emoji] ?? 0;
          final next = cur - 1;
          if (next <= 0) {
            rx.remove(emoji);
          } else {
            rx[emoji] = next;
          }
        } else {
          my.add(emoji);
          rx[emoji] = (rx[emoji] ?? 0) + 1;
        }

        _items[i] = old.copyWith(reactions: rx, myReactions: my);
      });
    }

    try {
      _stomp!.send(
        destination: '/app/projects/${widget.projectId}/messages/${m.id}/reactions/toggle',
        body: jsonEncode({'emoji': emoji}),
      );
    } catch (_) {}
  }

  Future<void> _pickAndUploadFiles() async {
    if (_sending) return;

    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось выбрать файл: $e')));
      return;
    }

    if (!mounted || res == null || res.files.isEmpty) return;

    for (final f in res.files) {
      final path = f.path;
      if (path == null || path.isEmpty) continue;

      setState(() => _uploadingNames.add(f.name));
      try {
        final att = await widget.chatApi.uploadFile(
          projectId: widget.projectId,
          filePath: path,
          fileName: f.name,
        );
        if (!mounted) return;
        setState(() => _composerAttachments.add(att));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload не удался (${f.name}): $e')));
      } finally {
        if (mounted) setState(() => _uploadingNames.remove(f.name));
      }
    }
  }

  String _attachmentUrl(ChatAttachment a) {
    final raw = (a.url ?? '').trim();
    if (raw.isNotEmpty) {
      if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
      if (raw.startsWith('/')) {
        return 'http://5.129.215.252:8081$raw';
      }
    }
    return 'http://5.129.215.252:8081/api/projects/${widget.projectId}/files/${a.id}';
  }

  Future<void> _openAttachment(ChatAttachment a) async {
    final url = _externalDownloadUrl(a);
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось открыть файл')));
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    final attachments = List<ChatAttachment>.from(_composerAttachments);

    if (text.isEmpty && attachments.isEmpty) return;

    setState(() => _sending = true);
    try {
      _enqueueAndTrySend(text: text, attachments: attachments);
      _ctrl.clear();
      setState(() => _composerAttachments.clear());
      _sendTyping(false);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _canEditMessage(ChatMessage m) {
    final isMine = _myUserId != null && m.authorId == _myUserId;
    if (!isMine) return false;
    if (m.status != ChatSendStatus.sent) return false;
    if (m.id == null) return false;
    if (m.isDeleted) return false;
    return true;
  }

  bool _canDeleteMessage(ChatMessage m) {
    if (m.status != ChatSendStatus.sent) return false;
    if (m.id == null) return false;
    if (m.isDeleted) return false;

    final isMine = _myUserId != null && m.authorId == _myUserId;
    if (isMine) return true;

    return _iAmOwner;
  }

  Future<void> _openMessageActionSheet(ChatMessage m) async {
    if (m.id == null || m.isDeleted) return;

    final canEdit = _canEditMessage(m);
    final canDelete = _canDeleteMessage(m);

    const emojis = ['👍', '❤️', '😂', '🔥', '😮', '😢', '👎', '🎉'];

    final act = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;

        Widget reactionChip(String e) {
          final selected = m.myReactions.contains(e);
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(ctx, 'react:$e'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: selected ? cs.primary.withOpacity(0.14) : cs.surfaceContainerHighest,
                border: selected ? Border.all(color: cs.primary.withOpacity(0.35)) : null,
              ),
              child: Text(e, style: const TextStyle(fontSize: 22)),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _buildUserAvatar(m.authorId, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      m.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    _fmtTime(m.createdAt),
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: emojis.map(reactionChip).toList(),
                ),
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              if (canEdit)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Редактировать'),
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
              if (canDelete)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(_iAmOwner && m.authorId != _myUserId ? 'Удалить (как OWNER)' : 'Удалить'),
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Закрыть'),
                onTap: () => Navigator.pop(ctx, 'close'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || act == null) return;

    if (act.startsWith('react:')) {
      final emoji = act.substring('react:'.length);
      if (emoji.isNotEmpty) _toggleReaction(m, emoji);
    } else if (act == 'edit') {
      await _editMessage(m);
    } else if (act == 'delete') {
      await _deleteMessage(m);
    }
  }

  Future<void> _editMessage(ChatMessage m) async {
    if (m.id == null) return;
    if (!_canEditMessage(m)) return;

    final ctrl = TextEditingController(text: m.text);

    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Редактировать'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
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
    if (!_canDeleteMessage(m)) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        content: Text(
          _iAmOwner && m.authorId != _myUserId
              ? 'Вы OWNER — можно удалить чужое сообщение. Удалить?'
              : 'Сообщение будет помечено как удалённое.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );

    if (!mounted || ok != true) return;

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
    int c = 0;
    for (final entry in _lastReadMessageAtByUser.entries) {
      final at = entry.value;
      if (at.isAfter(m.createdAt) || at.isAtSameMomentAs(m.createdAt)) {
        c += 1;
      }
    }
    return c;
  }

  void _openReadByDialog(ChatMessage m) {
    final readers = <String>[];
    for (final entry in _lastReadMessageAtByUser.entries) {
      final uid = entry.key;
      final at = entry.value;
      if (at.isAfter(m.createdAt) || at.isAtSameMomentAs(m.createdAt)) {
        readers.add(_userNameByUserId[uid] ?? uid);
      }
    }
    readers.sort();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Прочитали'),
        content: SizedBox(
          width: double.maxFinite,
          child: readers.isEmpty
              ? const Text('Нет данных')
              : ListView.builder(
            shrinkWrap: true,
            itemCount: readers.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(readers[i]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
        ],
      ),
    );
  }

  bool _isImageAttachment(ChatAttachment a) {
    final ct = (a.contentType ?? '').toLowerCase();
    if (ct.startsWith('image/')) return true;

    final name = a.fileName.toLowerCase();
    return name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp');
  }

  Future<void> _openImagePreview(ChatAttachment a) async {
    final url = _attachmentUrl(a);

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(
                url,
                headers: _authHeaders(),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Не удалось загрузить изображение'),
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentsInMessage(ChatMessage m) {
    if (m.attachments.isEmpty) return const SizedBox.shrink();

    final images = m.attachments.where(_isImageAttachment).toList();
    final files = m.attachments.where((a) => !_isImageAttachment(a)).toList();
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (images.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: images.map((a) {
                final url = _attachmentUrl(a);

                return InkWell(
                  onTap: () => _openImagePreview(a),
                  onLongPress: () => _openAttachment(a),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 164,
                      height: 164,
                      color: cs.surfaceContainerHighest.withOpacity(0.55),
                      child: Image.network(
                        url,
                        headers: _authHeaders(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) {
                          return const Center(child: Icon(Icons.broken_image_outlined));
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                        },
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          if (files.isNotEmpty) ...[
            if (images.isNotEmpty) const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: files.map((a) {
                return InkWell(
                  onTap: () => _openAttachment(a),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.attach_file, size: 16, color: cs.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            a.fileName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              decoration: TextDecoration.underline,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReactionsRow(ChatMessage m, {required bool isMine}) {
    if (m.isDeleted || m.id == null) return const SizedBox.shrink();
    if (m.reactions.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final chips = <Widget>[];

    for (final e in m.reactions.entries) {
      final emoji = e.key;
      final count = e.value;
      if (count <= 0) continue;

      final selected = m.myReactions.contains(emoji);

      chips.add(
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _toggleReaction(m, emoji),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected ? cs.primary.withOpacity(0.14) : cs.surfaceContainerHighest.withOpacity(0.85),
              border: selected ? Border.all(color: cs.primary.withOpacity(0.35)) : null,
            ),
            child: Text(
              '$emoji $count',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: 8, left: isMine ? 42 : 0, right: isMine ? 0 : 42),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips,
      ),
    );
  }

  BorderRadius _bubbleRadius({required bool isMine}) {
    const r = 18.0;
    return BorderRadius.only(
      topLeft: const Radius.circular(r),
      topRight: const Radius.circular(r),
      bottomLeft: Radius.circular(isMine ? r : 6),
      bottomRight: Radius.circular(isMine ? 6 : r),
    );
  }

  Color _bubbleColor({required bool isMine}) {
    final cs = Theme.of(context).colorScheme;
    if (isMine) return cs.primary.withOpacity(0.14);
    return cs.surfaceContainerHighest.withOpacity(0.70);
  }

  Widget _buildMessageBubble(ChatMessage m, {required bool isMine}) {
    final cs = Theme.of(context).colorScheme;

    final edited = m.editedAt != null && !m.isDeleted;
    final deleted = m.isDeleted;
    final statusText = m.status == ChatSendStatus.sending ? 'sending…' : '';

    final readCount = (isMine && !deleted && m.status == ChatSendStatus.sent) ? _readCountForMessage(m) : 0;
    final showRead = isMine && readCount > 0 && m.status == ChatSendStatus.sent && !deleted;

    final textStyle = deleted
        ? TextStyle(
      color: cs.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    )
        : Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: cs.onSurface,
      height: 1.25,
    );

    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _bubbleColor(isMine: isMine),
        borderRadius: _bubbleRadius(isMine: isMine),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                m.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (m.text.isNotEmpty) Text(m.text, style: textStyle),
          _buildAttachmentsInMessage(m),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fmtTime(m.createdAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (edited) ...[
                const SizedBox(width: 8),
                Text('edited', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
              if (statusText.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(statusText, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
              if (showRead) ...[
                const SizedBox(width: 10),
                InkWell(
                  onTap: () => _openReadByDialog(m),
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      'прочитано: $readCount',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final cs = Theme.of(context).colorScheme;
    final hasText = _ctrl.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.6))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Прикрепить файл',
            onPressed: _sending ? null : _pickAndUploadFiles,
            icon: const Icon(Icons.attach_file),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.65),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'Сообщение…',
                  border: InputBorder.none,
                ),
                onChanged: (v) {
                  _onComposerChanged(v);
                  if (mounted) setState(() {});
                },
                onSubmitted: (_) => _sending ? null : _send(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: (_sending || (!hasText && _composerAttachments.isEmpty)) ? null : _send,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(14),
            ),
            child: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typingLine = _typingLineText();

    final list = _loading
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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
        final canOpenMenu = (m.id != null && !m.isDeleted);

        final leftPad = isMine ? 56.0 : 0.0;
        final rightPad = isMine ? 0.0 : 56.0;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(left: leftPad, right: rightPad),
                child: Row(
                  mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMine) ...[
                      _buildUserAvatar(m.authorId, radius: 16),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: GestureDetector(
                        onLongPress: canOpenMenu ? () => _openMessageActionSheet(m) : null,
                        child: _buildMessageBubble(m, isMine: isMine),
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 10),
                      _buildUserAvatar(_myUserId ?? 'me', radius: 16),
                    ],
                  ],
                ),
              ),
              _buildReactionsRow(m, isMine: isMine),
            ],
          ),
        );
      },
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text('Чат: ${widget.projectName}${_iAmOwner ? ' • OWNER' : ''}'),
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
          Expanded(child: list),
          if (typingLine != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  typingLine,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          if (_composerAttachments.isNotEmpty || _uploadingNames.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._composerAttachments.map(
                        (a) => InputChip(
                      label: Text(a.fileName),
                      onDeleted: _sending
                          ? null
                          : () {
                        setState(() => _composerAttachments.removeWhere((x) => x.id == a.id));
                      },
                    ),
                  ),
                  ..._uploadingNames.map(
                        (name) => Chip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Flexible(child: Text('upload: $name', overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SafeArea(
            bottom: true,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: _buildComposer(),
            ),
          ),
        ],
      ),
    );
  }
}
