import 'package:flutter/material.dart';

import 'core/api/api_client.dart';
import 'core/storage/token_storage.dart';

import 'features/auth/auth_api.dart';
import 'features/auth/login_screen.dart';

import 'features/home/home_shell.dart';
import 'features/projects/projects_api.dart';
import 'features/projects/projects_screen.dart';

import 'features/tasks/tasks_api.dart';
import 'features/comments/comments_api.dart';
import 'features/chat/chat_api.dart';

import 'features/members/project_members_api.dart';

import 'features/profile/profile_api.dart';

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

  late final ProjectMembersApi projectMembersApi;

  late final ProfileApi profileApi;

  @override
  void initState() {
    super.initState();

    tokenStorage = TokenStorage();

    apiClient = ApiClient(
      tokenStorage: tokenStorage,
      onUnauthorized: () async {
        if (!mounted) return;
        setState(() {});
      },
    );

    authApi = AuthApi(api: apiClient, tokenStorage: tokenStorage);
    projectsApi = ProjectsApi(api: apiClient);
    tasksApi = TasksApi(api: apiClient);
    commentsApi = CommentsApi(api: apiClient);
    chatApi = ChatApi(api: apiClient);
    projectMembersApi = ProjectMembersApi(api: apiClient);
    profileApi = ProfileApi(api: apiClient);
  }

  Future<bool> _hasToken() async {
    final t = await tokenStorage.readToken();
    return t != null && t.isNotEmpty;
  }

  ThemeData _buildTheme() {
    const seed = Color(0xFF7CFF6B);

    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ).copyWith(
      surface: Colors.white,
      background: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: scheme.surfaceTint,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xA3F0FFE9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
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

          return HomeShell(
            projectsApi: projectsApi,
            tasksApi: tasksApi,
            commentsApi: commentsApi,
            chatApi: chatApi,
            tokenStorage: tokenStorage,
            projectMembersApi: projectMembersApi,
            authApi: authApi,
            onLoggedOut: () => setState(() {}),
            profileApi: profileApi,
          );

        },
      ),
    );
  }
}
