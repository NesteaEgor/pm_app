import 'package:flutter/material.dart';

import '../../core/storage/token_storage.dart';
import 'profile_api.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String? initialDisplayName;
  final String? initialEmail;
  final String? initialRole;

  final ProfileApi profileApi;
  final TokenStorage tokenStorage;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.profileApi,
    required this.tokenStorage,
    this.initialDisplayName,
    this.initialEmail,
    this.initialRole,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  bool _loading = true;
  String? _token;
  Map<String, dynamic>? _user;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _token = await widget.tokenStorage.readToken();
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final u = await widget.profileApi.userById(widget.userId);
      if (!mounted) return;
      setState(() {
        _user = u;
        _loading = false;
      });
    } catch (e) {
      // если эндпоинт другой/не готов — всё равно покажем то, что знаем из members list
      if (!mounted) return;
      setState(() {
        _user = null;
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить профиль: $e')),
      );
    }
  }

  String _avatarUrlWithToken(String userId) {
    const base = 'http://127.0.0.1:8080';
    final t = (_token ?? '').trim();
    final url = '$base/api/users/$userId/avatar';
    return t.isEmpty ? url : '$url?token=$t';
  }

  @override
  Widget build(BuildContext context) {
    final displayName =
    (_user?['displayName'] ?? widget.initialDisplayName ?? '').toString();
    final email = (_user?['email'] ?? widget.initialEmail ?? '').toString();
    final status = (_user?['status'] ?? '').toString();
    final role = (widget.initialRole ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль пользователя'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              backgroundImage: NetworkImage(_avatarUrlWithToken(widget.userId)),
              onBackgroundImageError: (_, __) {},
              child: const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 16),

          if (displayName.isNotEmpty)
            Text(displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(email, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75))),
          ],
          if (role.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Роль: $role'),
          ],
          if (status.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Статус: $status'),
          ],
          if (displayName.isEmpty && email.isEmpty) ...[
            const SizedBox(height: 20),
            const Text('Нет данных профиля'),
          ],
        ],
      ),
    );
  }
}
