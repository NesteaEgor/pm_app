class ProjectMember {
  final String userId;
  final String email;
  final String displayName;
  final String role; // OWNER / MEMBER
  final DateTime addedAt;

  ProjectMember({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.role,
    required this.addedAt,
  });

  bool get isOwner => role == 'OWNER';

  factory ProjectMember.fromJson(Map<String, dynamic> json) {
    return ProjectMember(
      userId: json['userId'] as String,
      email: (json['email'] ?? '') as String,
      displayName: (json['displayName'] ?? '') as String,
      role: (json['role'] ?? 'MEMBER') as String,
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }
}
