import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/storage/token_storage.dart';

import '../auth/auth_api.dart';

import '../tasks/tasks_api.dart';
import '../tasks/tasks_screen.dart';

import '../comments/comments_api.dart';

import '../chat/chat_api.dart';
import '../chat/project_chat_screen.dart';

import 'create_project_dialog.dart';
import 'project.dart';
import 'projects_api.dart';

import '../members/project_members_api.dart';

import '../profile/profile_api.dart';
import '../profile/profile_screen.dart';

class ProjectsScreen extends StatefulWidget {
  final ProjectsApi projectsApi;
  final TasksApi tasksApi;
  final CommentsApi commentsApi;

  final ChatApi chatApi;
  final TokenStorage tokenStorage;

  final ProjectMembersApi projectMembersApi;

  final AuthApi authApi;
  final VoidCallback onLoggedOut;

  final ProfileApi profileApi;

  const ProjectsScreen({
    super.key,
    required this.projectsApi,
    required this.tasksApi,
    required this.commentsApi,
    required this.chatApi,
    required this.tokenStorage,
    required this.projectMembersApi,
    required this.authApi,
    required this.onLoggedOut,
    required this.profileApi,
  });

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late Future<List<Project>> _future;

  String? _myUserId;

  final Map<String, bool> _iAmOwnerByProjectId = {};
  final Set<String> _ownerLoading = {};

  @override
  void initState() {
    super.initState();
    _future = widget.projectsApi.list();
    _initMe();
  }

  Future<void> _initMe() async {
    final token = await widget.tokenStorage.readToken();
    final uid = _tryReadSubFromJwt(token);
    if (!mounted) return;
    setState(() => _myUserId = uid);
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

  Future<void> _ensureOwnerLoaded(String projectId) async {
    if (_myUserId == null || _myUserId!.isEmpty) return;
    if (_iAmOwnerByProjectId.containsKey(projectId)) return;
    if (_ownerLoading.contains(projectId)) return;

    _ownerLoading.add(projectId);

    try {
      final members = await widget.projectMembersApi.list(projectId);
      final me = members.where((m) => m.userId == _myUserId).toList();
      final isOwner = me.isNotEmpty && me.first.role == 'OWNER';

      if (!mounted) return;
      setState(() {
        _iAmOwnerByProjectId[projectId] = isOwner;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _iAmOwnerByProjectId[projectId] = false;
      });
    } finally {
      _ownerLoading.remove(projectId);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.projectsApi.list();
      _iAmOwnerByProjectId.clear();
      _ownerLoading.clear();
    });
    await _future;
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<Project>(
      context: context,
      builder: (_) => CreateProjectDialog(projectsApi: widget.projectsApi),
    );

    if (!mounted) return;
    if (created != null) await _refresh();
  }

  void _openChat(Project p) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => ProjectChatScreen(
          projectId: p.id,
          projectName: p.name,
          chatApi: widget.chatApi,
          tokenStorage: widget.tokenStorage,
          projectMembersApi: widget.projectMembersApi,
          profileApi: widget.profileApi,
        ),
      ),
    );
  }

  void _openTasks(Project p) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => TasksScreen(
          projectId: p.id,
          projectName: p.name,
          tasksApi: widget.tasksApi,
          commentsApi: widget.commentsApi,
          tokenStorage: widget.tokenStorage,
          projectMembersApi: widget.projectMembersApi,
        ),
      ),
    );
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          profileApi: widget.profileApi,
          tokenStorage: widget.tokenStorage,
        ),
      ),
    );
  }

  Future<void> _deleteProject(Project p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить проект?'),
        content: Text('Проект “${p.name}” будет удалён.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );

    if (!mounted || ok != true) return;

    try {
      await widget.projectsApi.delete(p.id);
      if (!mounted) return;
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Проекты'),
        actions: [
          IconButton(
            tooltip: 'Профиль',
            onPressed: _openProfile,
            icon: const Icon(Icons.person_outline),
          ),
          IconButton(
            tooltip: 'Выйти',
            onPressed: () async {
              await widget.authApi.logout();
              widget.onLoggedOut();
            },
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Project>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  SizedBox(height: 220),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }

            if (snap.hasError) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 120),
                  Icon(Icons.cloud_off_rounded, size: 44, color: cs.onSurfaceVariant),
                  const SizedBox(height: 10),
                  Text(
                    'Ошибка загрузки проектов:\n${snap.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: FilledButton(
                      onPressed: _refresh,
                      child: const Text('Повторить'),
                    ),
                  ),
                ],
              );
            }

            final projects = snap.data ?? [];

            if (projects.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 120),
                  Icon(Icons.folder_open_rounded, size: 44, color: cs.onSurfaceVariant),
                  const SizedBox(height: 10),
                  Text(
                    'Пока нет проектов.\nНажми + чтобы создать.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final p = projects[i];
                _ensureOwnerLoaded(p.id);

                final iAmOwner = _iAmOwnerByProjectId[p.id] == true;

                return Card(
                  elevation: 0,
                  color: cs.surfaceContainerLowest,
                  surfaceTintColor: cs.surfaceTint,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _openTasks(p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(Icons.workspaces_rounded, color: cs.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  (p.description ?? 'Без описания').trim().isEmpty
                                      ? 'Без описания'
                                      : (p.description ?? 'Без описания'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Чат',
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                            onPressed: () => _openChat(p),
                          ),
                          if (iAmOwner)
                            IconButton(
                              tooltip: 'Удалить',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => _deleteProject(p),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
