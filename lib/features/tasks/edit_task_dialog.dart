import 'package:flutter/material.dart';

import '../members/project_member.dart';
import '../members/project_members_api.dart';

import 'task.dart';
import 'tasks_api.dart';

class EditTaskDialog extends StatefulWidget {
  final String projectId;
  final Task task;
  final TasksApi tasksApi;
  final ProjectMembersApi projectMembersApi;

  const EditTaskDialog({
    super.key,
    required this.projectId,
    required this.task,
    required this.tasksApi,
    required this.projectMembersApi,
  });

  @override
  State<EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<EditTaskDialog> {
  late final TextEditingController _title;
  late final TextEditingController _desc;

  bool _loading = false;
  String? _error;

  DateTime? _deadlineLocal;
  late TaskStatus _status;

  List<ProjectMember> _members = [];
  bool _membersLoading = true;

  String? _assigneeId;

  @override
  void initState() {
    super.initState();

    _title = TextEditingController(text: widget.task.title);
    _desc = TextEditingController(text: widget.task.description ?? '');
    _deadlineLocal = widget.task.deadline?.toLocal();
    _status = widget.task.status;
    _assigneeId = widget.task.assigneeId;

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
    final base = _deadlineLocal ?? now;

    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null) return;

    setState(() {
      _deadlineLocal = DateTime(date.year, date.month, date.day, time.hour, time.minute);
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

  Future<void> _save() async {
    final newTitle = _title.text.trim();
    final newDesc = _desc.text.trim();

    if (newTitle.isEmpty) {
      setState(() => _error = 'Название не может быть пустым');
      return;
    }

    final patch = <String, dynamic>{};

    if (newTitle != widget.task.title) patch['title'] = newTitle;

    final oldDesc = (widget.task.description ?? '').trim();
    if (newDesc != oldDesc) patch['description'] = newDesc;

    if (_status != widget.task.status) {
      patch['status'] = taskStatusToString(_status);
    }

    final oldDeadline = widget.task.deadline?.toLocal();
    final sameDeadline =
        (oldDeadline == null && _deadlineLocal == null) ||
            (oldDeadline != null &&
                _deadlineLocal != null &&
                oldDeadline.isAtSameMomentAs(_deadlineLocal!));

    if (!sameDeadline) {
      patch['deadline'] = _deadlineLocal;
    }

    if (_assigneeId != widget.task.assigneeId) {
      patch['assigneeId'] = _assigneeId;
    }

    if (patch.isEmpty) {
      if (!mounted) return;
      Navigator.of(context).pop<Task>(widget.task);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final updated = await widget.tasksApi.patch(
        widget.projectId,
        widget.task.id,
        patch,
      );
      if (!mounted) return;
      Navigator.of(context).pop<Task>(updated);
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
      title: const Text('Редактировать задачу'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Название'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _desc,
                keyboardType: TextInputType.multiline,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Описание'),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<TaskStatus>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Статус'),
                items: TaskStatus.values
                    .map(
                      (s) => DropdownMenuItem(
                    value: s,
                    child: Text(taskStatusToString(s)),
                  ),
                )
                    .toList(),
                onChanged: _loading ? null : (v) => setState(() => _status = v ?? _status),
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
                    if (_deadlineLocal == null)
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
                        label: Text(_fmt(_deadlineLocal!)),
                        onDeleted: _loading ? null : () => setState(() => _deadlineLocal = null),
                      ),
                    TextButton.icon(
                      onPressed: _loading ? null : _pickDeadline,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(_deadlineLocal == null ? 'Выбрать' : 'Изменить'),
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
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
