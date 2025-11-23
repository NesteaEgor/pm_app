import 'package:flutter/material.dart';
import 'core/api/api_client.dart';
import 'core/storage/token_storage.dart';
import 'features/auth/auth_api.dart';
import 'features/auth/login_screen.dart';

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final TokenStorage tokenStorage;
  late final ApiClient apiClient;
  late final AuthApi authApi;

  @override
  void initState() {
    super.initState();
    tokenStorage = TokenStorage();
    apiClient = ApiClient(tokenStorage: tokenStorage);
    authApi = AuthApi(api: apiClient, tokenStorage: tokenStorage);
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
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan, brightness: Brightness.dark),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: FutureBuilder<bool>(
        future: _hasToken(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final authed = snap.data!;
          if (!authed) {
            return LoginScreen(
              authApi: authApi,
              onAuthed: () => setState(() {}),
            );
          }

          // Временно: показываем /api/me, чтобы убедиться что токен работает
          return FutureBuilder<Map<String, dynamic>>(
            future: authApi.me(),
            builder: (context, meSnap) {
              if (!meSnap.hasData) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              final me = meSnap.data!;
              return Scaffold(
                appBar: AppBar(
                  title: Text('Привет, ${me['displayName']}'),
                  actions: [
                    IconButton(
                      onPressed: () async {
                        await authApi.logout();
                        setState(() {});
                      },
                      icon: const Icon(Icons.logout),
                    )
                  ],
                ),
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('ME:\n$me'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
