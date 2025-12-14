enum ChatSendStatus { sent, sending }

class ChatMessage {
  final String? id;
  final String projectId;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime createdAt;

  final String? clientMessageId;

  final DateTime? editedAt;
  final DateTime? deletedAt;

  final String? eventType; // CREATED / UPDATED / DELETED
  final ChatSendStatus status;

  bool get isDeleted => deletedAt != null;

  ChatMessage({
    required this.id,
    required this.projectId,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAt,
    required this.clientMessageId,
    required this.editedAt,
    required this.deletedAt,
    required this.eventType,
    required this.status,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    DateTime? parseOpt(String k) => json[k] == null ? null : DateTime.parse(json[k] as String);

    return ChatMessage(
      id: json['id']?.toString(),
      projectId: json['projectId'] as String,
      authorId: json['authorId'] as String,
      authorName: (json['authorName'] ?? 'Unknown') as String,
      text: (json['text'] ?? '') as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      clientMessageId: json['clientMessageId']?.toString(),
      editedAt: parseOpt('editedAt'),
      deletedAt: parseOpt('deletedAt'),
      eventType: json['eventType']?.toString(),
      status: ChatSendStatus.sent,
    );
  }

  factory ChatMessage.pending({
    required String clientMessageId,
    required String projectId,
    required String authorId,
    required String authorName,
    required String text,
  }) {
    return ChatMessage(
      id: null,
      projectId: projectId,
      authorId: authorId,
      authorName: authorName,
      text: text,
      createdAt: DateTime.now(),
      clientMessageId: clientMessageId,
      editedAt: null,
      deletedAt: null,
      eventType: 'CREATED',
      status: ChatSendStatus.sending,
    );
  }

  ChatMessage copyWith({
    String? id,
    String? text,
    DateTime? createdAt,
    DateTime? editedAt,
    DateTime? deletedAt,
    ChatSendStatus? status,
    String? authorName,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      projectId: projectId,
      authorId: authorId,
      authorName: authorName ?? this.authorName,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      clientMessageId: clientMessageId,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      eventType: eventType,
      status: status ?? this.status,
    );
  }
}
