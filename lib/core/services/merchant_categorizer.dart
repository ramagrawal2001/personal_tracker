class MerchantCategoryMapping {
  final String pattern;
  final String merchantName;
  final String categoryId;

  MerchantCategoryMapping({
    required this.pattern,
    required this.merchantName,
    required this.categoryId,
  });
}

class MerchantCategorizer {
  static final List<MerchantCategoryMapping> _rules = [
    MerchantCategoryMapping(pattern: 'swiggy', merchantName: 'Swiggy', categoryId: 'cat_food'),
    MerchantCategoryMapping(pattern: 'zomato', merchantName: 'Zomato', categoryId: 'cat_food'),
    MerchantCategoryMapping(pattern: 'amazon', merchantName: 'Amazon', categoryId: 'cat_shopping'),
    MerchantCategoryMapping(pattern: 'flipkart', merchantName: 'Flipkart', categoryId: 'cat_shopping'),
    MerchantCategoryMapping(pattern: 'uber', merchantName: 'Uber', categoryId: 'cat_transport'),
    MerchantCategoryMapping(pattern: 'ola', merchantName: 'Ola Cabs', categoryId: 'cat_transport'),
    MerchantCategoryMapping(pattern: 'shell', merchantName: 'Shell Petrol', categoryId: 'cat_transport'),
    MerchantCategoryMapping(pattern: 'indian oil', merchantName: 'Indian Oil Petrol', categoryId: 'cat_transport'),
    MerchantCategoryMapping(pattern: 'netflix', merchantName: 'Netflix', categoryId: 'cat_bills'),
    MerchantCategoryMapping(pattern: 'spotify', merchantName: 'Spotify', categoryId: 'cat_bills'),
  ];

  /// Automatically deduce merchant name and category from a raw description string (e.g. "INR 2,450 debited at AMAZON IN")
  static MerchantCategoryMapping? categorize(String description) {
    final lower = description.toLowerCase();
    for (var rule in _rules) {
      if (lower.contains(rule.pattern)) {
        return rule;
      }
    }
    return null;
  }
}
