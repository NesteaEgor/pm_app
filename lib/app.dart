import 'package:flutter/material.dart';

import 'core/api/api_client.dart';
import 'core/storage/token_storage.dart';

import 'features/auth/auth_api.dart';
import 'features/auth/login_screen.dart';

import 'features/projects/projects_api.dart';
import 'features/projects/projects_screen.dart';

import 'features/tasks/tasks_api.dart';
import 'features/comments/comments_api.dart';
import 'features/chat/chat_api.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final TokenStorage tokenStorage;
  late final ApiClient apiClient;

  late final AuthApi authApi;
  late final ProjectsApi projectsApi;
  late final TasksApi tasksApi;
  late final CommentsApi commentsApi;
  late final ChatApi chatApi;

  @override
  void initState() {
    super.initState();

    tokenStorage = TokenStorage();

    // ВАЖНО: прокидываем onUnauthorized, чтобы при 401 UI возвращался на логин
    apiClient = ApiClient(
      tokenStorage: tokenStorage,
      onUnauthorized: () async {
        if (!mounted) return;
        setState(() {}); // перерисует FutureBuilder -> вернёмся на LoginScreen
      },
    );

    authApi = AuthApi(api: apiClient, tokenStorage: tokenStorage);
    projectsApi = ProjectsApi(api: apiClient);
    tasksApi = TasksApi(api: apiClient);
    commentsApi = CommentsApi(api: apiClient);

    // добавили чат
    chatApi = ChatApi(api: apiClient);
  }

  Future<bool> _hasToken() async {
    final t = await tokenStorage.readToken();
    return t != null && t.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.cyan,
        brightness: Brightness.dark,
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: FutureBuilder<bool>(
        future: _hasToken(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final authed = snap.data!;
          if (!authed) {
            return LoginScreen(
              authApi: authApi,
              onAuthed: () => setState(() {}),
            );
          }

          return ProjectsScreen(
            projectsApi: projectsApi,
            tasksApi: tasksApi,
            commentsApi: commentsApi,

            // добавили чат и tokenStorage для WS
            chatApi: chatApi,
            tokenStorage: tokenStorage,

            authApi: authApi,
            onLoggedOut: () => setState(() {}),
          );
        },
      ),
    );
  }
}
