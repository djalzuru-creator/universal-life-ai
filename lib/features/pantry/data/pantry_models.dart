enum PantryLocation {
  fridge('Nevera'),
  freezer('Congelador'),
  pantry('Despensa'),
  other('Otros');

  const PantryLocation(this.label);
  final String label;
}

const pantryUnits = ['ud', 'g', 'kg', 'ml', 'l'];

enum ExpiryStatus { none, ok, soon, expired }

class PantryItem {
  const PantryItem({
    this.id,
    required this.householdId,
    required this.name,
    this.brand,
    this.barcode,
    this.quantity = 1,
    this.unit = 'ud',
    this.location = PantryLocation.pantry,
    this.expiresOn,
    this.price,
    this.imageUrl,
  });

  final String? id;
  final String householdId;
  final String name;
  final String? brand;
  final String? barcode;
  final double quantity;
  final String unit;
  final PantryLocation location;
  final DateTime? expiresOn;
  final double? price;
  final String? imageUrl;

  /// Días hasta la caducidad (negativo si ya caducó).
  int? daysLeft(DateTime today) {
    final e = expiresOn;
    if (e == null) return null;
    final t = DateTime(today.year, today.month, today.day);
    return DateTime(e.year, e.month, e.day).difference(t).inDays;
  }

  ExpiryStatus expiry(DateTime today) {
    final d = daysLeft(today);
    if (d == null) return ExpiryStatus.none;
    if (d < 0) return ExpiryStatus.expired;
    if (d <= 3) return ExpiryStatus.soon;
    return ExpiryStatus.ok;
  }

  String get quantityLabel {
    final q = quantity == quantity.roundToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
    return '$q $unit';
  }

  factory PantryItem.fromJson(Map<String, dynamic> j) => PantryItem(
    id: j['id'] as String,
    householdId: j['household_id'] as String,
    name: j['name'] as String,
    brand: j['brand'] as String?,
    barcode: j['barcode'] as String?,
    quantity: (j['quantity'] as num).toDouble(),
    unit: j['unit'] as String,
    location: PantryLocation.values.byName(j['location'] as String),
    expiresOn: j['expires_on'] == null
        ? null
        : DateTime.parse(j['expires_on'] as String),
    price: (j['price'] as num?)?.toDouble(),
    imageUrl: j['image_url'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'household_id': householdId,
    'name': name,
    'brand': brand,
    'barcode': barcode,
    'quantity': quantity,
    'unit': unit,
    'location': location.name,
    'expires_on': expiresOn == null
        ? null
        : '${expiresOn!.year.toString().padLeft(4, '0')}-'
              '${expiresOn!.month.toString().padLeft(2, '0')}-'
              '${expiresOn!.day.toString().padLeft(2, '0')}',
    'price': price,
    'image_url': imageUrl,
  };
}
