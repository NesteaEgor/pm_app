import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../../core/storage/token_storage.dart';
import 'chat_api.dart';
import 'chat_message.dart';

class ProjectChatScreen extends StatefulWidget {
  final String projectId;
  final String projectName;
  final ChatApi chatApi;
  final TokenStorage tokenStorage;

  const ProjectChatScreen({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.chatApi,
    required this.tokenStorage,
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

  @override
  void initState() {
    super.initState();
    _init();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _stomp?.deactivate();
    super.dispose();
  }

  void _onScroll() {
    // пагинация назад: когда наверху — подгружаем старые
    if (_scroll.position.pixels <= 80 && !_loadingMore && _items.isNotEmpty) {
      _loadMore();
    }
  }

  Future<void> _init() async {
    await _loadInitial();
    await _connectWs();
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

      // скролл вниз
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
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
        // сохраняем позицию скролла примерно
        final prevOffset = _scroll.position.pixels;

        setState(() {
          _items.insertAll(0, older);
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(prevOffset + 200); // простая компенсация, потом улучшим
          }
        });
      }
    } catch (_) {
      // молча, чтобы не раздражать
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _connectWs() async {
    final token = await widget.tokenStorage.readToken();
    if (token == null || token.isEmpty) return;

    //   ws url:
    // - Android Emulator: ws://10.0.2.2:8080/ws
    // - Real device: ws://<IP_твоего_ПК>:8080/ws
    // - если у тебя всё работало на 127.0.0.1 — значит ты используешь adb reverse
    final wsUrl = 'ws://127.0.0.1:8080/ws';

    final client = StompClient(
      config: StompConfig(
        url: wsUrl,
        stompConnectHeaders: {
          'Authorization': 'Bearer $token',
        },
        webSocketConnectHeaders: const {},
        onConnect: _onConnect,
        onStompError: (StompFrame f) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('WS ошибка: ${f.body}')),
          );
        },
        onWebSocketError: (dynamic err) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('WS error: $err')),
          );
        },
        reconnectDelay: const Duration(seconds: 2),
      ),
    );

    setState(() => _stomp = client);
    client.activate();
  }

  void _onConnect(StompFrame frame) {
    final topic = '/topic/projects/${widget.projectId}/messages';

    _stomp?.subscribe(
      destination: topic,
      callback: (StompFrame f) {
        if (f.body == null) return;
        final jsonMap = jsonDecode(f.body!) as Map<String, dynamic>;
        final msg = ChatMessage.fromJson(jsonMap);

        if (!mounted) return;
        setState(() => _items.add(msg));

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent + 120,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
          }
        });
      },
    );
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    if (_stomp == null) return;

    setState(() => _sending = true);
    try {
      _stomp!.send(
        destination: '/app/projects/${widget.projectId}/messages',
        body: jsonEncode({'text': text}),
      );
      _ctrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не отправилось: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
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
                  Text(m.text),
                  const SizedBox(height: 6),
                  Text(
                    m.createdAt.toLocal().toString(),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Чат: ${widget.projectName}'),
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
