import '../../core/api/api_client.dart';
import '../../core/storage/token_storage.dart';

class AuthApi {
  final ApiClient api;
  final TokenStorage tokenStorage;

  AuthApi({required this.api, required this.tokenStorage});

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final res = await api.dio.post('/api/auth/register', data: {
      'email': email,
      'password': password,
      'displayName': displayName,
    });

    final token = res.data['accessToken'] as String;
    await tokenStorage.saveToken(token);
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    final res = await api.dio.post('/api/auth/login', data: {
      'email': email,
      'password': password,
    });

    final token = res.data['accessToken'] as String;
    await tokenStorage.saveToken(token);
  }

  Future<void> logout() => tokenStorage.clear();

  Future<Map<String, dynamic>> me() async {
    final res = await api.dio.get('/api/me');
    return Map<String, dynamic>.from(res.data);
  }
}
