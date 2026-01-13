import 'package:flutter/material.dart';
import '../../core/api/api_error_mapper.dart';
import 'project.dart';
import 'projects_api.dart';

class CreateProjectDialog extends StatefulWidget {
  final ProjectsApi projectsApi;

  const CreateProjectDialog({super.key, required this.projectsApi});

  @override
  State<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<CreateProjectDialog> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final desc = _desc.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Название не может быть пустым')),
      );
      return;
    }

    if (name.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Название должно быть минимум 3 символа')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final created = await widget.projectsApi.create(
        name: name,
        description: desc.isEmpty ? null : desc,
      );

      if (!mounted) return;
      Navigator.of(context).pop<Project>(created);
    } catch (e) {
      if (!mounted) return;
      final msg = userMessageFromError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый проект'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Название',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Описание',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Text('Создать'),
        ),
      ],
    );
  }
}
