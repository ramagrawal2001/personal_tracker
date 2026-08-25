import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Maps a [CategoryModel.icon] string (a stable identifier stored in the DB)
/// to the Lucide [IconData] it should render as. Keep names lowercase,
/// hyphenated, stable — they're persisted, not just display labels.
const Map<String, IconData> _iconsByName = {
  'tag': LucideIcons.tag,
  'utensils': LucideIcons.utensils,
  'shopping-bag': LucideIcons.shoppingBag,
  'shopping-cart': LucideIcons.shoppingCart,
  'car': LucideIcons.car,
  'home': LucideIcons.home,
  'zap': LucideIcons.zap,
  'briefcase': LucideIcons.briefcase,
  'laptop': LucideIcons.laptop,
  'trending-up': LucideIcons.trendingUp,
  'heart': LucideIcons.heart,
  'plane': LucideIcons.plane,
  'gift': LucideIcons.gift,
  'film': LucideIcons.film,
  'book': LucideIcons.book,
  'coffee': LucideIcons.coffee,
  'phone': LucideIcons.phone,
  'dumbbell': LucideIcons.dumbbell,
  'graduation-cap': LucideIcons.graduationCap,
};

IconData iconForCategoryName(String name) => _iconsByName[name] ?? LucideIcons.tag;

/// (stored name, icon) pairs offered in the category icon picker.
List<MapEntry<String, IconData>> get categoryIconOptions => _iconsByName.entries.toList();
