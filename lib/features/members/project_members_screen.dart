import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/storage/token_storage.dart';
import '../../core/ui/glass.dart';

import '../profile/profile_api.dart';
import '../profile/profile_screen.dart';
import '../profile/user_profile_screen.dart';

import 'project_member.dart';
import 'project_members_api.dart';

class ProjectMembersScreen extends StatefulWidget {
  final String projectId;
  final String projectName;
  final ProjectMembersApi api;
  final TokenStorage tokenStorage;

  // NEW:
  final ProfileApi profileApi;

  const ProjectMembersScreen({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.api,
    required this.tokenStorage,
    required this.profileApi,
  });

  @override
  State<ProjectMembersScreen> createState() => _ProjectMembersScreenState();
}

class _ProjectMembersScreenState extends State<ProjectMembersScreen> {
  final _emailCtrl = TextEditingController();
  Future<List<ProjectMember>>? _future;

  String? _myUserId;
  String? _token;

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
    _token = token;
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

  String? _avatarUrlWithToken(String userId) {
    final t = (_token ?? '').trim();
    if (t.isEmpty) return null;

    const base = 'http://127.0.0.1:8080';
    return '$base/api/users/$userId/avatar?token=$t';
  }

  void _openProfile(ProjectMember m) {
    final isMe = _myUserId != null && m.userId == _myUserId;

    if (isMe) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileScreen(
            profileApi: widget.profileApi,
            tokenStorage: widget.tokenStorage,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: m.userId,
          profileApi: widget.profileApi,
          tokenStorage: widget.tokenStorage,
          initialDisplayName: m.displayName,
          initialEmail: m.email,
          initialRole: m.role,
        ),
      ),
    );
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

                    final avatarUrl = _avatarUrlWithToken(m.userId);

                    return Glass(
                      child: ListTile(
                        leading: InkWell(
                          onTap: () => _openProfile(m),
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
                            child: avatarUrl == null
                                ? Icon(isOwner ? Icons.verified : Icons.person_outline, size: 18)
                                : null,
                          ),
                        ),
                        title: Text(m.displayName),
                        subtitle: Text('${m.email}\n${m.role}'),
                        isThreeLine: true,
                        onTap: () => _openProfile(m),
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
