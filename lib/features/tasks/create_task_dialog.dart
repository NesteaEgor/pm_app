import 'package:flutter/material.dart';

import '../members/project_member.dart';
import '../members/project_members_api.dart';

import 'task.dart';
import 'tasks_api.dart';

class CreateTaskDialog extends StatefulWidget {
  final String projectId;
  final TasksApi tasksApi;
  final ProjectMembersApi projectMembersApi;

  const CreateTaskDialog({
    super.key,
    required this.projectId,
    required this.tasksApi,
    required this.projectMembersApi,
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

  List<ProjectMember> _members = [];
  bool _membersLoading = true;

  String? _assigneeId;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _membersLoading = true;
      _error = null;
    });
    try {
      final list = await widget.projectMembersApi.list(widget.projectId);
      list.sort((a, b) => a.displayName.compareTo(b.displayName));
      if (!mounted) return;
      setState(() {
        _members = list;
        _membersLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _membersLoading = false;
        _error = 'Не удалось загрузить участников: $e';
      });
    }
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

  List<DropdownMenuItem<String?>> _assigneeItems() {
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Не назначен'),
      ),
    ];

    for (final m in _members) {
      items.add(
        DropdownMenuItem<String?>(
          value: m.userId,
          child: Text(m.displayName, overflow: TextOverflow.ellipsis),
        ),
      );
    }

    return items;
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
        assigneeId: _assigneeId,
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
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Новая задача'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Название',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _desc,
                keyboardType: TextInputType.multiline,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Описание',
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String?>(
                value: _assigneeId,
                decoration: const InputDecoration(labelText: 'Исполнитель'),
                items: _membersLoading ? null : _assigneeItems(),
                onChanged: (_loading || _membersLoading) ? null : (v) => setState(() => _assigneeId = v),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Дедлайн',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    if (_deadline == null)
                      Chip(
                        label: Text(
                          'не задан',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        side: BorderSide(color: cs.outlineVariant),
                        backgroundColor: cs.surfaceContainerLowest,
                      )
                    else
                      InputChip(
                        label: Text(_fmt(_deadline!)),
                        onDeleted: _loading ? null : () => setState(() => _deadline = null),
                      ),
                    TextButton.icon(
                      onPressed: _loading ? null : _pickDeadline,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(_deadline == null ? 'Выбрать' : 'Изменить'),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(color: cs.error),
                  ),
                ),
              ],
            ],
          ),
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
