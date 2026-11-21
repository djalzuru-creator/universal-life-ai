import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool get canSaveFiles => true;

Future<void> saveFile(String name, Uint8List bytes) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/zip'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body!.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}
