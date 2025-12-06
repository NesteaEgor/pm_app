import '../../core/api/api_client.dart';
import 'comment.dart';

class CommentsApi {
  final ApiClient api;
  CommentsApi({required this.api});

  Future<List<Comment>> list({
    required String projectId,
    required String taskId,
  }) async {
    final res = await api.dio.get('/api/projects/$projectId/tasks/$taskId/comments');
    final data = (res.data as List).cast<dynamic>();
    return data.map((e) => Comment.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<Comment> create({
    required String projectId,
    required String taskId,
    required String text,
  }) async {
    final res = await api.dio.post(
      '/api/projects/$projectId/tasks/$taskId/comments',
      data: {'text': text},
    );
    return Comment.fromJson(Map<String, dynamic>.from(res.data));
  }

  Future<void> delete({
    required String projectId,
    required String taskId,
    required String commentId,
  }) async {
    await api.dio.delete('/api/projects/$projectId/tasks/$taskId/comments/$commentId');
  }
}
