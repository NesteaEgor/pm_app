class Comment {
  final String id;
  final String taskId;
  final String authorId;
  final String text;
  final DateTime createdAt;

  Comment({
    required this.id,
    required this.taskId,
    required this.authorId,
    required this.text,
    required this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'] as String,
      taskId: json['taskId'] as String,
      authorId: json['authorId'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
