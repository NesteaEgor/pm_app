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
    const base = 'http://5.129.215.252:8081';
    final t = (_token ?? '').trim();
    final url = '$base/api/users/$userId/avatar';
    return t.isEmpty ? url : '$url?token=$t';
  }

  Widget _roleChip(String role) {
    final cs = Theme.of(context).colorScheme;
    final isOwner = role.toUpperCase() == 'OWNER';
    final icon = isOwner ? Icons.verified_rounded : Icons.badge_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.65),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            role,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final displayName = (_user?['displayName'] ?? widget.initialDisplayName ?? '').toString().trim();
    final email = (_user?['email'] ?? widget.initialEmail ?? '').toString().trim();
    final status = (_user?['status'] ?? '').toString().trim();
    final role = (widget.initialRole ?? '').toString().trim();

    final avatarUrl = _avatarUrlWithToken(widget.userId);

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
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: cs.surfaceContainerHighest,
                  backgroundImage: NetworkImage(avatarUrl),
                  onBackgroundImageError: (_, __) {},
                  child: const SizedBox.shrink(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName.isEmpty ? 'Без имени' : displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (role.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _roleChip(role),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (status.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.55),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote_rounded, color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      status,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (displayName.isEmpty && email.isEmpty && status.isEmpty) ...[
            const SizedBox(height: 18),
            Center(
              child: Text(
                'Нет данных профиля',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
