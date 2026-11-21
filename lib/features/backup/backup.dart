import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../household/data/providers.dart';
import '../household/ui/common.dart';
import 'save_file.dart';

/// Nombre válido para un archivo o carpeta en Windows, Mac y móvil.
String safeName(String s) {
  final t = s
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return t.isEmpty ? 'sin nombre' : (t.length > 60 ? t.substring(0, 60) : t);
}

/// Devuelve un nombre que no esté repetido en [used].
String uniqueName(Set<String> used, String base, String ext) {
  var n = '$base.$ext';
  for (var i = 2; used.contains(n); i++) {
    n = '$base ($i).$ext';
  }
  used.add(n);
  return n;
}

String _ext(String path) {
  final i = path.lastIndexOf('.');
  return i < 0 ? 'jpg' : path.substring(i + 1);
}

const _tables = [
  'households',
  'members',
  'pantry_items',
  'shopping_items',
  'expenses',
  'budget_limits',
  'events',
  'garments',
  'outfits',
  'albums',
  'photos',
];

/// Crea un ZIP con una carpeta por persona (Armario y Fotos personales) y datos/*.json.
Future<Uint8List> buildBackup(
  SupabaseClient db,
  String householdId,
  void Function(String) progress,
) async {
  final zip = Archive();
  final data = <String, List<Map<String, dynamic>>>{};
  for (final t in _tables) {
    try {
      final rows = await db
          .from(t)
          .select()
          .eq(t == 'households' ? 'id' : 'household_id', householdId);
      data[t] = List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      data[t] = []; // módulo sin cargar o sin permiso
    }
    final bytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(data[t]),
    );
    zip.addFile(ArchiveFile('datos/$t.json', bytes.length, bytes));
  }

  final members = {
    for (final m in data['members']!)
      m['id'] as String: safeName(m['display_name'] as String),
  };
  final byUser = {
    for (final m in data['members']!)
      if (m['user_id'] != null)
        m['user_id'] as String: safeName(m['display_name'] as String),
  };
  final albums = {
    for (final a in data['albums']!)
      a['id'] as String: safeName(a['name'] as String),
  };

  var done = 0;
  final garments = data['garments']!.where((g) => g['photo_path'] != null);
  final photos = data['photos']!;
  final total = garments.length + photos.length;
  final used = <String>{};

  Future<void> add(
    String bucket,
    String path,
    String folder,
    String base,
  ) async {
    try {
      final bytes = await db.storage.from(bucket).download(path);
      final name = uniqueName(used, '$folder/$base', _ext(path));
      zip.addFile(ArchiveFile(name, bytes.length, bytes));
    } catch (_) {
      // Foto que ya no existe: se salta.
    }
    progress('Copiando fotos… ${++done} de $total');
  }

  for (final g in garments) {
    final who = members[g['member_id']] ?? 'Otros';
    await add(
      'wardrobe',
      g['photo_path'] as String,
      '$who/Armario',
      safeName(g['name'] as String),
    );
  }
  for (final p in photos) {
    final album = albums[p['album_id']] ?? 'Sin álbum';
    final who = byUser[p['created_by']] ?? 'Familia';
    final caption = p['caption'] as String?;
    await add(
      'family-photos',
      p['path'] as String,
      '$who/Fotos personales/$album',
      safeName('${p['taken_on']}${caption == null ? '' : ' $caption'}'),
    );
  }
  progress('Preparando el archivo…');
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

/// Tarjeta para el administrador: descarga la copia en el ordenador.
class BackupCard extends ConsumerStatefulWidget {
  const BackupCard({super.key, required this.householdId});
  final String householdId;

  @override
  ConsumerState<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends ConsumerState<BackupCard> {
  String? _status;

  Future<void> _run() async {
    setState(() => _status = 'Leyendo datos…');
    try {
      final bytes = await buildBackup(
        ref.read(supabaseProvider),
        widget.householdId,
        (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      final d = DateTime.now();
      final stamp =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      await saveFile('copia-familia-$stamp.zip', bytes);
      if (mounted) {
        showSnack(
          context,
          'Copia descargada (${(bytes.length / 1048576).toStringAsFixed(1)} MB). Está en Descargas.',
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, 'No se pudo hacer la copia: $e');
    } finally {
      if (mounted) setState(() => _status = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _status != null;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.backup_outlined),
        title: const Text('Copia de seguridad'),
        subtitle: Text(
          busy
              ? _status!
              : canSaveFiles
              ? 'Descarga un ZIP con una carpeta por persona (Armario y Fotos personales) y todos los datos.'
              : 'Hazla desde el ordenador, entrando en la web de la app.',
        ),
        trailing: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton(
                onPressed: canSaveFiles ? _run : null,
                child: const Text('Descargar'),
              ),
      ),
    );
  }
}
