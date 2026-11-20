import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../household/data/household_repository.dart';
import '../household/data/models.dart';
import '../household/ui/common.dart';
import '../pantry/data/pantry_models.dart';
import '../pantry/data/pantry_repository.dart';
import '../shopping/data/shopping_repository.dart';
import '../shopping/ui/shopping_page.dart' show moduleAccessProvider;

/// Ingrediente de una receta. [keys] son palabras que lo reconocen en la despensa.
class Ingredient {
  const Ingredient(this.name, [this.keys = const [], this.optional = false]);
  final String name;
  final List<String> keys;
  final bool optional;

  List<String> get matchKeys => keys.isEmpty ? [normalize(name)] : keys;
}

class Recipe {
  const Recipe(this.name, this.minutes, this.ingredients, this.steps);
  final String name;
  final int minutes;
  final List<Ingredient> ingredients;
  final List<String> steps;
}

String normalize(String s) {
  const from = 'áéíóúüñ';
  const to = 'aeiouun';
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = from.indexOf(c);
    b.write(i < 0 ? c : to[i]);
  }
  return b.toString().trim();
}

const _sal = Ingredient('Sal', ['sal'], true);
const _aceite = Ingredient('Aceite de oliva', ['aceite'], true);

const recipeCatalog = <Recipe>[
  Recipe(
    'Tortilla de patatas',
    40,
    [
      Ingredient('Huevos', ['huevo']),
      Ingredient('Patatas', ['patata']),
      Ingredient('Cebolla', ['cebolla'], true),
      _aceite,
      _sal,
    ],
    [
      'Pela y corta las patatas (y la cebolla) en láminas finas.',
      'Fríelas a fuego medio en aceite hasta que estén tiernas. Escúrrelas.',
      'Bate los huevos con sal y mézclalos con las patatas.',
      'Cuaja en la sartén por los dos lados.',
    ],
  ),
  Recipe(
    'Macarrones con tomate',
    25,
    [
      Ingredient('Macarrones', ['macarron', 'pasta']),
      Ingredient('Tomate frito', ['tomate']),
      Ingredient('Queso rallado', ['queso'], true),
      Ingredient('Chorizo', ['chorizo'], true),
      _sal,
    ],
    [
      'Cuece la pasta en agua con sal el tiempo del paquete.',
      'Escúrrela y mézclala con el tomate (y el chorizo dorado).',
      'Sirve con queso por encima.',
    ],
  ),
  Recipe(
    'Lentejas estofadas',
    50,
    [
      Ingredient('Lentejas', ['lenteja']),
      Ingredient('Zanahoria', ['zanahoria']),
      Ingredient('Cebolla', ['cebolla']),
      Ingredient('Patata', ['patata'], true),
      Ingredient('Chorizo', ['chorizo'], true),
      _aceite,
      _sal,
    ],
    [
      'Sofríe la cebolla y la zanahoria picadas.',
      'Añade las lentejas, la patata y el chorizo. Cubre con agua.',
      'Cuece 35–40 minutos a fuego suave. Ajusta de sal.',
    ],
  ),
  Recipe(
    'Arroz a la cubana',
    25,
    [
      Ingredient('Arroz', ['arroz']),
      Ingredient('Huevos', ['huevo']),
      Ingredient('Tomate frito', ['tomate']),
      Ingredient('Plátano', ['platano'], true),
      _aceite,
      _sal,
    ],
    [
      'Cuece el arroz y escúrrelo.',
      'Fríe los huevos (y el plátano).',
      'Sirve el arroz con tomate y el huevo encima.',
    ],
  ),
  Recipe(
    'Pollo al horno con patatas',
    60,
    [
      Ingredient('Pollo', ['pollo']),
      Ingredient('Patatas', ['patata']),
      Ingredient('Ajo', ['ajo'], true),
      Ingredient('Limón', ['limon'], true),
      _aceite,
      _sal,
    ],
    [
      'Precalienta el horno a 200 °C.',
      'Pon las patatas en rodajas en la bandeja y el pollo encima con sal, ajo y aceite.',
      'Hornea unos 50 minutos dándole la vuelta a mitad.',
    ],
  ),
  Recipe(
    'Ensalada mixta',
    10,
    [
      Ingredient('Lechuga', ['lechuga']),
      Ingredient('Tomate', ['tomate']),
      Ingredient('Atún', ['atun'], true),
      Ingredient('Huevo', ['huevo'], true),
      Ingredient('Cebolla', ['cebolla'], true),
      _aceite,
      _sal,
    ],
    [
      'Lava y corta la lechuga, el tomate y la cebolla.',
      'Añade atún y huevo cocido.',
      'Aliña con aceite y sal.',
    ],
  ),
  Recipe(
    'Crema de calabacín',
    30,
    [
      Ingredient('Calabacín', ['calabacin']),
      Ingredient('Patata', ['patata']),
      Ingredient('Cebolla', ['cebolla'], true),
      Ingredient('Quesitos', ['quesito', 'queso'], true),
      _aceite,
      _sal,
    ],
    [
      'Rehoga la cebolla, añade calabacín y patata troceados.',
      'Cubre con agua y cuece 20 minutos.',
      'Tritura con los quesitos y ajusta de sal.',
    ],
  ),
  Recipe(
    'Espaguetis carbonara',
    20,
    [
      Ingredient('Espaguetis', ['espagueti', 'pasta']),
      Ingredient('Bacon', ['bacon', 'panceta']),
      Ingredient('Huevos', ['huevo']),
      Ingredient('Queso rallado', ['queso']),
      _sal,
    ],
    [
      'Cuece la pasta. Mientras, dora el bacon.',
      'Bate yemas con queso.',
      'Fuera del fuego, mezcla la pasta caliente con el bacon y el huevo.',
    ],
  ),
  Recipe(
    'Sándwich mixto',
    10,
    [
      Ingredient('Pan de molde', ['pan']),
      Ingredient('Jamón cocido', ['jamon']),
      Ingredient('Queso en lonchas', ['queso']),
      Ingredient('Mantequilla', ['mantequilla'], true),
    ],
    [
      'Monta el pan con jamón y queso.',
      'Tuéstalo en sartén con un poco de mantequilla por los dos lados.',
    ],
  ),
  Recipe(
    'Garbanzos con espinacas',
    20,
    [
      Ingredient('Garbanzos cocidos', ['garbanzo']),
      Ingredient('Espinacas', ['espinaca']),
      Ingredient('Ajo', ['ajo'], true),
      Ingredient('Pimentón', ['pimenton'], true),
      _aceite,
      _sal,
    ],
    [
      'Dora el ajo en aceite y añade las espinacas.',
      'Agrega los garbanzos escurridos y el pimentón.',
      'Cocina 10 minutos y ajusta de sal.',
    ],
  ),
  Recipe(
    'Merluza a la plancha con verduras',
    20,
    [
      Ingredient('Merluza', ['merluza', 'pescado']),
      Ingredient('Calabacín', ['calabacin'], true),
      Ingredient('Pimiento', ['pimiento'], true),
      Ingredient('Limón', ['limon'], true),
      _aceite,
      _sal,
    ],
    [
      'Haz las verduras a la plancha en tiras.',
      'Cocina la merluza 3–4 minutos por lado con sal.',
      'Sirve con unas gotas de limón.',
    ],
  ),
  Recipe(
    'Huevos rotos con jamón',
    25,
    [
      Ingredient('Patatas', ['patata']),
      Ingredient('Huevos', ['huevo']),
      Ingredient('Jamón', ['jamon'], true),
      _aceite,
      _sal,
    ],
    [
      'Fríe las patatas en bastones.',
      'Fríe los huevos y ponlos encima.',
      'Añade el jamón y rompe los huevos al servir.',
    ],
  ),
  Recipe(
    'Albóndigas en salsa de tomate',
    45,
    [
      Ingredient('Carne picada', ['carne picada', 'picada']),
      Ingredient('Huevo', ['huevo']),
      Ingredient('Pan rallado', ['pan rallado', 'pan']),
      Ingredient('Tomate frito', ['tomate']),
      Ingredient('Cebolla', ['cebolla'], true),
      _aceite,
      _sal,
    ],
    [
      'Mezcla la carne con huevo, pan rallado y sal. Forma bolitas.',
      'Dóralas en aceite.',
      'Cuécelas 15 minutos en el tomate con la cebolla.',
    ],
  ),
  Recipe(
    'Yogur con fruta y cereales',
    5,
    [
      Ingredient('Yogur', ['yogur']),
      Ingredient('Fruta', ['platano', 'manzana', 'fresa', 'fruta', 'pera']),
      Ingredient('Cereales o avena', ['cereal', 'avena'], true),
    ],
    ['Pon el yogur en un bol, añade la fruta troceada y los cereales.'],
  ),
  Recipe(
    'Tostadas con tomate',
    5,
    [
      Ingredient('Pan', ['pan']),
      Ingredient('Tomate', ['tomate']),
      _aceite,
      _sal,
    ],
    ['Tuesta el pan, ralla el tomate encima y aliña con aceite y sal.'],
  ),
  Recipe(
    'Arroz con pollo',
    45,
    [
      Ingredient('Arroz', ['arroz']),
      Ingredient('Pollo', ['pollo']),
      Ingredient('Pimiento', ['pimiento'], true),
      Ingredient('Tomate', ['tomate'], true),
      Ingredient('Ajo', ['ajo'], true),
      _aceite,
      _sal,
    ],
    [
      'Dora el pollo troceado y retíralo.',
      'Sofríe pimiento, ajo y tomate. Añade el arroz y el doble de agua.',
      'Vuelve a poner el pollo y cuece 18 minutos.',
    ],
  ),
];

