import 'package:flutter/material.dart';

/// Maps the stable string key persisted with each [Category] to a Material
/// icon, and exposes the palette of keys the icon picker offers. Keeping the
/// mapping in one place means the model layer stays free of Flutter types.
class CategoryIcons {
  CategoryIcons._();

  static const Map<String, IconData> _map = {
    'category': Icons.category,
    'restaurant': Icons.restaurant,
    'fastfood': Icons.fastfood,
    'grocery': Icons.local_grocery_store,
    'home': Icons.home,
    'bolt': Icons.bolt,
    'receipt': Icons.receipt_long,
    'water': Icons.water_drop,
    'wifi': Icons.wifi,
    'phone': Icons.smartphone,
    'car': Icons.directions_car,
    'fuel': Icons.local_gas_station,
    'flight': Icons.flight,
    'health': Icons.local_hospital,
    'medical': Icons.medical_services,
    'fitness': Icons.fitness_center,
    'school': Icons.school,
    'book': Icons.menu_book,
    'shopping': Icons.shopping_bag,
    'clothing': Icons.checkroom,
    'movie': Icons.movie,
    'games': Icons.sports_esports,
    'sports': Icons.sports_soccer,
    'coffee': Icons.coffee,
    'gift': Icons.card_giftcard,
    'pets': Icons.pets,
    'child': Icons.child_care,
    'bank': Icons.account_balance,
    'card': Icons.credit_card,
    'cash': Icons.payments,
    'savings': Icons.savings,
    'shield': Icons.shield,
    'subscriptions': Icons.subscriptions,
    'celebration': Icons.celebration,
    'beauty': Icons.spa,
    'donation': Icons.volunteer_activism,
  };

  /// The icon for a key, falling back to a generic tag for unknown keys.
  static IconData byKey(String key) => _map[key] ?? Icons.category;

  /// All keys, in registry order — the choices shown in the icon picker.
  static List<String> get keys => _map.keys.toList();
}
