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
  final String projectId;
  final String title;
  final String? description;
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime? deadline;

  Task({
    required this.id,
    required this.projectId,
    required this.title,
    required this.status,
    required this.createdAt,
    this.description,
    this.deadline,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      status: taskStatusFromString(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      deadline: json['deadline'] == null ? null : DateTime.parse(json['deadline'] as String),
    );
  }
}
