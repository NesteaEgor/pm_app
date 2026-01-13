import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

Future<void> saveAndOpenPdf(Uint8List bytes, {required String fileName}) async {
  final dir = await getTemporaryDirectory();
  final safe = fileName.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(' ', '_');
  final file = File('${dir.path}/$safe.pdf');
  await file.writeAsBytes(bytes, flush: true);
  await OpenFilex.open(file.path);
}
