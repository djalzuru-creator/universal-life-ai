import 'dart:typed_data';

bool get canSaveFiles => false;

Future<void> saveFile(String name, Uint8List bytes) async =>
    throw UnsupportedError('Solo desde el navegador');