class RecipeMatch {
  RecipeMatch(this.recipe, this.have, this.missing, this.usesExpiring);
  final Recipe recipe;
  final List<Ingredient> have;
  final List<Ingredient> missing;
  final int usesExpiring;

  List<Ingredient> get required =>
      recipe.ingredients.where((i) => !i.optional).toList();
  int get haveRequired => have.where((i) => !i.optional).length;
  List<Ingredient> get missingRequired =>
      missing.where((i) => !i.optional).toList();
  double get score => required.isEmpty ? 1 : haveRequired / required.length;
}

/// Ordena el catálogo según lo que hay en la despensa (cantidad > 0).
/// Primero las que puedes hacer ya, y entre ellas las que gastan lo que caduca.
List<RecipeMatch> matchRecipes(
  List<PantryItem> pantry, {
  DateTime? today,
  List<Recipe> catalog = recipeCatalog,
}) {
  final now = today ?? DateTime.now();
  final stock = [
    for (final p in pantry)
      if (p.quantity > 0) (name: normalize(p.name), item: p),
  ];
  PantryItem? find(Ingredient ing) {
    for (final s in stock) {
      if (ing.matchKeys.any(s.name.contains)) return s.item;
    }
    return null;
  }

  final result = <RecipeMatch>[];
  for (final r in catalog) {
    final have = <Ingredient>[];
    final missing = <Ingredient>[];
    var expiring = 0;
    for (final ing in r.ingredients) {
      final p = find(ing);
      if (p == null) {
        missing.add(ing);
      } else {
        have.add(ing);
        final s = p.expiry(now);
        if (s == ExpiryStatus.soon || s == ExpiryStatus.expired) expiring++;
      }
    }
    result.add(RecipeMatch(r, have, missing, expiring));
  }
  result.sort((a, b) {
    final s = b.score.compareTo(a.score);
    if (s != 0) return s;
    final e = b.usesExpiring.compareTo(a.usesExpiring);
    if (e != 0) return e;
    return a.recipe.minutes.compareTo(b.recipe.minutes);
  });
  return result;
}

