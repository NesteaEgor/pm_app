import 'package:flutter/material.dart';
import 'task.dart';
import 'tasks_api.dart';

class CreateTaskDialog extends StatefulWidget {
  final String projectId;
  final TasksApi tasksApi;

  const CreateTaskDialog({
    super.key,
    required this.projectId,
    required this.tasksApi,
  });

  @override
  State<CreateTaskDialog> createState() => _CreateTaskDialogState();
}

class _CreateTaskDialogState extends State<CreateTaskDialog> {
  final _title = TextEditingController();
  final _desc = TextEditingController();

  bool _loading = false;
  String? _error;

  DateTime? _deadline;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  String _fmt(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _deadline != null ? TimeOfDay.fromDateTime(_deadline!) : TimeOfDay.now(),
    );
    if (time == null) return;

    setState(() {
      _deadline = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final desc = _desc.text.trim();

    if (title.isEmpty) {
      setState(() => _error = 'Название не может быть пустым');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final created = await widget.tasksApi.create(
        widget.projectId,
        title: title,
        description: desc.isEmpty ? null : desc,
        deadline: _deadline,
      );

      if (!mounted) return;
      Navigator.of(context).pop<Task>(created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Ошибка: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новая задача'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Название'),
          ),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: 'Описание'),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Text(
                  _deadline == null ? 'Дедлайн: не задан' : 'Дедлайн: ${_fmt(_deadline!)}',
                ),
              ),
              TextButton(
                onPressed: _loading ? null : _pickDeadline,
                child: const Text('Выбрать'),
              ),
              if (_deadline != null)
                IconButton(
                  tooltip: 'Убрать дедлайн',
                  onPressed: _loading ? null : () => setState(() => _deadline = null),
                  icon: const Icon(Icons.clear),
                ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
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
