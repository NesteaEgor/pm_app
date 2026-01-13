import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/storage/token_storage.dart';
import '../members/project_members_api.dart';

import 'create_task_dialog.dart';
import 'edit_task_dialog.dart';
import 'task.dart';
import 'tasks_api.dart';

import '../comments/comments_api.dart';
import '../comments/comments_screen.dart';

import 'package:dio/dio.dart';
import 'task_report_api.dart';
import 'task_report_file.dart';

enum TaskFilter { all, todo, inProgress, done, myReported, myAssigned }
enum TaskSortMode { deadlineAsc, createdAtDesc }

class TasksScreen extends StatefulWidget {
  final String projectId;
  final String projectName;
  final TasksApi tasksApi;
  final CommentsApi commentsApi;

  final TokenStorage tokenStorage;
  final ProjectMembersApi projectMembersApi;

  const TasksScreen({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.tasksApi,
    required this.commentsApi,
    required this.tokenStorage,
    required this.projectMembersApi,
  });

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final List<Task> _tasks = [];

  bool _loading = true;
  Object? _error;

  TaskFilter _filter = TaskFilter.all;
  TaskSortMode _sortMode = TaskSortMode.deadlineAsc;

  String? _myUserId;
  bool _iAmOwner = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final token = await widget.tokenStorage.readToken();
    _myUserId = _tryReadSubFromJwt(token);

