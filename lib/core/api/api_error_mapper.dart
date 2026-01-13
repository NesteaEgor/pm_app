import 'package:dio/dio.dart';

String userMessageFromError(Object e) {
  if (e is DioException) {
    if (e.response == null) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Таймаут соединения. Попробуйте ещё раз';
        case DioExceptionType.connectionError:
          return 'Нет соединения с сервером';
        default:
          return 'Ошибка сети';
      }
    }

    final status = e.response?.statusCode;
    final data = e.response?.data;

    final msg = _extractMessage(data);
    if (msg != null && msg.trim().isNotEmpty) return msg;

    if (status == 400) return 'Некорректные данные';
    if (status == 401) return 'Нужно войти заново';
    if (status == 403) return 'Недостаточно прав';
    if (status == 404) return 'Не найдено';
    if (status != null && status >= 500) return 'Ошибка сервера. Попробуйте позже';

    return 'Ошибка запроса';
  }

  return 'Что-то пошло не так';
}

String? _extractMessage(dynamic data) {
  if (data is String) return data;
  if (data is Map) {
    final m = data['message'];
    if (m is String && m.trim().isNotEmpty) return m;

    final err = data['error'];
    if (err is String && err.trim().isNotEmpty) return err;
  }
  return null;
}
