class ChatMessage {
  final String id;
  final String projectId;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.projectId,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      authorId: json['authorId'] as String,
      authorName: (json['authorName'] ?? 'Unknown') as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
