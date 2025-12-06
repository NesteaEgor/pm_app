import 'package:flutter/material.dart';

import '../../core/ui/glass.dart';
import '../auth/auth_api.dart';

import '../tasks/tasks_api.dart';
import '../tasks/tasks_screen.dart';

import '../comments/comments_api.dart';

import 'create_project_dialog.dart';
import 'project.dart';
import 'projects_api.dart';

class ProjectsScreen extends StatefulWidget {
  final ProjectsApi projectsApi;
  final TasksApi tasksApi;
  final CommentsApi commentsApi;
  final AuthApi authApi;
  final VoidCallback onLoggedOut;

  const ProjectsScreen({
    super.key,
    required this.projectsApi,
    required this.tasksApi,
    required this.commentsApi,
    required this.authApi,
    required this.onLoggedOut,
  });

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late Future<List<Project>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.projectsApi.list();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.projectsApi.list();
    });
    await _future;
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<Project>(
      context: context,
      builder: (_) => CreateProjectDialog(projectsApi: widget.projectsApi),
    );

    if (!mounted) return;

    if (created != null) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // фон
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0B1220)],
              ),
            ),
          ),
          const Positioned(top: -120, left: -80, child: _Blob(size: 260)),
          const Positioned(bottom: -140, right: -90, child: _Blob(size: 300)),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      const Text(
                        'Проекты',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () async {
                          await widget.authApi.logout();
                          widget.onLoggedOut();
                        },
                        icon: const Icon(Icons.logout),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: FutureBuilder<List<Project>>(
                      future: _future,
                      builder: (context, snap) {
                        // Лоадинг
                        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                          return ListView(
                            children: const [
                              SizedBox(height: 220),
                              Center(child: CircularProgressIndicator()),
                            ],
                          );
                        }

                        // Ошибка
                        if (snap.hasError) {
                          return ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              const SizedBox(height: 120),
                              Center(
                                child: Text(
                                  'Ошибка загрузки проектов:\n${snap.error}',
                                  textAlign: TextAlign.center,
                                ),
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

                        // Пусто
                        if (projects.isEmpty) {
                          return ListView(
                            padding: const EdgeInsets.all(16),
                            children: const [
                              SizedBox(height: 80),
                              Center(
                                child: Text(
                                  'Пока нет проектов.\nНажми + чтобы создать.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          );
                        }

                        // Список
                        return ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: projects.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            final p = projects[i];
                            return Glass(
                              child: ListTile(
                                title: Text(
                                  p.name,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                subtitle: Text(p.description ?? 'Без описания'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
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
                                  },
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => TasksScreen(
                                        projectId: p.id,
                                        projectName: p.name,
                                        tasksApi: widget.tasksApi,
                                        commentsApi: widget.commentsApi,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  const _Blob({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.cyanAccent.withValues(alpha: 0.28),
            Colors.purpleAccent.withValues(alpha: 0.14),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}
