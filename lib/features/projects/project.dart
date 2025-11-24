class Project {
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;

  Project({
    required this.id,
    required this.name,
    required this.createdAt,
    this.description,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
