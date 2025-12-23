class ChatRead {
  final String projectId;
  final String userId;
  final String? userName;
  final String? lastReadMessageId;

  final DateTime? lastReadMessageAt;
  final DateTime lastReadAt;

  ChatRead({
    required this.projectId,
    required this.userId,
    required this.userName,
    required this.lastReadMessageId,
    required this.lastReadMessageAt,
    required this.lastReadAt,
  });

  factory ChatRead.fromJson(Map<String, dynamic> json) {
    DateTime? opt(String k) => json[k] == null ? null : DateTime.parse(json[k] as String);

    return ChatRead(
      projectId: json['projectId'] as String,
      userId: json['userId'] as String,
      userName: json['userName']?.toString(),
      lastReadMessageId: json['lastReadMessageId']?.toString(),
      lastReadMessageAt: opt('lastReadMessageAt'),
      lastReadAt: DateTime.parse(json['lastReadAt'] as String),
    );
  }
}