class RecipesPage extends ConsumerWidget {
  const RecipesPage({super.key, required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pantryAccess =
        ref
            .watch(
              moduleAccessProvider((
                householdId: householdId,
                module: AppModule.pantry,
              )),
            )
            .value ??
        const {};
    final shopAccess =
        ref
            .watch(
              moduleAccessProvider((
                householdId: householdId,
                module: AppModule.shopping,
              )),
            )
            .value ??
        const {};
    final canAddToList = shopAccess.contains(PermissionAction.create);
    final pantry = pantryAccess.contains(PermissionAction.view)
        ? ref.watch(pantryItemsProvider(householdId)).value ?? const []
        : const <PantryItem>[];
    final matches = matchRecipes(pantry);
    final ready = matches.where((m) => m.missingRequired.isEmpty).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Recetas')),
      body: PageBody(
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.kitchen_outlined),
              title: Text(
                ready == 0
                    ? 'Con tu despensa aún no sale ninguna receta completa'
                    : ready == 1
                    ? 'Puedes hacer 1 receta con lo que tienes'
                    : 'Puedes hacer $ready recetas con lo que tienes',
              ),
              subtitle: const Text(
                'Primero salen las que gastan lo que caduca antes.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final m in matches)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text('${m.haveRequired}/${m.required.length}'),
                ),
                title: Text(m.recipe.name),
                subtitle: Text(
                  [
                    '${m.recipe.minutes} min',
                    if (m.missingRequired.isEmpty)
                      'Lo tienes todo'
                    else
                      'Falta: ${m.missingRequired.map((i) => i.name).join(', ')}',
                    if (m.usesExpiring > 0) 'Aprovecha lo que caduca',
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, ref, m, canAddToList),
              ),
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _open(
    BuildContext context,
    WidgetRef ref,
    RecipeMatch m,
    bool canAddToList,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Text(m.recipe.name, style: Theme.of(ctx).textTheme.headlineSmall),
            Text('${m.recipe.minutes} minutos'),
            const SizedBox(height: 16),
            Text('Ingredientes', style: Theme.of(ctx).textTheme.titleMedium),
            for (final i in m.recipe.ingredients)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  m.have.contains(i)
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: m.have.contains(i) ? Colors.green : null,
                ),
                title: Text(i.optional ? '${i.name} (opcional)' : i.name),
              ),
            if (canAddToList && m.missing.isNotEmpty) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.add_shopping_cart),
                label: Text(
                  m.missingRequired.isEmpty
                      ? 'Añadir opcionales a la compra'
                      : 'Añadir lo que falta a la compra',
                ),
                onPressed: () async {
                  final list = m.missingRequired.isEmpty
                      ? m.missing
                      : m.missingRequired;
                  try {
                    final repo = ref.read(shoppingRepositoryProvider);
                    for (final i in list) {
                      await repo.add(
                        ShoppingItem(householdId: householdId, name: i.name),
                      );
                    }
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      showSnack(
                        context,
                        list.length == 1
                            ? '1 producto añadido a la compra.'
                            : '${list.length} productos añadidos a la compra.',
                      );
                    }
                  } catch (e) {
                    if (ctx.mounted) showSnack(ctx, friendlyError(e));
                  }
                },
              ),
            ],
            const SizedBox(height: 16),
            Text('Pasos', style: Theme.of(ctx).textTheme.titleMedium),
            for (final (n, s) in m.recipe.steps.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${n + 1}. $s'),
              ),
          ],
        ),
      ),
    );
  }
}
