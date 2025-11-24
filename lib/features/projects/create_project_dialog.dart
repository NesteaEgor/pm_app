import 'package:flutter/material.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать проект: $e')),
      );
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0B1220),
      title: const Text('Новый проект', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Название',
              labelStyle: TextStyle(color: Colors.white70),
            ),
          ),
          TextField(
            controller: _desc,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Описание',
              labelStyle: TextStyle(color: Colors.white70),
            ),
          ),
        ],
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
