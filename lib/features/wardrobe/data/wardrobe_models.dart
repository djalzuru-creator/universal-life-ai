import 'package:flutter/material.dart';

enum GarmentCategory {
  top('Parte de arriba', Icons.checkroom),
  bottom('Pantalón o falda', Icons.straighten),
  dress('Vestido o mono', Icons.woman),
  outerwear('Abrigo o chaqueta', Icons.ac_unit),
  shoes('Calzado', Icons.directions_walk),
  accessory('Complemento', Icons.watch_outlined);

  const GarmentCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum Season {
  spring('Primavera'),
  summer('Verano'),
  autumn('Otoño'),
  winter('Invierno');

  const Season(this.label);
  final String label;

  /// Estación según el mes; en el hemisferio sur se invierte.
  static Season of(DateTime d, {double? latitude}) {
    const north = [
      Season.winter,
      Season.winter,
      Season.spring,
      Season.spring,
      Season.spring,
      Season.summer,
      Season.summer,
      Season.summer,
      Season.autumn,
      Season.autumn,
      Season.autumn,
      Season.winter,
    ];
    final s = north[d.month - 1];
    if (latitude == null || latitude >= 0) return s;
    return switch (s) {
      Season.winter => Season.summer,
      Season.summer => Season.winter,
      Season.spring => Season.autumn,
      Season.autumn => Season.spring,
    };
  }
}

/// Paleta sencilla para clasificar prendas.
const garmentColors = <String, Color>{
  'negro': Color(0xFF212121),
  'blanco': Color(0xFFFAFAFA),
  'gris': Color(0xFF9E9E9E),
  'azul': Color(0xFF1E5AA8),
  'vaquero': Color(0xFF5C7EA6),
  'rojo': Color(0xFFC62828),
  'rosa': Color(0xFFEC8FB0),
  'verde': Color(0xFF2E7D32),
  'amarillo': Color(0xFFF9C80E),
  'naranja': Color(0xFFEF6C00),
  'marrón': Color(0xFF6D4C41),
  'beige': Color(0xFFD7C4A3),
  'morado': Color(0xFF6A1B9A),
  'estampado': Color(0xFFB0BEC5),
};

const garmentStyles = [
  'Casual',
  'Elegante',
  'Deportivo',
  'Trabajo',
  'Fiesta',
  'Clásico',
  'Urbano',
];

const warmthLabels = {1: 'Fresca', 2: 'Media', 3: 'De abrigo'};

class Garment {
  const Garment({
    this.id,
    required this.householdId,
    required this.memberId,
    required this.name,
    required this.category,
    this.color = 'negro',
    this.seasons = const {
      Season.spring,
      Season.summer,
      Season.autumn,
      Season.winter,
    },
    this.styles = const {},
    this.warmth = 2,
    this.photoPath,
    this.isShared = false,
  });

  final String? id;
  final String householdId;
  final String memberId;
  final String name;
  final GarmentCategory category;
  final String color;
  final Set<Season> seasons;
  final Set<String> styles;
  final int warmth;
  final String? photoPath;
  final bool isShared;

  Garment copyWith({String? photoPath}) => Garment(
    id: id,
    householdId: householdId,
    memberId: memberId,
    name: name,
    category: category,
    color: color,
    seasons: seasons,
    styles: styles,
    warmth: warmth,
    photoPath: photoPath ?? this.photoPath,
    isShared: isShared,
  );

  factory Garment.fromJson(Map<String, dynamic> j) => Garment(
    id: j['id'] as String,
    householdId: j['household_id'] as String,
    memberId: j['member_id'] as String,
    name: j['name'] as String,
    category: GarmentCategory.values.byName(j['category'] as String),
    color: j['color'] as String,
    seasons: {
      for (final s in (j['seasons'] as List)) Season.values.byName(s as String),
    },
    styles: {for (final s in (j['styles'] as List)) s as String},
    warmth: (j['warmth'] as num).toInt(),
    photoPath: j['photo_path'] as String?,
    isShared: j['is_shared'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'household_id': householdId,
    'member_id': memberId,
    'name': name,
    'category': category.name,
    'color': color,
    'seasons': [for (final s in seasons) s.name],
    'styles': styles.toList(),
    'warmth': warmth,
    'photo_path': photoPath,
    'is_shared': isShared,
  };
}

class Outfit {
  const Outfit({
    this.id,
    required this.householdId,
    required this.memberId,
    required this.name,
    required this.garmentIds,
    this.occasion,
    this.isFavorite = false,
  });

  final String? id;
  final String householdId;
  final String memberId;
  final String name;
  final List<String> garmentIds;
  final String? occasion;
  final bool isFavorite;

  factory Outfit.fromJson(Map<String, dynamic> j) => Outfit(
    id: j['id'] as String,
    householdId: j['household_id'] as String,
    memberId: j['member_id'] as String,
    name: j['name'] as String,
    garmentIds: [for (final g in (j['garment_ids'] as List)) g as String],
    occasion: j['occasion'] as String?,
    isFavorite: j['is_favorite'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'household_id': householdId,
    'member_id': memberId,
    'name': name,
    'garment_ids': garmentIds,
    'occasion': occasion,
    'is_favorite': isFavorite,
  };
}
