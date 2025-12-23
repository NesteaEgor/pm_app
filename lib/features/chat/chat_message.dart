enum ChatSendStatus { sent, sending }

class ChatAttachment {
  final String id;
  final String fileName;
  final String? url;
  final int? size;
  final String? contentType;

  ChatAttachment({
    required this.id,
    required this.fileName,
    required this.url,
    required this.size,
    required this.contentType,
  });

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    int? toInt(dynamic v) => v == null ? null : (v as num).toInt();

    return ChatAttachment(
      id: json['id']?.toString() ?? '',
      fileName: (json['fileName'] ?? json['name'] ?? 'file').toString(),
      url: json['url']?.toString(),
      size: toInt(json['size']),
      contentType: json['contentType']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    if (url != null) 'url': url,
    if (size != null) 'size': size,
    if (contentType != null) 'contentType': contentType,
  };
}

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

  // --- new ---
  final List<ChatAttachment> attachments;
  final Map<String, int> reactions; // emoji -> count
  final Set<String> myReactions; // emojis I reacted with

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
    required this.attachments,
    required this.reactions,
    required this.myReactions,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    DateTime? parseOpt(String k) => json[k] == null ? null : DateTime.parse(json[k] as String);

    // attachments
    final atts = <ChatAttachment>[];
    final rawAtt = json['attachments'];
    if (rawAtt is List) {
      for (final x in rawAtt) {
        if (x is Map) atts.add(ChatAttachment.fromJson(Map<String, dynamic>.from(x)));
      }
    }

    // reactions
    final rx = <String, int>{};
    final rawRx = json['reactions'];
    if (rawRx is Map) {
      for (final e in rawRx.entries) {
        rx[e.key.toString()] = (e.value as num).toInt();
      }
    }

    // myReactions
    final my = <String>{};
    final rawMy = json['myReactions'];
    if (rawMy is List) {
      for (final x in rawMy) {
        my.add(x.toString());
      }
    }

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
      attachments: atts,
      reactions: rx,
      myReactions: my,
    );
  }

  factory ChatMessage.pending({
    required String clientMessageId,
    required String projectId,
    required String authorId,
    required String authorName,
    required String text,
    required List<ChatAttachment> attachments,
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
      attachments: attachments,
      reactions: const {},
      myReactions: const {},
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
    List<ChatAttachment>? attachments,
    Map<String, int>? reactions,
    Set<String>? myReactions,
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
      attachments: attachments ?? this.attachments,
      reactions: reactions ?? this.reactions,
      myReactions: myReactions ?? this.myReactions,
    );
  }
}
