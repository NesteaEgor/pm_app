import 'dart:typed_data';
import 'package:dio/dio.dart';

class TaskReportApi {
  final Dio dio;
  TaskReportApi(this.dio);

  Future<Uint8List> downloadReport({
    required String projectId,
    String? role,
    String? status,
  }) async {
    final res = await dio.get(
      '/api/projects/$projectId/tasks/report',
      queryParameters: {
        if (role != null) 'role': role,
        if (status != null) 'status': status,
      },
      options: Options(responseType: ResponseType.bytes),
    );

    return Uint8List.fromList(res.data);
  }
}
