enum TaskStatus { TODO, IN_PROGRESS, DONE }

TaskStatus taskStatusFromString(String s) {
  switch (s) {
    case 'TODO':
      return TaskStatus.TODO;
    case 'IN_PROGRESS':
      return TaskStatus.IN_PROGRESS;
    case 'DONE':
      return TaskStatus.DONE;
    default:
      return TaskStatus.TODO;
  }
}

String taskStatusToString(TaskStatus s) {
  switch (s) {
    case TaskStatus.TODO:
      return 'TODO';
    case TaskStatus.IN_PROGRESS:
      return 'IN_PROGRESS';
    case TaskStatus.DONE:
      return 'DONE';
  }
}

class Task {
  final String id;
  final String title;
  final String? description;

  final TaskStatus status;

  final DateTime? deadline; // UTC в модели, UI показывает toLocal()
  final DateTime createdAt; // UTC в модели

  // NEW: постановщик/исполнитель
  final String? reporterId;
  final String? reporterName;

  final String? assigneeId;
  final String? assigneeName;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.deadline,
    required this.createdAt,
    required this.reporterId,
    required this.reporterName,
    required this.assigneeId,
    required this.assigneeName,
  });

  static String? _readId(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  static String? _readName(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static DateTime? _readDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toUtc();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toUtc();
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    // reporter может быть плоским или объектом
    final reporterObj = json['reporter'] is Map ? Map<String, dynamic>.from(json['reporter']) : null;
    final assigneeObj = json['assignee'] is Map ? Map<String, dynamic>.from(json['assignee']) : null;

    final reporterId = _readId(
      json['reporterId'] ??
          json['creatorId'] ??
          reporterObj?['id'] ??
          reporterObj?['userId'],
    );

    final reporterName = _readName(
      json['reporterName'] ??
          json['creatorName'] ??
          reporterObj?['displayName'] ??
          reporterObj?['name'],
    );

    final assigneeId = _readId(
      json['assigneeId'] ??
          json['executorId'] ??
          assigneeObj?['id'] ??
          assigneeObj?['userId'],
    );

    final assigneeName = _readName(
      json['assigneeName'] ??
          json['executorName'] ??
          assigneeObj?['displayName'] ??
          assigneeObj?['name'],
    );

    return Task(
      id: json['id'].toString(),
      title: (json['title'] ?? '').toString(),
      description: _readName(json['description']),
      status: taskStatusFromString((json['status'] ?? 'TODO').toString()),
      deadline: _readDate(json['deadline']),
      createdAt: _readDate(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      reporterId: reporterId,
      reporterName: reporterName,
      assigneeId: assigneeId,
      assigneeName: assigneeName,
    );
  }

  Task copyWith({
    String? id,
    String? title,
    String? description,
    TaskStatus? status,
    DateTime? deadline,
    DateTime? createdAt,
    String? reporterId,
    String? reporterName,
    String? assigneeId,
    String? assigneeName,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      deadline: deadline ?? this.deadline,
      createdAt: createdAt ?? this.createdAt,
      reporterId: reporterId ?? this.reporterId,
      reporterName: reporterName ?? this.reporterName,
      assigneeId: assigneeId ?? this.assigneeId,
      assigneeName: assigneeName ?? this.assigneeName,
    );
  }
}
