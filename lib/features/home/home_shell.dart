import 'package:flutter/material.dart';

import '../../core/storage/token_storage.dart';

import '../auth/auth_api.dart';

import '../projects/projects_api.dart';
import '../projects/projects_screen.dart';

import '../tasks/tasks_api.dart';
import '../comments/comments_api.dart';

import '../chat/chat_api.dart';
import '../chat/project_chat_screen.dart';

import '../members/project_members_api.dart';

import '../profile/profile_api.dart';
import '../profile/profile_screen.dart';
import '../projects/project.dart';

class HomeShell extends StatefulWidget {
  final ProjectsApi projectsApi;
  final TasksApi tasksApi;
  final CommentsApi commentsApi;

  final ChatApi chatApi;
  final TokenStorage tokenStorage;

  final ProjectMembersApi projectMembersApi;

  final AuthApi authApi;
  final VoidCallback onLoggedOut;

  final ProfileApi profileApi;

  const HomeShell({
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
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  final _keys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  Future<bool> _onWillPop() async {
    final nav = _keys[_index].currentState;
    if (nav == null) return true;
    if (nav.canPop()) {
      nav.pop();
      return false;
    }
    return true;
  }

  void _selectTab(int i) {
    if (i == _index) {
      _keys[i].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() => _index = i);
  }

  Route _routeProjects(RouteSettings s) {
    return MaterialPageRoute(
      settings: s,
      builder: (_) => ProjectsScreen(
        projectsApi: widget.projectsApi,
        tasksApi: widget.tasksApi,
        commentsApi: widget.commentsApi,
        chatApi: widget.chatApi,
        tokenStorage: widget.tokenStorage,
        projectMembersApi: widget.projectMembersApi,
        authApi: widget.authApi,
        onLoggedOut: widget.onLoggedOut,
        profileApi: widget.profileApi,
      ),
    );
  }

  Route _routeChats(RouteSettings s) {
    return MaterialPageRoute(
      settings: s,
      builder: (_) => _ChatsTabScreen(
        projectsApi: widget.projectsApi,
        chatApi: widget.chatApi,
        tokenStorage: widget.tokenStorage,
        projectMembersApi: widget.projectMembersApi,
        profileApi: widget.profileApi,
      ),
    );
  }

  Route _routeProfile(RouteSettings s) {
    return MaterialPageRoute(
      settings: s,
      builder: (_) => ProfileScreen(
        profileApi: widget.profileApi,
        tokenStorage: widget.tokenStorage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      Navigator(
        key: _keys[0],
        onGenerateRoute: (s) => _routeProjects(s),
      ),
      Navigator(
        key: _keys[1],
        onGenerateRoute: (s) => _routeChats(s),
      ),
      Navigator(
        key: _keys[2],
        onGenerateRoute: (s) => _routeProfile(s),
      ),
    ];

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: pages,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder_rounded),
              label: 'Проекты',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Чаты',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Профиль',
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatsTabScreen extends StatefulWidget {
  final ProjectsApi projectsApi;
  final ChatApi chatApi;
  final TokenStorage tokenStorage;
  final ProjectMembersApi projectMembersApi;
  final ProfileApi profileApi;

  const _ChatsTabScreen({
    required this.projectsApi,
    required this.chatApi,
    required this.tokenStorage,
    required this.projectMembersApi,
    required this.profileApi,
  });

  @override
  State<_ChatsTabScreen> createState() => _ChatsTabScreenState();
}

class _ChatsTabScreenState extends State<_ChatsTabScreen> {
  late Future<List<Project>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.projectsApi.list();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.projectsApi.list());
    await _future;
  }

  void _open(Project p) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Чаты')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Project>>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) {
              return ListView(
                children: const [
                  SizedBox(height: 240),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }

            final projects = snap.data ?? [];
            if (projects.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('Пока нет проектов.')),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = projects[i];
                return ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: Text(p.name),
                  subtitle: Text(p.description ?? ''),
                  onTap: () => _open(p),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
