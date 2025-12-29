import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/storage/token_storage.dart';

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

    const base = 'http://5.129.215.252:8081';
    final uri = Uri.parse('$base/api/users/$userId/avatar');
    final qp = Map<String, String>.from(uri.queryParameters);
    qp['token'] = t;
    return uri.replace(queryParameters: qp).toString();
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
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пользователь добавлен')),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось добавить: $err')),
      );
    }
  }

  Future<void> _remove(ProjectMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить участника?'),
        content: Text('${m.displayName} будет удалён из проекта.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );

    if (!mounted || ok != true) return;

    try {
      await widget.api.remove(projectId: widget.projectId, userId: m.userId);
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Удалено')),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить: $err')),
      );
    }
  }

  Widget _inviteBar() {
    final cs = Theme.of(context).colorScheme;
    final canInvite = _emailCtrl.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.6))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.65),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'Email пользователя…',
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: _invite,
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: canInvite ? () => _invite(_emailCtrl.text) : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  Widget _memberTile(ProjectMember m, {required bool iAmOwner}) {
    final cs = Theme.of(context).colorScheme;
    final isOwner = m.role == 'OWNER';
    final canRemove = iAmOwner && !isOwner;

    final avatarUrl = _avatarUrlWithToken(m.userId);
    final isMe = _myUserId != null && m.userId == _myUserId;

    final badgeText = isMe ? 'Вы' : (isOwner ? 'OWNER' : 'MEMBER');
    final badgeBg = isOwner ? cs.primaryContainer : cs.surfaceContainerHighest;

    return InkWell(
      onTap: () => _openProfile(m),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
        ),
        child: Row(
          children: [
            InkWell(
              onTap: () => _openProfile(m),
              customBorder: const CircleBorder(),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: cs.surfaceContainerHighest,
                backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
                child: avatarUrl == null
                    ? Icon(
                  isOwner ? Icons.verified_rounded : Icons.person_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          m.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
                        ),
                        child: Text(
                          badgeText,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    m.email,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (canRemove) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Удалить',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => _remove(m),
              ),
            ],
          ],
        ),
      ),
    );
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
                SafeArea(
                  bottom: false,
                  child: AnimatedPadding(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
                    child: _inviteBar(),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: members.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _memberTile(members[i], iAmOwner: iAmOwner),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