    await _loadMyRole();
    await _load();
  }

  Future<void> _loadMyRole() async {
    try {
      if (_myUserId == null) return;
      final members = await widget.projectMembersApi.list(widget.projectId);
      final me = members.where((m) => m.userId == _myUserId).toList();
      final owner = me.isNotEmpty && me.first.role == 'OWNER';
      if (mounted) setState(() => _iAmOwner = owner);
    } catch (_) {
      if (mounted) setState(() => _iAmOwner = false);
    }
  }

  String? _tryReadSubFromJwt(String? token) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length < 2) return null;

    try {
      final payload = parts[1];
      final norm = base64.normalize(payload);
      final jsonStr = utf8.decode(base64Url.decode(norm));
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return map['sub']?.toString();
    } catch (_) {
      return null;
    }
  }

  String? _statusParam() {
    switch (_filter) {
      case TaskFilter.all:
      case TaskFilter.myReported:
      case TaskFilter.myAssigned:
        return null;
      case TaskFilter.todo:
        return 'TODO';
      case TaskFilter.inProgress:
        return 'IN_PROGRESS';
      case TaskFilter.done:
        return 'DONE';
    }
  }

  List<Task> _applyLocalFilter(List<Task> list) {
    final me = _myUserId;
    if (me == null || me.isEmpty) {
      if (_filter == TaskFilter.myReported || _filter == TaskFilter.myAssigned) {
        return <Task>[];
      }
      return list;
    }

    switch (_filter) {
      case TaskFilter.myReported:
        return list.where((t) => t.reporterId == me).toList();
      case TaskFilter.myAssigned:
        return list.where((t) => t.assigneeId == me).toList();
      default:
        return list;
    }
  }

  void _applyLocalSort(List<Task> list) {
    if (_sortMode == TaskSortMode.createdAtDesc) {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return;
    }

    final farFuture = DateTime(9999, 12, 31, 23, 59);
    DateTime da(Task t) => t.deadline?.toLocal() ?? farFuture;

    list.sort((a, b) {
      final c = da(a).compareTo(da(b));
      if (c != 0) return c;
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }

    try {
      final status = _statusParam();
      final sortParam = _sortMode == TaskSortMode.deadlineAsc ? 'deadline' : null;

      final listRaw = await widget.tasksApi.list(
        widget.projectId,
        status: status,
        sort: sortParam,
      );

      final list = _applyLocalFilter(listRaw);
      _applyLocalSort(list);

      if (!mounted) return;
      setState(() {
        _tasks
          ..clear()
          ..addAll(list);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _refresh() => _load(showSpinner: false);

  Future<void> _openCreateDialog() async {
    final created = await showDialog<Task>(
      context: context,
      builder: (_) => CreateTaskDialog(
        projectId: widget.projectId,
        tasksApi: widget.tasksApi,
        projectMembersApi: widget.projectMembersApi,
      ),
    );

    if (!mounted) return;
    if (created != null) {
      await _load(showSpinner: false);
    }
  }

  Future<void> _openEditDialog(Task t) async {
    final updated = await showDialog<Task>(
      context: context,
      builder: (_) => EditTaskDialog(
        projectId: widget.projectId,
        task: t,
        tasksApi: widget.tasksApi,
        projectMembersApi: widget.projectMembersApi,
      ),
    );

    if (!mounted) return;
    if (updated != null) {
      await _load(showSpinner: false);
    }
  }

  void _openComments(Task t) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => CommentsScreen(
          projectId: widget.projectId,
          taskId: t.id,
          taskTitle: t.title,
          commentsApi: widget.commentsApi,
          tokenStorage: widget.tokenStorage,
          projectMembersApi: widget.projectMembersApi,
        ),
      ),
    );
  }

  TaskStatus _nextStatus(TaskStatus s) {
    switch (s) {
      case TaskStatus.TODO:
        return TaskStatus.IN_PROGRESS;
      case TaskStatus.IN_PROGRESS:
        return TaskStatus.DONE;
      case TaskStatus.DONE:
        return TaskStatus.TODO;
    }
  }

  String _fmtDeadline(DateTime d) {
    final local = d.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$day $hh:$mm';
  }

  Future<bool> _confirmDelete(Task t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: Text('Точно удалить "${t.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  String _filterLabel() {
    switch (_filter) {
      case TaskFilter.all:
        return 'ALL';
      case TaskFilter.todo:
        return 'TODO';
      case TaskFilter.inProgress:
        return 'IN_PROGRESS';
      case TaskFilter.done:
        return 'DONE';
      case TaskFilter.myReported:
        return 'REPORTER';
      case TaskFilter.myAssigned:
        return 'ASSIGNEE';
    }
  }

  String _sortLabel() {
    switch (_sortMode) {
      case TaskSortMode.deadlineAsc:
        return 'deadline';
      case TaskSortMode.createdAtDesc:
        return 'createdAt';
    }
  }

  String _statusShort(TaskStatus s) {
    switch (s) {
      case TaskStatus.TODO:
        return 'TODO';
      case TaskStatus.IN_PROGRESS:
        return 'IN_PROGRESS';
      case TaskStatus.DONE:
        return 'DONE';
    }
  }

  Widget _statusChip(TaskStatus s) {
    return Chip(
      label: Text(_statusShort(s)),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _metaChip(String text, {IconData? icon}) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: icon == null ? null : Icon(icon, size: 16),
      label: Text(text),
    );
  }

  Future<void> _changeStatus(Task t) async {
    try {
      final next = _nextStatus(t.status);
      await widget.tasksApi.patch(
        widget.projectId,
        t.id,
        {'status': taskStatusToString(next)},
      );
      if (!mounted) return;
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = '${_filterLabel()} • ${_sortLabel()}';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.projectName),
            const SizedBox(height: 2),
            Text(
              sub,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Отчёт PDF',
            icon: const Icon(Icons.picture_as_pdf_rounded),
            onPressed: _openReportDialog,
          ),
          PopupMenuButton<TaskFilter>(
            tooltip: 'Фильтр',
            icon: const Icon(Icons.filter_list_rounded),
            onSelected: (f) => setState(() {
              _filter = f;
              _load(showSpinner: false);
            }),
            itemBuilder: (ctx) => [
              CheckedPopupMenuItem(
                value: TaskFilter.all,
                checked: _filter == TaskFilter.all,
                child: const Text('ALL'),
              ),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(
                value: TaskFilter.todo,
                checked: _filter == TaskFilter.todo,
                child: const Text('TODO'),
              ),
              CheckedPopupMenuItem(
                value: TaskFilter.inProgress,
                checked: _filter == TaskFilter.inProgress,
                child: const Text('IN_PROGRESS'),
              ),
              CheckedPopupMenuItem(
                value: TaskFilter.done,
                checked: _filter == TaskFilter.done,
                child: const Text('DONE'),
              ),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(
                value: TaskFilter.myReported,
                checked: _filter == TaskFilter.myReported,
                child: const Text('Постановщик (я)'),
              ),
              CheckedPopupMenuItem(
                value: TaskFilter.myAssigned,
                checked: _filter == TaskFilter.myAssigned,
                child: const Text('Исполнитель (я)'),
              ),
            ],
          ),
          PopupMenuButton<TaskSortMode>(
            tooltip: 'Сортировка',
            icon: const Icon(Icons.sort_rounded),
            onSelected: (m) => setState(() {
              _sortMode = m;
              _load(showSpinner: false);
            }),
            itemBuilder: (ctx) => [
              CheckedPopupMenuItem(
                value: TaskSortMode.deadlineAsc,
                checked: _sortMode == TaskSortMode.deadlineAsc,
                child: const Text('По дедлайну (asc)'),
              ),
              CheckedPopupMenuItem(
                value: TaskSortMode.createdAtDesc,
                checked: _sortMode == TaskSortMode.createdAtDesc,
                child: const Text('По созданию (newest)'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateDialog,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? ListView(
          children: const [
            SizedBox(height: 220),
            Center(child: CircularProgressIndicator()),
          ],
        )
            : _error != null
            ? ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 80),
            Text('Ошибка:\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Center(
              child: FilledButton(
                onPressed: _refresh,
                child: const Text('Повторить'),
              ),
            ),
          ],
        )
            : _tasks.isEmpty
            ? ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            SizedBox(height: 80),
            Center(
              child: Text(
                'Пока нет задач.\nНажми + чтобы создать.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        )
            : ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: _tasks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final t = _tasks[i];

            final me = _myUserId;
            final isReporter = (me != null && me.isNotEmpty && t.reporterId == me);
            final isAssignee = (me != null && me.isNotEmpty && t.assigneeId == me);

            final canAll = _iAmOwner || isReporter;
            final canEdit = canAll;
            final canDelete = canAll;
            final canChangeStatus = _iAmOwner || isReporter || isAssignee;

            final desc = (t.description ?? '').trim();
            final rep = (t.reporterName ?? '').trim();
            final ass = (t.assigneeName ?? '').trim();

            final chips = <Widget>[
              _statusChip(t.status),
              if (t.deadline != null) _metaChip(_fmtDeadline(t.deadline!), icon: Icons.schedule_rounded),
              if (rep.isNotEmpty) _metaChip(rep, icon: Icons.person_outline_rounded),
              if (ass.isNotEmpty) _metaChip(ass, icon: Icons.assignment_ind_outlined),
            ];

            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: canEdit ? () => _openEditDialog(t) : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              t.title,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Действия',
                            onSelected: (v) async {
                              if (v == 'comments') {
                                _openComments(t);
                                return;
                              }
                              if (v == 'status') {
                                await _changeStatus(t);
                                return;
                              }
                              if (v == 'delete') {
                                final ok = await _confirmDelete(t);
                                if (!ok) return;
                                try {
                                  await widget.tasksApi.delete(widget.projectId, t.id);
                                  if (!mounted) return;
                                  await _load(showSpinner: false);
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Ошибка: $e')),
                                  );
                                }
                                return;
                              }
                              if (v == 'edit') {
                                await _openEditDialog(t);
                                return;
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'comments',
                                child: ListTile(
                                  leading: Icon(Icons.chat_bubble_outline_rounded),
                                  title: Text('Комментарии'),
                                ),
                              ),
                              if (canEdit)
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    leading: Icon(Icons.edit_outlined),
                                    title: Text('Редактировать'),
                                  ),
                                ),
                              if (canChangeStatus)
                                const PopupMenuItem(
                                  value: 'status',
                                  child: ListTile(
                                    leading: Icon(Icons.autorenew_rounded),
                                    title: Text('Сменить статус'),
                                  ),
                                ),
                              if (canDelete) ...[
                                const PopupMenuDivider(),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: Icon(Icons.delete_outline_rounded, color: cs.error),
                                    title: Text('Удалить', style: TextStyle(color: cs.error)),
                                  ),
                                ),
                              ],
                            ],
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.more_vert_rounded),
                            ),
                          ),
                        ],
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          desc,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: chips,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
  TaskReportApi _reportApi() => TaskReportApi(widget.tasksApi.api.dio);

  Future<void> _openReportDialog() async {
    String? role;   // null | creator | assignee
    String? status; // null | TODO | IN_PROGRESS | DONE
    bool loading = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) => AlertDialog(
          title: const Text('Отчёт по задачам'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String?>(
                value: role,
                decoration: const InputDecoration(labelText: 'Роль'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Все')),
                  DropdownMenuItem(value: 'creator', child: Text('Я постановщик')),
                  DropdownMenuItem(value: 'assignee', child: Text('Я исполнитель')),
                ],
                onChanged: loading ? null : (v) => role = v,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: status,
                decoration: const InputDecoration(labelText: 'Статус'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Все')),
                  DropdownMenuItem(value: 'TODO', child: Text('TODO')),
                  DropdownMenuItem(value: 'IN_PROGRESS', child: Text('IN_PROGRESS')),
                  DropdownMenuItem(value: 'DONE', child: Text('DONE')),
                ],
                onChanged: loading ? null : (v) => status = v,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                setSB(() => loading = true);
                try {
                  final bytes = await _reportApi().downloadReport(
                    projectId: widget.projectId,
                    role: role,
                    status: status,
                  );

                  await saveAndOpenPdf(
                    bytes,
                    fileName: 'task-report-${widget.projectName}',
                  );

                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Не удалось скачать отчёт: $e')),
                  );
                } finally {
                  setSB(() => loading = false);
                }
              },
              child: loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Скачать PDF'),
            ),
          ],
        ),
      ),
    );
  }

}
