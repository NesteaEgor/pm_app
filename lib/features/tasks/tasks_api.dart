import '../../core/api/api_client.dart';
import 'task.dart';

class TasksApi {
  final ApiClient api;
  TasksApi({required this.api});

  Future<List<Task>> list(String projectId, {String? status, String? sort}) async {
    final qp = <String, dynamic>{};
    if (status != null) qp['status'] = status;
    if (sort != null) qp['sort'] = sort;

    final res = await api.dio.get(
      '/api/projects/$projectId/tasks',
      queryParameters: qp,
    );

    final data = (res.data as List).cast<dynamic>();
    return data.map((e) => Task.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<Task> create(
      String projectId, {
        required String title,
        String? description,
        DateTime? deadline,
      }) async {
    final payload = <String, dynamic>{
      'title': title,
      'description': description,
    };

    if (deadline != null) {
      payload['deadline'] = deadline.toUtc().toIso8601String();
    }

    final res = await api.dio.post(
      '/api/projects/$projectId/tasks',
      data: payload,
    );
    return Task.fromJson(Map<String, dynamic>.from(res.data));
  }

  Future<Task> patch(String projectId, String taskId, Map<String, dynamic> patch) async {
    // Нормализуем PATCH:
    // - DateTime -> ISO UTC string
    // - null оставляем null (для удаления дедлайна)
    final normalized = <String, dynamic>{};

    patch.forEach((key, value) {
      if (value is DateTime) {
        normalized[key] = value.toUtc().toIso8601String();
      } else {
        normalized[key] = value;
      }
    });

    final res = await api.dio.patch(
      '/api/projects/$projectId/tasks/$taskId',
      data: normalized,
    );
    return Task.fromJson(Map<String, dynamic>.from(res.data));
  }

  Future<void> delete(String projectId, String taskId) async {
    await api.dio.delete('/api/projects/$projectId/tasks/$taskId');
  }
}
