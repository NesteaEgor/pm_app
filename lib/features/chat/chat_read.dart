class ChatRead {
  final String projectId;
  final String userId;
  final String? lastReadMessageId;

  /// Время сообщения, до которого прочитано (createdAt этого message)
  final DateTime? lastReadMessageAt;

  /// Время фиксации прочтения (когда юзер отметил read)
  final DateTime lastReadAt;

  ChatRead({
    required this.projectId,
    required this.userId,
    required this.lastReadMessageId,
    required this.lastReadMessageAt,
    required this.lastReadAt,
  });

  factory ChatRead.fromJson(Map<String, dynamic> json) {
    DateTime? opt(String k) => json[k] == null ? null : DateTime.parse(json[k] as String);

    return ChatRead(
      projectId: json['projectId'] as String,
      userId: json['userId'] as String,
      lastReadMessageId: json['lastReadMessageId']?.toString(),
      lastReadMessageAt: opt('lastReadMessageAt'),
      lastReadAt: DateTime.parse(json['lastReadAt'] as String),
    );
  }
}
