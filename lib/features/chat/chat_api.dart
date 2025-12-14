import '../../core/api/api_client.dart';
import 'chat_message.dart';
import 'chat_read.dart';

class ChatApi {
  final ApiClient api;
  ChatApi({required this.api});

  Future<List<ChatMessage>> history({
    required String projectId,
    DateTime? before,
    int limit = 30,
  }) async {
    final qp = <String, dynamic>{'limit': limit};
    if (before != null) {
      qp['before'] = before.toUtc().toIso8601String();
    }

    final res = await api.dio.get(
      '/api/projects/$projectId/messages',
      queryParameters: qp,
    );

    final data = (res.data as List).cast<dynamic>();
    return data.map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<ChatRead>> reads({required String projectId}) async {
    final res = await api.dio.get('/api/projects/$projectId/reads');
    final data = (res.data as List).cast<dynamic>();
    return data.map((e) => ChatRead.fromJson(Map<String, dynamic>.from(e))).toList();
  }
}
