import '../../core/api/api_client.dart';
import 'project_member.dart';

class ProjectMembersApi {
  final ApiClient api;
  ProjectMembersApi({required this.api});

  Future<List<ProjectMember>> list(String projectId) async {
    final res = await api.dio.get('/api/projects/$projectId/members');
    final data = (res.data as List).cast<dynamic>();
    return data
        .map((e) => ProjectMember.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> add({required String projectId, required String email}) async {
    await api.dio.post(
      '/api/projects/$projectId/members',
      data: {'email': email},
    );
  }

  Future<void> remove({required String projectId, required String userId}) async {
    await api.dio.delete('/api/projects/$projectId/members/$userId');
  }
}
