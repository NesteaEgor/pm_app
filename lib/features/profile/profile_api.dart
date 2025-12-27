import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';

class ProfileApi {
  final ApiClient api;
  ProfileApi({required this.api});

  Future<Map<String, dynamic>> me() async {
    final res = await api.dio.get('/api/me');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> updateMe({
    String? displayName,
    String? status,
  }) async {
    final data = <String, dynamic>{};
    if (displayName != null) data['displayName'] = displayName;
    if (status != null) data['status'] = status;

    final res = await api.dio.patch('/api/me/profile', data: data);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> uploadAvatar({
    required String filePath,
    required String fileName,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });

    final res = await api.dio.post(
      '/api/me/avatar',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );

    return Map<String, dynamic>.from(res.data as Map);
  }

  // NEW: чужой профиль (read-only)
  Future<Map<String, dynamic>> userById(String userId) async {
    final res = await api.dio.get('/api/users/$userId');
    return Map<String, dynamic>.from(res.data as Map);
  }
}
