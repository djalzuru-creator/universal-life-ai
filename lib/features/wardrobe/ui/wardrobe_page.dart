import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../household/data/household_repository.dart';
import '../../household/data/models.dart';
import '../../household/data/providers.dart';
import '../../ai/aguilucho_ai.dart';
import '../../household/ui/common.dart';
import '../data/outfit_suggester.dart';
import '../data/wardrobe_models.dart';
import '../data/wardrobe_repository.dart';
import '../data/weather.dart';
import 'garment_form.dart';
import 'fitting_room.dart';
import 'garment_photo.dart';

typedef _AccessKey = ({String householdId, String memberId});

/// Qué puede hacer el usuario actual en el armario de un miembro.
final _wardrobeAccessProvider =
    FutureProvider.family<Set<PermissionAction>, _AccessKey>((ref, k) async {
      final me = await ref.watch(myMemberProvider(k.householdId).future);
      if (me == null) return {};
      if (me.isOwner) return PermissionAction.values.toSet();
      if (me.id != k.memberId) return {};
      final perms = await ref.watch(permissionsProvider(me.id).future);
      return perms
          .where((p) => p.module == AppModule.wardrobe)
          .expand((p) => p.allowed)
          .toSet();
    });

class WardrobePage extends ConsumerStatefulWidget {
  const WardrobePage({super.key, required this.householdId});
  final String householdId;

  @override
  ConsumerState<WardrobePage> createState() => _WardrobePageState();
}

