import 'package:dio/dio.dart';
import '../storage/token_storage.dart';

class ApiClient {
  final Dio dio;
  final TokenStorage tokenStorage;

  /// Вызывается, когда сервер вернул 401 (токен невалиден/протух).
  /// Внутри мы уже чистим токен, а этот коллбек нужен чтобы UI
  /// вернулся на экран логина.
  final Future<void> Function()? onUnauthorized;

  ApiClient({
    required this.tokenStorage,
    this.onUnauthorized,
  }) : dio = Dio(
    BaseOptions(
      baseUrl: 'http://5.129.215.252:8081',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokenStorage.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (e, handler) async {
          final status = e.response?.statusCode;

          // Если токен протух/невалиден — чистим токен и возвращаем на логин
          if (status == 401) {
            await tokenStorage.clear();

            if (onUnauthorized != null) {
              try {
                await onUnauthorized!.call();
              } catch (_) {
                // не ломаем запрос, даже если UI коллбек упал
              }
            }
          }

          handler.next(e);
        },
      ),
    );
  }
}
