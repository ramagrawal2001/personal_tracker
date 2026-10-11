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
  static MerchantCategoryMapping _m(String pattern, String name, String cat) =>
      MerchantCategoryMapping(pattern: pattern, merchantName: name, categoryId: cat);

  static final List<MerchantCategoryMapping> _rules = [
    // Food & dining
    _m('swiggy instamart', 'Swiggy Instamart', 'cat_groceries'),
    _m('swiggy', 'Swiggy', 'cat_food'),
    _m('zomato', 'Zomato', 'cat_food'),
    _m('dominos', "Domino's", 'cat_food'),
    _m("domino's", "Domino's", 'cat_food'),
    _m('mcdonald', "McDonald's", 'cat_food'),
    _m('kfc', 'KFC', 'cat_food'),
    _m('starbucks', 'Starbucks', 'cat_food'),
    _m('pizza hut', 'Pizza Hut', 'cat_food'),
    _m('burger king', 'Burger King', 'cat_food'),
    _m('chai', 'Chai', 'cat_food'),
    _m('restaurant', 'Restaurant', 'cat_food'),
    _m('cafe', 'Cafe', 'cat_food'),
    _m('dinner', 'Dinner', 'cat_food'),
    _m('lunch', 'Lunch', 'cat_food'),
    _m('breakfast', 'Breakfast', 'cat_food'),
    _m('snacks', 'Snacks', 'cat_food'),
    _m('coffee', 'Coffee', 'cat_food'),
    _m('tea', 'Tea', 'cat_food'),
    _m('food', 'Food', 'cat_food'),
    // Groceries
    _m('blinkit', 'Blinkit', 'cat_groceries'),
    _m('zepto', 'Zepto', 'cat_groceries'),
    _m('bigbasket', 'BigBasket', 'cat_groceries'),
    _m('big basket', 'BigBasket', 'cat_groceries'),
    _m('dmart', 'DMart', 'cat_groceries'),
    _m('jiomart', 'JioMart', 'cat_groceries'),
    _m('grocery', 'Groceries', 'cat_groceries'),
    _m('groceries', 'Groceries', 'cat_groceries'),
    _m('vegetables', 'Vegetables', 'cat_groceries'),
    _m('milk', 'Milk', 'cat_groceries'),
    // Shopping
    _m('amazon', 'Amazon', 'cat_shopping'),
    _m('flipkart', 'Flipkart', 'cat_shopping'),
    _m('myntra', 'Myntra', 'cat_shopping'),
    _m('ajio', 'Ajio', 'cat_shopping'),
    _m('meesho', 'Meesho', 'cat_shopping'),
    _m('nykaa', 'Nykaa', 'cat_shopping'),
    _m('croma', 'Croma', 'cat_shopping'),
    _m('reliance digital', 'Reliance Digital', 'cat_shopping'),
    _m('decathlon', 'Decathlon', 'cat_shopping'),
    // Transport & fuel
    _m('uber', 'Uber', 'cat_transport'),
    _m('ola', 'Ola Cabs', 'cat_transport'),
    _m('rapido', 'Rapido', 'cat_transport'),
    _m('irctc', 'IRCTC', 'cat_transport'),
    _m('redbus', 'redBus', 'cat_transport'),
    _m('metro', 'Metro', 'cat_transport'),
    _m('fastag', 'FASTag', 'cat_transport'),
    _m('indigo', 'IndiGo', 'cat_transport'),
    _m('petrol', 'Petrol', 'cat_transport'),
    _m('diesel', 'Diesel', 'cat_transport'),
    _m('fuel', 'Fuel', 'cat_transport'),
    _m('shell', 'Shell Petrol', 'cat_transport'),
    _m('indian oil', 'Indian Oil Petrol', 'cat_transport'),
    _m('bharat petroleum', 'Bharat Petroleum', 'cat_transport'),
    _m('hpcl', 'HP Petrol', 'cat_transport'),
    _m('auto', 'Auto', 'cat_transport'),
    _m('cab', 'Cab', 'cat_transport'),
    // Bills & subscriptions
    _m('netflix', 'Netflix', 'cat_bills'),
    _m('spotify', 'Spotify', 'cat_bills'),
    _m('hotstar', 'Disney+ Hotstar', 'cat_bills'),
    _m('prime video', 'Prime Video', 'cat_bills'),
    _m('youtube premium', 'YouTube Premium', 'cat_bills'),
    _m('airtel', 'Airtel', 'cat_bills'),
    _m('jio', 'Jio', 'cat_bills'),
    _m('vodafone', 'Vi', 'cat_bills'),
    _m('bsnl', 'BSNL', 'cat_bills'),
    _m('electricity', 'Electricity', 'cat_bills'),
    _m('recharge', 'Recharge', 'cat_bills'),
    _m('broadband', 'Broadband', 'cat_bills'),
    _m('gas', 'Gas', 'cat_bills'),
    // Housing
    _m('rent', 'Rent', 'cat_housing'),
    _m('maintenance', 'Maintenance', 'cat_housing'),
    // Investments
    _m('zerodha', 'Zerodha', 'cat_investment'),
    _m('groww', 'Groww', 'cat_investment'),
    _m('sip', 'SIP', 'cat_investment'),
    // Income
    _m('salary', 'Salary', 'cat_salary'),
  ];

  static final Map<String, RegExp> _patternCache = {};

  /// Automatically deduce merchant name and category from a raw description string (e.g. "INR 2,450 debited at AMAZON IN").
  /// Patterns match on word boundaries, so "ola" doesn't fire on "Motorola".
  static MerchantCategoryMapping? categorize(String description) {
    final lower = description.toLowerCase();
    for (var rule in _rules) {
      final re = _patternCache.putIfAbsent(
        rule.pattern,
        () => RegExp('(^|[^a-z0-9])${RegExp.escape(rule.pattern)}(\$|[^a-z0-9])'),
      );
      if (re.hasMatch(lower)) {
        return rule;
      }
    }
    return null;
  }
}
