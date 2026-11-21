import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../household/data/household_repository.dart';
import '../household/data/models.dart';
import '../household/data/providers.dart';
import '../household/ui/common.dart';
import '../household/ui/dashboard_page.dart' show spanishDate;
import '../shopping/ui/shopping_page.dart' show moduleAccessProvider;

const photoBucket = 'family-photos';

class Album {
  const Album(this.id, this.name, this.createdBy);
  final String id;
  final String name;
  final String? createdBy;
  factory Album.fromJson(Map<String, dynamic> j) =>
      Album(j['id'] as String, j['name'] as String, j['created_by'] as String?);
}

class FamilyPhoto {
  const FamilyPhoto({
    required this.id,
    required this.path,
    required this.takenOn,
    this.albumId,
    this.caption,
    this.createdBy,
  });
  final String id;
  final String path;
  final DateTime takenOn;
  final String? albumId;
  final String? caption;
  final String? createdBy;
  factory FamilyPhoto.fromJson(Map<String, dynamic> j) => FamilyPhoto(
    id: j['id'] as String,
    path: j['path'] as String,
    takenOn: DateTime.parse(j['taken_on'] as String),
    albumId: j['album_id'] as String?,
    caption: j['caption'] as String?,
    createdBy: j['created_by'] as String?,
  );
}

final albumsProvider = StreamProvider.family<List<Album>, String>(
  (ref, hid) => ref
      .watch(supabaseProvider)
      .from('albums')
      .stream(primaryKey: ['id'])
      .eq('household_id', hid)
      .order('created_at')
      .map((r) => r.map(Album.fromJson).toList()),
);

final photosProvider = StreamProvider.family<List<FamilyPhoto>, String>(
  (ref, hid) => ref
      .watch(supabaseProvider)
      .from('photos')
      .stream(primaryKey: ['id'])
      .eq('household_id', hid)
      .order('taken_on')
      .map(
        (r) =>
            r.map(FamilyPhoto.fromJson).toList()
              ..sort((a, b) => b.takenOn.compareTo(a.takenOn)),
      ),
);

/// Enlace privado temporal (1 h) de una foto.
final familyPhotoUrlProvider = FutureProvider.family<String, String>(
  (ref, path) => ref
      .watch(supabaseProvider)
      .storage
      .from(photoBucket)
      .createSignedUrl(path, 3600),
);

class PhotosPage extends ConsumerStatefulWidget {
  const PhotosPage({super.key, required this.householdId});
  final String householdId;

  @override
  ConsumerState<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends ConsumerState<PhotosPage> {
  String? _album; // null = todas
  bool _uploading = false;

  SupabaseClient get _db => ref.read(supabaseProvider);

  Future<void> _upload() async {
    final files = await ImagePicker().pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
      limit: 20,
    );
    if (files.isEmpty) return;
    setState(() => _uploading = true);
    var ok = 0, big = 0;
    try {
      for (final f in files) {
        final bytes = await f.readAsBytes();
        if (bytes.lengthInBytes > 2 * 1024 * 1024) {
          big++;
          continue;
        }
        final mime = f.mimeType ?? _mimeOf(f.name);
        final ext = mime == 'image/png'
            ? 'png'
            : mime == 'image/webp'
            ? 'webp'
            : 'jpg';
        final path =
            '${widget.householdId}/${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 20)}.$ext';
        await _db.storage
            .from(photoBucket)
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: mime),
            );
        DateTime? taken;
        try {
          taken = await f.lastModified();
        } catch (_) {}
        await _db.from('photos').insert({
          'household_id': widget.householdId,
          'album_id': _album,
          'path': path,
          if (taken != null)
            'taken_on': taken.toIso8601String().substring(0, 10),
        });
        ok++;
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
        showSnack(
          context,
          [
            if (ok > 0) ok == 1 ? '1 foto subida.' : '$ok fotos subidas.',
            if (big > 0)
              big == 1
                  ? '1 era demasiado grande.'
                  : '$big eran demasiado grandes.',
          ].join(' '),
        );
      }
    }
  }

  static String _mimeOf(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _newAlbum() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo álbum'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Verano 2026, Cumple de Lucía…',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    c.dispose();
    final n = name?.trim() ?? '';
    if (n.isEmpty) return;
    try {
      final row = await _db
          .from('albums')
          .insert({'household_id': widget.householdId, 'name': n})
          .select('id')
          .single();
      setState(() => _album = row['id'] as String);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  void _open(
    List<FamilyPhoto> list,
    int index,
    bool Function(FamilyPhoto) canTouch,
    List<Album> albums,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _Viewer(
          photos: list,
          initial: index,
          canTouch: canTouch,
          albums: albums,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hid = widget.householdId;
    final access =
        ref
            .watch(
              moduleAccessProvider((
                householdId: hid,
                module: AppModule.photos,
              )),
            )
            .value ??
        const {};
    final uid = ref.watch(supabaseProvider).auth.currentUser?.id;
    final canCreate = access.contains(PermissionAction.create);
    bool canTouch(FamilyPhoto p) =>
        access.contains(PermissionAction.delete) ||
        (canCreate && p.createdBy == uid);
    final albums = ref.watch(albumsProvider(hid)).value ?? const <Album>[];
    final photos = ref.watch(photosProvider(hid));

    return Scaffold(
      appBar: AppBar(title: const Text('Fotos de la familia')),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _uploading ? null : _upload,
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_uploading ? 'Subiendo…' : 'Subir fotos'),
            )
          : null,
      body: photos.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            ErrorView(e, onRetry: () => ref.invalidate(photosProvider(hid))),
        data: (all) {
          final list = _album == null
              ? all
              : all.where((p) => p.albumId == _album).toList();
          return PageBody(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: Text('Todas (${all.length})'),
                    selected: _album == null,
                    onSelected: (_) => setState(() => _album = null),
                  ),
                  for (final a in albums)
                    ChoiceChip(
                      label: Text(
                        '${a.name} (${all.where((p) => p.albumId == a.id).length})',
                      ),
                      selected: _album == a.id,
                      onSelected: (_) => setState(() => _album = a.id),
                    ),
                  if (canCreate)
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('Nuevo álbum'),
                      onPressed: _newAlbum,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    'Aún no hay fotos aquí. Pulsa "Subir fotos" para añadir las primeras.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: list.length,
                  itemBuilder: (_, i) => InkWell(
                    onTap: () => _open(list, i, canTouch, albums),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _PhotoImage(list[i].path),
                    ),
                  ),
                ),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }
}

