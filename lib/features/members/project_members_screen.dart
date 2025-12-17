import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/storage/token_storage.dart';
import '../../core/ui/glass.dart';
import 'project_member.dart';
import 'project_members_api.dart';

class ProjectMembersScreen extends StatefulWidget {
  final String projectId;
  final String projectName;
  final ProjectMembersApi api;
  final TokenStorage tokenStorage;

  const ProjectMembersScreen({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.api,
    required this.tokenStorage,
  });

  @override
  State<ProjectMembersScreen> createState() => _ProjectMembersScreenState();
}

class _ProjectMembersScreenState extends State<ProjectMembersScreen> {
  final _emailCtrl = TextEditingController();
  Future<List<ProjectMember>>? _future;

  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _load();
    _initMe();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _initMe() async {
    final token = await widget.tokenStorage.readToken();
    _myUserId = _tryReadSubFromJwt(token);
    if (mounted) setState(() {});
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

  void _load() {
    setState(() {
      _future = widget.api.list(widget.projectId);
    });
  }

  Future<void> _invite(String email) async {
    final e = email.trim().toLowerCase();
    if (e.isEmpty) return;

    try {
      await widget.api.add(projectId: widget.projectId, email: e);
      _emailCtrl.clear();
      _load();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось добавить: $err')),
      );
    }
  }

  Future<void> _remove(ProjectMember m) async {
    try {
      await widget.api.remove(projectId: widget.projectId, userId: m.userId);
      _load();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить: $err')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Участники: ${widget.projectName}'),
      ),
      body: FutureBuilder<List<ProjectMember>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final members = snap.data!;
          final me = members.where((x) => x.userId == _myUserId).toList();
          final iAmOwner = me.isNotEmpty && me.first.role == 'OWNER';

          return Column(
            children: [
              if (iAmOwner)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _emailCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Email пользователя…',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: _invite,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _invite(_emailCtrl.text),
                        child: const Text('Добавить'),
                      ),
                    ],
                  ),
                ),

              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: members.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final m = members[i];
                    final isOwner = m.role == 'OWNER';
                    final canRemove = iAmOwner && !isOwner;

                    return Glass(
                      child: ListTile(
                        leading: Icon(isOwner ? Icons.verified : Icons.person_outline),
                        title: Text(m.displayName),
                        subtitle: Text('${m.email}\n${m.role}'),
                        isThreeLine: true,
                        trailing: canRemove
                            ? IconButton(
                          tooltip: 'Удалить',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => _remove(m),
                        )
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
