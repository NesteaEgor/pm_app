import '../../core/api/api_client.dart';
import 'project.dart';

class ProjectsApi {
  final ApiClient api;
  ProjectsApi({required this.api});

  Future<List<Project>> list() async {
    final res = await api.dio.get('/api/projects');
    final data = (res.data as List).cast<dynamic>();
    return data.map((e) => Project.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<Project> create({required String name, String? description}) async {
    final res = await api.dio.post('/api/projects', data: {
      'name': name,
      'description': description,
    });
    return Project.fromJson(Map<String, dynamic>.from(res.data));
  }

  Future<void> delete(String projectId) async {
    await api.dio.delete('/api/projects/$projectId');
  }
}