class _PhotoImage extends ConsumerWidget {
  const _PhotoImage(this.path, {this.fit = BoxFit.cover});
  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const fallback = ColoredBox(
      color: Brand.panel2,
      child: Center(child: Icon(Icons.image_outlined, color: Brand.dim)),
    );
    return ref
        .watch(familyPhotoUrlProvider(path))
        .when(
          loading: () => fallback,
          error: (_, _) => fallback,
          data: (url) =>
              Image.network(url, fit: fit, errorBuilder: (_, _, _) => fallback),
        );
  }
}

class _Viewer extends ConsumerStatefulWidget {
  const _Viewer({
    required this.photos,
    required this.initial,
    required this.canTouch,
    required this.albums,
  });
  final List<FamilyPhoto> photos;
  final int initial;
  final bool Function(FamilyPhoto) canTouch;
  final List<Album> albums;

  @override
  ConsumerState<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends ConsumerState<_Viewer> {
  late final _page = PageController(initialPage: widget.initial);
  late int _i = widget.initial;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _delete(FamilyPhoto p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar esta foto?'),
        content: const Text('Se borrará para toda la familia.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(supabaseProvider);
    try {
      await db.from('photos').delete().eq('id', p.id);
      try {
        await db.storage.from(photoBucket).remove([p.path]);
      } catch (_) {}
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  Future<void> _caption(FamilyPhoto p) async {
    final c = TextEditingController(text: p.caption ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descripción'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    c.dispose();
    if (text == null) return;
    try {
      await ref
          .read(supabaseProvider)
          .from('photos')
          .update({'caption': text.trim().isEmpty ? null : text.trim()})
          .eq('id', p.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.photos[_i];
    String? album;
    for (final a in widget.albums) {
      if (a.id == p.albumId) album = a.name;
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        title: Text('${_i + 1} de ${widget.photos.length}'),
        actions: [
          if (widget.canTouch(p)) ...[
            IconButton(
              tooltip: 'Descripción',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _caption(p),
            ),
            IconButton(
              tooltip: 'Borrar',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(p),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _page,
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => _i = i),
              itemBuilder: (_, i) => InteractiveViewer(
                child: Center(
                  child: _PhotoImage(
                    widget.photos[i].path,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.caption != null)
                    Text(
                      p.caption!,
                      style: const TextStyle(fontSize: 16, color: Brand.fg),
                    ),
                  Text(
                    [spanishDate(p.takenOn), ?album].join(' · '),
                    style: const TextStyle(color: Brand.muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
