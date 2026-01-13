import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_error_mapper.dart';
import '../../core/storage/token_storage.dart';
import 'profile_api.dart';

class ProfileScreen extends StatefulWidget {
  final ProfileApi profileApi;
  final TokenStorage tokenStorage;

  const ProfileScreen({
    super.key,
    required this.profileApi,
    required this.tokenStorage,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  bool _saving = false;

  String? _token;
  Map<String, dynamic>? _me;

  final _name = TextEditingController();
  final _status = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _name.dispose();
    _status.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _token = await widget.tokenStorage.readToken();
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = await widget.profileApi.me();
      if (!mounted) return;
      setState(() {
        _me = me;
        _name.text = (me['displayName'] ?? '').toString();
        _status.text = (me['status'] ?? '').toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final msg = userMessageFromError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  String? _avatarUrlWithToken() {
    final raw = (_me?['avatarUrl'] ?? '').toString().trim();
    if (raw.isEmpty) return null;

    const base = 'http://5.129.215.252:8081';
    final full = raw.startsWith('http')
        ? raw
        : (raw.startsWith('/') ? '$base$raw' : '$base/$raw');

    final t = (_token ?? '').trim();
    if (t.isEmpty) return full;

    final uri = Uri.parse(full);
    final qp = Map<String, String>.from(uri.queryParameters);
    qp['token'] = t;
    return uri.replace(queryParameters: qp).toString();
  }

  Future<void> _save() async {
    if (_saving) return;

    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Имя не может быть пустым')),
      );
      return;
    }
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Имя должно быть минимум 2 символа')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final updated = await widget.profileApi.updateMe(
        displayName: name,
        status: _status.text.trim(),
      );
      if (!mounted) return;
      setState(() => _me = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено ✅')),
      );
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (!mounted) return;
      final msg = userMessageFromError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_saving) return;

    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );

    if (!mounted || res == null || res.files.isEmpty) return;

    final f = res.files.first;
    final path = f.path;
    if (path == null || path.isEmpty) return;

    setState(() => _saving = true);
    try {
      final updated = await widget.profileApi.uploadAvatar(
        filePath: path,
        fileName: f.name,
      );
      if (!mounted) return;
      setState(() => _me = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Аватар обновлён ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = userMessageFromError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _header() {
    final cs = Theme.of(context).colorScheme;
    final avatarUrl = _avatarUrlWithToken();

    final displayName = (_me?['displayName'] ?? '').toString().trim();
    final email = (_me?['email'] ?? '').toString().trim();
    final status = (_me?['status'] ?? '').toString().trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          InkWell(
            onTap: _saving ? null : _pickAndUploadAvatar,
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: 34,
              backgroundColor: cs.surfaceContainerHighest,
              backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
              child: avatarUrl == null
                  ? Icon(Icons.person_rounded, size: 34, color: cs.onSurfaceVariant)
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName.isEmpty ? 'Профиль' : displayName,
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
                if (status.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
                    ),
                    child: Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Сменить аватар',
            onPressed: _saving ? null : _pickAndUploadAvatar,
            icon: const Icon(Icons.image_outlined),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            children: [
              _header(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Имя',
                        prefixIcon: const Icon(Icons.badge_outlined),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withOpacity(0.65),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _status,
                      maxLength: 160,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Статус',
                        prefixIcon: const Icon(Icons.format_quote_rounded),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withOpacity(0.65),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Подсказка: статус видно другим участникам проекта',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _saving
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Text('Сохранить'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
