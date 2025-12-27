import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не загрузилось: $e')),
      );
    }
  }

  String? _avatarUrlWithToken() {
    final raw = (_me?['avatarUrl'] ?? '').toString().trim();
    if (raw.isEmpty) return null;

    const base = 'http://127.0.0.1:8080';
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
    setState(() => _saving = true);

    try {
      final updated = await widget.profileApi.updateMe(
        displayName: _name.text.trim(),
        status: _status.text.trim(),
      );
      if (!mounted) return;
      setState(() => _me = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не сохранилось: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не загрузилось: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final avatarUrl = _avatarUrlWithToken();

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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: InkWell(
              onTap: _saving ? null : _pickAndUploadAvatar,
              child: CircleAvatar(
                radius: 44,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
                child: avatarUrl == null ? const Icon(Icons.person, size: 42) : null,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton.icon(
              onPressed: _saving ? null : _pickAndUploadAvatar,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Сменить аватар'),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Имя',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _status,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'Статус',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}