class _WardrobePageState extends ConsumerState<WardrobePage> {
  String? _memberId;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(myMemberProvider(widget.householdId));
    return me.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(body: ErrorView(e)),
      data: (member) {
        if (member == null) {
          return const Scaffold(
            body: Center(child: Text('No perteneces a este hogar.')),
          );
        }
        final memberId = _memberId ?? member.id;
        final members = member.isOwner
            ? ref.watch(membersProvider(widget.householdId)).value
            : null;
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Armario'),
              actions: [
                if (members != null && members.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: DropdownButton<String>(
                      value: memberId,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final m in members)
                          DropdownMenuItem(
                            value: m.id,
                            child: Text(
                              m.id == member.id ? 'Yo' : m.displayName,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _memberId = v),
                    ),
                  ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.wb_sunny_outlined), text: 'Hoy'),
                  Tab(icon: Icon(Icons.checkroom), text: 'Prendas'),
                  Tab(icon: Icon(Icons.style_outlined), text: 'Conjuntos'),
                  Tab(icon: Icon(Icons.accessibility_new), text: 'Probador'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _TodayTab(
                  householdId: widget.householdId,
                  memberId: memberId,
                  isOwner: member.isOwner,
                ),
                _GarmentsTab(
                  householdId: widget.householdId,
                  memberId: memberId,
                ),
                _OutfitsTab(
                  householdId: widget.householdId,
                  memberId: memberId,
                ),
                Consumer(
                  builder: (context, ref, _) => FittingRoom(
                    householdId: widget.householdId,
                    memberId: memberId,
                    canSave:
                        ref
                            .watch(
                              _wardrobeAccessProvider((
                                householdId: widget.householdId,
                                memberId: memberId,
                              )),
                            )
                            .value
                            ?.contains(PermissionAction.create) ??
                        false,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Hoy: outfit según el tiempo
// ---------------------------------------------------------------------------
class _TodayTab extends ConsumerStatefulWidget {
  const _TodayTab({
    required this.householdId,
    required this.memberId,
    required this.isOwner,
  });
  final String householdId;
  final String memberId;
  final bool isOwner;

  @override
  ConsumerState<_TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends ConsumerState<_TodayTab> {
  int _seed = DateTime.now().day;

  Future<void> _chooseCity() async {
    final city = await showDialog<CityResult>(
      context: context,
      builder: (_) => const _CityDialog(),
    );
    if (city == null) return;
    try {
      await ref
          .read(wardrobeRepositoryProvider)
          .setCity(widget.householdId, city);
      ref.invalidate(householdProvider(widget.householdId));
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final household = ref.watch(householdProvider(widget.householdId));
    return household.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(e),
      data: (h) {
        if (h.latitude == null || h.longitude == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_city_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    widget.isOwner
                        ? 'Elige la ciudad del hogar para proponer la ropa según el tiempo.'
                        : 'Pide al administrador que elija la ciudad del hogar en esta pantalla.',
                    textAlign: TextAlign.center,
                  ),
                  if (widget.isOwner) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _chooseCity,
                      icon: const Icon(Icons.search),
                      label: const Text('Elegir ciudad'),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        final weather = ref.watch(
          todayWeatherProvider((lat: h.latitude!, lon: h.longitude!)),
        );
        final garments = ref.watch(garmentsProvider(widget.memberId));
        return PageBody(
          children: [
            weather.when(
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: LoadingView(),
                ),
              ),
              error: (e, _) => Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_off),
                  title: const Text('No se pudo consultar el tiempo'),
                  trailing: TextButton(
                    onPressed: () => ref.invalidate(
                      todayWeatherProvider((
                        lat: h.latitude!,
                        lon: h.longitude!,
                      )),
                    ),
                    child: const Text('Reintentar'),
                  ),
                ),
              ),
              data: (w) => Card(
                child: ListTile(
                  leading: const Icon(Icons.thermostat, size: 36),
                  title: Text(
                    '${h.cityName ?? 'Tu ciudad'}: ${w.current.round()}° (sensación ${w.feelsLike.round()}°)',
                  ),
                  subtitle: Text(
                    '${w.description} · mín ${w.min.round()}° / máx ${w.max.round()}° · lluvia ${w.rainChance}%',
                  ),
                  trailing: widget.isOwner
                      ? IconButton(
                          tooltip: 'Cambiar ciudad',
                          icon: const Icon(Icons.edit_location_alt_outlined),
                          onPressed: _chooseCity,
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (weather.value case final w?)
              garments.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(e),
                data: (list) {
                  if (list.isEmpty) {
                    return const Text(
                      'Añade tu ropa en la pestaña "Prendas" y aquí verás qué ponerte cada día.',
                      textAlign: TextAlign.center,
                    );
                  }
                  final s = suggestOutfit(
                    wardrobe: list,
                    weather: w,
                    season: Season.of(DateTime.now(), latitude: h.latitude),
                    seed: _seed,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Propuesta para hoy',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _GarmentStrip(s.garments),
                      for (final n in s.notes)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(n)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => setState(() => _seed++),
                            icon: const Icon(Icons.shuffle),
                            label: const Text('Otra combinación'),
                          ),
                          if (s.garments.isNotEmpty)
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(wardrobeRepositoryProvider)
                                      .saveOutfit(
                                        Outfit(
                                          householdId: widget.householdId,
                                          memberId: widget.memberId,
                                          name:
                                              'Conjunto del ${DateTime.now().day}/${DateTime.now().month}',
                                          garmentIds: [
                                            for (final g in s.garments) g.id!,
                                          ],
                                          occasion: 'Día a día',
                                        ),
                                      );
                                  ref.invalidate(
                                    outfitsProvider(widget.memberId),
                                  );
                                  if (context.mounted) {
                                    showSnack(
                                      context,
                                      'Guardado en Conjuntos.',
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    showSnack(context, friendlyError(e));
                                  }
                                }
                              },
                              icon: const Icon(Icons.bookmark_add_outlined),
                              label: const Text('Guardar conjunto'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _AiOutfitCard(
                        garments: list,
                        weather: w,
                        season: Season.of(DateTime.now(), latitude: h.latitude),
                        householdId: widget.householdId,
                        memberId: widget.memberId,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Propuesta según estación, temperatura y lo que tienes en el armario.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

const _occasions = [
  'Día a día',
  'Trabajo',
  'Colegio',
  'Deporte',
  'Fiesta',
  'Cita',
];

/// Aguilucho con IA (Gemini) propone un conjunto y explica por qué.
class _AiOutfitCard extends ConsumerStatefulWidget {
  const _AiOutfitCard({
    required this.garments,
    required this.weather,
    required this.season,
    required this.householdId,
    required this.memberId,
  });
  final List<Garment> garments;
  final TodayWeather weather;
  final Season season;
  final String householdId;
  final String memberId;

  @override
  ConsumerState<_AiOutfitCard> createState() => _AiOutfitCardState();
}

class _AiOutfitCardState extends ConsumerState<_AiOutfitCard> {
  String _occasion = _occasions.first;
  bool _busy = false;
  AiOutfit? _result;
  String? _error;

  Future<void> _ask() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final w = widget.weather;
      final r = await ref
          .read(aguiluchoAiProvider)
          .outfit(
            memberId: widget.memberId,
            season: widget.season.label,
            occasion: _occasion,
            weather: {
              'current': w.current,
              'feels_like': w.feelsLike,
              'min': w.min,
              'max': w.max,
              'rain': w.rainChance,
            },
          );
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final g in widget.garments) g.id: g};
    final picked = [
      for (final id in _result?.garmentIds ?? const <String>[]) ?byId[id],
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pregúntale a Aguilucho',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final o in _occasions)
                  ChoiceChip(
                    label: Text(o),
                    selected: _occasion == o,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _occasion = o),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _ask,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_busy ? 'Pensando…' : '¿Qué me pongo?'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_result case final r?) ...[
              const SizedBox(height: 12),
              if (picked.isNotEmpty) _GarmentStrip(picked),
              if (r.why.isNotEmpty) ...[const SizedBox(height: 8), Text(r.why)],
              if (r.tip.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '💡 ${r.tip}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (picked.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Guardar conjunto'),
                    onPressed: () async {
                      try {
                        await ref
                            .read(wardrobeRepositoryProvider)
                            .saveOutfit(
                              Outfit(
                                householdId: widget.householdId,
                                memberId: widget.memberId,
                                name: 'Aguilucho: $_occasion',
                                garmentIds: [for (final g in picked) g.id!],
                                occasion: _occasion,
                              ),
                            );
                        ref.invalidate(outfitsProvider(widget.memberId));
                        if (context.mounted) {
                          showSnack(context, 'Guardado en Conjuntos.');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showSnack(context, friendlyError(e));
                        }
                      }
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _GarmentStrip extends StatelessWidget {
  const _GarmentStrip(this.garments);
  final List<Garment> garments;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 150,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: garments.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) => SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GarmentPhoto(garments[i], size: 110),
            ),
            const SizedBox(height: 4),
            Text(
              garments[i].name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _CityDialog extends ConsumerStatefulWidget {
  const _CityDialog();
  @override
  ConsumerState<_CityDialog> createState() => _CityDialogState();
}

class _CityDialogState extends ConsumerState<_CityDialog> {
  final _q = TextEditingController();
  List<CityResult> _results = [];
  bool _busy = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(weatherServiceProvider).searchCity(_q.text);
      if (mounted) setState(() => _results = r);
    } catch (_) {
      if (mounted) showSnack(context, 'No se pudo buscar. Revisa la conexión.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ciudad del hogar'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _q,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Ciudad',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _busy ? null : _search,
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 8),
          for (final c in _results)
            ListTile(
              dense: true,
              title: Text(c.name),
              subtitle: Text(c.detail),
              onTap: () => Navigator.pop(context, c),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Prendas
// ---------------------------------------------------------------------------
class _GarmentsTab extends ConsumerStatefulWidget {
  const _GarmentsTab({required this.householdId, required this.memberId});
  final String householdId;
  final String memberId;

  @override
  ConsumerState<_GarmentsTab> createState() => _GarmentsTabState();
}

class _GarmentsTabState extends ConsumerState<_GarmentsTab> {
  GarmentCategory? _filter;

  Future<void> _open(Garment g, Set<PermissionAction> access) async {
    final saved = await showGarmentForm(
      context,
      initial: g,
      canDelete: access.contains(PermissionAction.delete),
    );
    if (saved == true) ref.invalidate(garmentsProvider(widget.memberId));
  }

  @override
  Widget build(BuildContext context) {
    final access =
        ref
            .watch(
              _wardrobeAccessProvider((
                householdId: widget.householdId,
                memberId: widget.memberId,
              )),
            )
            .value ??
        const {};
    final garments = ref.watch(garmentsProvider(widget.memberId));
    return Scaffold(
      floatingActionButton: access.contains(PermissionAction.create)
          ? FloatingActionButton.extended(
              heroTag: 'add-garment',
              onPressed: () => _open(
                Garment(
                  householdId: widget.householdId,
                  memberId: widget.memberId,
                  name: '',
                  category: _filter ?? GarmentCategory.top,
                ),
                access,
              ),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Añadir prenda'),
            )
          : null,
      body: garments.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          e,
          onRetry: () => ref.invalidate(garmentsProvider(widget.memberId)),
        ),
        data: (all) {
          final list = all
              .where((g) => _filter == null || g.category == _filter)
              .toList();
          return PageBody(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: Text('Todo (${all.length})'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  for (final c in GarmentCategory.values)
                    ChoiceChip(
                      label: Text(
                        '${c.label} (${all.where((g) => g.category == c).length})',
                      ),
                      selected: _filter == c,
                      onSelected: (_) => setState(() => _filter = c),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (all.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'El armario está vacío. Pulsa "Añadir prenda" y hazle una foto.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                GridView.extent(
                  maxCrossAxisExtent: 170,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.78,
                  children: [
                    for (final g in list)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: access.contains(PermissionAction.edit)
                            ? () => _open(g, access)
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: GarmentPhoto(g),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              g.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${g.category.label} · ${g.color}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conjuntos
// ---------------------------------------------------------------------------
class _OutfitsTab extends ConsumerWidget {
  const _OutfitsTab({required this.householdId, required this.memberId});
  final String householdId;
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access =
        ref
            .watch(
              _wardrobeAccessProvider((
                householdId: householdId,
                memberId: memberId,
              )),
            )
            .value ??
        const {};
    final outfits = ref.watch(outfitsProvider(memberId));
    final garments =
        ref.watch(garmentsProvider(memberId)).value ?? const <Garment>[];
    final byId = {for (final g in garments) g.id: g};
    final repo = ref.read(wardrobeRepositoryProvider);

    Future<void> run(Future<void> Function() f) async {
      try {
        await f();
        ref.invalidate(outfitsProvider(memberId));
      } catch (e) {
        if (context.mounted) showSnack(context, friendlyError(e));
      }
    }

    return Scaffold(
      floatingActionButton:
          access.contains(PermissionAction.create) && garments.isNotEmpty
          ? FloatingActionButton.extended(
              heroTag: 'add-outfit',
              onPressed: () async {
                final o = await showDialog<Outfit>(
                  context: context,
                  builder: (_) => _OutfitBuilder(
                    householdId: householdId,
                    memberId: memberId,
                    garments: garments,
                  ),
                );
                if (o != null) await run(() => repo.saveOutfit(o));
              },
              icon: const Icon(Icons.add),
              label: const Text('Nuevo conjunto'),
            )
          : null,
      body: outfits.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e),
        data: (list) => PageBody(
          children: [
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'Aún no hay conjuntos. Crea uno o guarda la propuesta de "Hoy".',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final o in list)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  o.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                if (o.occasion != null)
                                  Text(
                                    o.occasion!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                              ],
                            ),
                          ),
                          if (access.contains(PermissionAction.edit))
                            IconButton(
                              tooltip: o.isFavorite
                                  ? 'Quitar de favoritos'
                                  : 'Favorito',
                              icon: Icon(
                                o.isFavorite ? Icons.star : Icons.star_border,
                              ),
                              onPressed: () => run(
                                () => repo.saveOutfit(
                                  Outfit(
                                    id: o.id,
                                    householdId: o.householdId,
                                    memberId: o.memberId,
                                    name: o.name,
                                    garmentIds: o.garmentIds,
                                    occasion: o.occasion,
                                    isFavorite: !o.isFavorite,
                                  ),
                                ),
                              ),
                            ),
                          if (access.contains(PermissionAction.delete))
                            IconButton(
                              tooltip: 'Borrar',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  run(() => repo.deleteOutfit(o.id!)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: OutfitStack([
                          for (final id in o.garmentIds) ?byId[id],
                        ], width: 180),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _OutfitBuilder extends StatefulWidget {
  const _OutfitBuilder({
    required this.householdId,
    required this.memberId,
    required this.garments,
  });
  final String householdId;
  final String memberId;
  final List<Garment> garments;

  @override
  State<_OutfitBuilder> createState() => _OutfitBuilderState();
}

class _OutfitBuilderState extends State<_OutfitBuilder> {
  final _name = TextEditingController();
  final _selected = <String>{};
  String _occasion = garmentStyles.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuevo conjunto'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Cena del sábado',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _occasion,
              decoration: const InputDecoration(labelText: 'Ocasión'),
              items: [
                for (final s in garmentStyles)
                  DropdownMenuItem(value: s, child: Text(s)),
              ],
              onChanged: (v) => setState(() => _occasion = v ?? _occasion),
            ),
            const SizedBox(height: 12),
            Text('Elige las prendas (${_selected.length})'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in widget.garments)
                  GestureDetector(
                    onTap: () => setState(
                      () => _selected.contains(g.id)
                          ? _selected.remove(g.id)
                          : _selected.add(g.id!),
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: GarmentPhoto(g, size: 72),
                        ),
                        if (_selected.contains(g.id))
                          const Positioned(
                            right: 2,
                            top: 2,
                            child: Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.pop(
                context,
                Outfit(
                  householdId: widget.householdId,
                  memberId: widget.memberId,
                  name: _name.text.trim().isEmpty
                      ? 'Conjunto $_occasion'
                      : _name.text.trim(),
                  garmentIds: _selected.toList(),
                  occasion: _occasion,
                ),
              ),
        child: const Text('Guardar'),
      ),
    ],
  );
}
