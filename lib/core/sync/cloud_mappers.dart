import 'dart:convert';

import '../constants/app_constants.dart';
import '../services/secret_cipher_service.dart';
import '../../domain/models/models.dart';
import '../../domain/models/note_model.dart';

/// Serialization between the in-memory domain models and the JSON row shape of
/// the Supabase cloud tables (`supabase/migrations/0002_sync_all_entities.sql`).
///
/// Keys are snake_case and match the cloud columns exactly. `user_id` is never
/// sent — the cloud column defaults to `auth.uid()`. Dates go out as UTC ISO
/// 8601 and come back parsed to local time. Enums use their `.name`.

// ── shared pref keys (settings sync) ─────────────────────────────────────────
const String kPrefEmergencyBuffer = 'finance_emergency_buffer';
const String kPrefCurrencySymbol = 'finance_currency_symbol';
const String kPrefBiometricEnabled = 'finance_biometric_enabled';
const String kPrefRoundUpEnabled = 'finance_round_up_enabled';
const String kPrefAutoBackupEnabled = 'finance_auto_backup_enabled';

// ── cloud table registry ────────────────────────────────────────────────────
const Map<Type, String> kTableForModel = {
  AccountModel: 'accounts',
  CategoryModel: 'categories',
  TransactionModel: 'transactions',
  CardModel: 'credit_cards',
  LoanModel: 'loans',
  BudgetModel: 'budgets',
  RecurringPaymentModel: 'recurring_payments',
  InvestmentModel: 'investments',
  GoalModel: 'goals',
  NoteModel: 'notes',
};

/// Push/pull order: parents before children where it matters, `notes` last.
const List<String> kSyncedTables = <String>[
  'accounts',
  'categories',
  'transactions',
  'credit_cards',
  'loans',
  'budgets',
  'recurring_payments',
  'investments',
  'goals',
  'notes',
];

// ── primitive coercion helpers ──────────────────────────────────────────────
String _iso(DateTime d) => d.toUtc().toIso8601String();
String? _isoN(DateTime? d) => d?.toUtc().toIso8601String();
DateTime _dt(Object? v) => DateTime.parse(v as String).toLocal();
DateTime? _dtN(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
double _d(Object? v) => (v as num).toDouble();
double? _dN(Object? v) => (v as num?)?.toDouble();
int _int(Object? v) => (v as num).toInt();
int? _intN(Object? v) => (v as num?)?.toInt();
bool _bool(Object? v) => v == true;
List<String> _strList(Object? v) =>
    ((v as List?) ?? const <dynamic>[]).map((e) => e.toString()).toList();
List<Map<String, dynamic>> _mapList(Object? v) => ((v as List?) ?? const <dynamic>[])
    .map((e) => (e as Map).cast<String, dynamic>())
    .toList();

// ═══════════════════════════════════════════════════════════════════════════
// Accounts
// ═══════════════════════════════════════════════════════════════════════════
extension AccountCloud on AccountModel {
  Map<String, dynamic> toCloudJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'bank': bank,
        'account_number_last4': accountNumberLast4,
        'enc_account_number': encAccountNumber,
        'enc_ifsc': encIfsc,
        'opening_balance': openingBalance,
        'calculated_balance': calculatedBalance,
        'currency': currency,
        'is_active': isActive,
        'is_deleted': isDeleted,
        'deleted_at': _isoN(isDeleted ? updatedAt : null),
        'created_at': _iso(createdAt),
        'updated_at': _iso(updatedAt),
      };

  static AccountModel fromCloud(Map<String, dynamic> m) => AccountModel(
        id: m['id'] as String,
        name: m['name'] as String,
        type: AccountType.values.byName(m['type'] as String),
        bank: m['bank'] as String?,
        accountNumberLast4: m['account_number_last4'] as String?,
        encAccountNumber: m['enc_account_number'] as String?,
        encIfsc: m['enc_ifsc'] as String?,
        openingBalance: _d(m['opening_balance']),
        calculatedBalance: _d(m['calculated_balance'] ?? m['opening_balance'] ?? 0),
        currency: m['currency'] as String? ?? 'INR',
        isActive: _bool(m['is_active'] ?? true),
        createdAt: _dt(m['created_at']),
        updatedAt: _dt(m['updated_at']),
        isDeleted: _bool(m['is_deleted']),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Categories
// ═══════════════════════════════════════════════════════════════════════════
extension CategoryCloud on CategoryModel {
  Map<String, dynamic> toCloudJson() => {
        'id': id,
        'name': name,
        'parent_id': parentId,
        'type': type,
        'icon': icon,
        'color_hex': colorHex,
        'is_deleted': isDeleted,
        'deleted_at': _isoN(isDeleted ? updatedAt : null),
        'created_at': _iso(updatedAt),
        'updated_at': _iso(updatedAt),
      };

  static CategoryModel fromCloud(Map<String, dynamic> m) => CategoryModel(
        id: m['id'] as String,
        name: m['name'] as String,
        parentId: m['parent_id'] as String?,
        type: m['type'] as String,
        icon: m['icon'] as String? ?? 'tag',
        colorHex: m['color_hex'] as String? ?? '0xFF6366F1',
        updatedAt: _dt(m['updated_at']),
        isDeleted: _bool(m['is_deleted']),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Transactions
// ═══════════════════════════════════════════════════════════════════════════
extension TransactionCloud on TransactionModel {
  Map<String, dynamic> toCloudJson() => {
        'id': id,
        'account_id': accountId,
        'to_account_id': toAccountId,
        'type': type.name,
        'amount': amount,
        'category_id': categoryId,
        'merchant': merchant,
        'date': _iso(date),
        'description': description,
        'notes': notes,
        'credit_card_id': creditCardId,
        'loan_id': loanId,
        'investment_id': investmentId,
        'sync_status': syncStatus.name,
        'tags': tags,
        'splits': splits.map((s) => s.toMap()).toList(),
        'attachment_path': attachmentPath,
        'is_deleted': isDeleted,
        'deleted_at': _isoN(isDeleted ? updatedAt : null),
        'created_at': _iso(createdAt),
        'updated_at': _iso(updatedAt),
      };

  static TransactionModel fromCloud(Map<String, dynamic> m) => TransactionModel(
        id: m['id'] as String,
        accountId: m['account_id'] as String,
        toAccountId: m['to_account_id'] as String?,
        type: TransactionType.values.byName(m['type'] as String),
        amount: _d(m['amount']),
        categoryId: m['category_id'] as String?,
        merchant: m['merchant'] as String?,
        date: _dt(m['date']),
        description: m['description'] as String?,
        notes: m['notes'] as String?,
        tags: _strList(m['tags']),
        splits: _mapList(m['splits']).map(TransactionSplit.fromMap).toList(),
        attachmentPath: m['attachment_path'] as String?,
        creditCardId: m['credit_card_id'] as String?,
        loanId: m['loan_id'] as String?,
        investmentId: m['investment_id'] as String?,
        syncStatus: SyncStatus.values.byName(m['sync_status'] as String? ?? 'synced'),
        createdAt: _dt(m['created_at']),
        updatedAt: _dt(m['updated_at']),
        isDeleted: _bool(m['is_deleted']),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Credit cards
// ═══════════════════════════════════════════════════════════════════════════
extension CardCloud on CardModel {
  Map<String, dynamic> toCloudJson() => {
        'id': id,
        'card_type': cardType.name,
        'name': name,
        'bank': bank,
        'last4': last4,
        'network': network.name,
        'cardholder_name': cardholderName,
        'expiry_month': expiryMonth,
        'expiry_year': expiryYear,
        'color_preset': colorPreset.name,
        'color_hex': colorHex,
        'is_virtual': isVirtual,
        'notes': notes,
        'enc_card_number': encCardNumber,
        'enc_cvv': encCvv,
        'enc_pin': encPin,
        'credit_limit': creditLimit,
        'current_outstanding': currentOutstanding,
        'statement_day': statementDay,
        'due_day': dueDay,
        'linked_account_id': linkedAccountId,
        'balance': balance,
        'currency': currency,
        'last_payment_date': _isoN(lastPaymentDate),
        'last_payment_amount': lastPaymentAmount,
        'is_deleted': isDeleted,
        'deleted_at': _isoN(isDeleted ? updatedAt : null),
        'created_at': _iso(updatedAt),
        'updated_at': _iso(updatedAt),
      };

  static CardModel fromCloud(Map<String, dynamic> m) => CardModel(
        id: m['id'] as String,
        cardType: CardType.values.byName(m['card_type'] as String? ?? 'credit'),
        name: m['name'] as String,
        bank: m['bank'] as String? ?? '',
        last4: m['last4'] as String? ?? '',
        network: CardNetwork.values.byName(m['network'] as String? ?? 'visa'),
        cardholderName: m['cardholder_name'] as String? ?? '',
        expiryMonth: _intN(m['expiry_month']),
        expiryYear: _intN(m['expiry_year']),
        colorPreset: CardColorPreset.values.byName(m['color_preset'] as String? ?? 'midnight'),
        colorHex: m['color_hex'] as String?,
        isVirtual: _bool(m['is_virtual']),
        notes: m['notes'] as String?,
        encCardNumber: m['enc_card_number'] as String?,
        encCvv: m['enc_cvv'] as String?,
        encPin: m['enc_pin'] as String?,
        creditLimit: _d(m['credit_limit'] ?? 0),
        currentOutstanding: _d(m['current_outstanding'] ?? 0),
        statementDay: _int(m['statement_day'] ?? 1),
        dueDay: _int(m['due_day'] ?? 15),
        linkedAccountId: m['linked_account_id'] as String?,
        balance: _dN(m['balance']),
        currency: m['currency'] as String?,
        lastPaymentDate: _dtN(m['last_payment_date']),
        lastPaymentAmount: _dN(m['last_payment_amount']),
        updatedAt: _dt(m['updated_at']),
        isDeleted: _bool(m['is_deleted']),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Loans
// ═══════════════════════════════════════════════════════════════════════════
extension LoanCloud on LoanModel {
  Map<String, dynamic> toCloudJson() => {
        'id': id,
        'name': name,
        'provider': provider,
        'principal_amount': principalAmount,
        'outstanding_amount': outstandingAmount,
        'interest_rate': interestRate,
        'monthly_emi': monthlyEmi,
        'due_day': dueDay,
        'start_date': _iso(startDate),
        'remaining_tenure_months': remainingTenureMonths,
        'is_deleted': isDeleted,
        'deleted_at': _isoN(isDeleted ? updatedAt : null),
        'created_at': _iso(updatedAt),
        'updated_at': _iso(updatedAt),
      };

  static LoanModel fromCloud(Map<String, dynamic> m) => LoanModel(
        id: m['id'] as String,
        name: m['name'] as String,
        provider: m['provider'] as String? ?? '',
        principalAmount: _d(m['principal_amount'] ?? 0),
        outstandingAmount: _d(m['outstanding_amount'] ?? 0),
        interestRate: _d(m['interest_rate'] ?? 0),
        monthlyEmi: _d(m['monthly_emi'] ?? 0),
        dueDay: _int(m['due_day'] ?? 1),
        startDate: _dt(m['start_date']),
        remainingTenureMonths: _int(m['remaining_tenure_months'] ?? 0),
        updatedAt: _dt(m['updated_at']),
        isDeleted: _bool(m['is_deleted']),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Budgets
// ═══════════════════════════════════════════════════════════════════════════
extension BudgetCloud on BudgetModel {
  Map<String, dynamic> toCloudJson() => {
        'id': id,
        'category_id': categoryId,
        'monthly_limit': monthlyLimit,
        'month_year': monthYear,
        'spent_amount': spentAmount,
        'is_deleted': isDeleted,
        'deleted_at': _isoN(isDeleted ? updatedAt : null),
        'created_at': _iso(updatedAt),
        'updated_at': _iso(updatedAt),
      };

  static BudgetModel fromCloud(Map<String, dynamic> m) => BudgetModel(
        id: m['id'] as String,
        categoryId: m['category_id'] as String,
        monthlyLimit: _d(m['monthly_limit'] ?? 0),
        monthYear: m['month_year'] as String,
        spentAmount: _d(m['spent_amount'] ?? 0),
        updatedAt: _dt(m['updated_at']),
        isDeleted: _bool(m['is_deleted']),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Recurring payments
// ═══════════════════════════════════════════════════════════════════════════
extension RecurringPaymentCloud on RecurringPaymentModel {
  Map<String, dynamic> toCloudJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'frequency': frequency.name,
        'next_due_date': _iso(nextDueDate),
        'category_id': categoryId,
        'account_id': accountId,
        'is_auto_pay': isAutoPay,
        'is_deleted': isDeleted,
        'deleted_at': _isoN(isDeleted ? updatedAt : null),
        'created_at': _iso(updatedAt),
        'updated_at': _iso(updatedAt),
      };

  static RecurringPaymentModel fromCloud(Map<String, dynamic> m) => RecurringPaymentModel(
        id: m['id'] as String,
        title: m['title'] as String,
        amount: _d(m['amount'] ?? 0),
        frequency: PaymentFrequency.values.byName(m['frequency'] as String? ?? 'monthly'),
        nextDueDate: _dt(m['next_due_date']),
        categoryId: m['category_id'] as String?,
        accountId: m['account_id'] as String?,
        isAutoPay: _bool(m['is_auto_pay']),
        updatedAt: _dt(m['updated_at']),
        isDeleted: _bool(m['is_deleted']),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Investments
// ═══════════════════════════════════════════════════════════════════════════
extension InvestmentCloud on InvestmentModel {
  Map<String, dynamic> toCloudJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'invested_amount': investedAmount,
        'current_value': currentValue,
        'monthly_sip_amount': monthlySipAmount,
        'sip_day': sipDay,
        'is_deleted': isDeleted,
        'deleted_at': _isoN(isDeleted ? updatedAt : null),
        'created_at': _iso(updatedAt),
        'updated_at': _iso(updatedAt),
      };

  static InvestmentModel fromCloud(Map<String, dynamic> m) => InvestmentModel(
        id: m['id'] as String,
        name: m['name'] as String,
        type: InvestmentType.values.byName(m['type'] as String? ?? 'other'),
        investedAmount: _d(m['invested_amount'] ?? 0),
        currentValue: _d(m['current_value'] ?? 0),
        monthlySipAmount: _d(m['monthly_sip_amount'] ?? 0),
        sipDay: _int(m['sip_day'] ?? 1),
        updatedAt: _dt(m['updated_at']),
        isDeleted: _bool(m['is_deleted']),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Goals
// ═══════════════════════════════════════════════════════════════════════════
extension GoalCloud on GoalModel {
  Map<String, dynamic> toCloudJson() => {
        'id': id,
        'name': name,
        'target_amount': targetAmount,
        'current_saved_amount': currentSavedAmount,
        'target_date': _isoN(targetDate),
        'icon': icon,
        'color_hex': colorHex,
        'is_deleted': isDeleted,
        'deleted_at': _isoN(isDeleted ? updatedAt : null),
        'created_at': _iso(updatedAt),
        'updated_at': _iso(updatedAt),
      };

  static GoalModel fromCloud(Map<String, dynamic> m) => GoalModel(
        id: m['id'] as String,
        name: m['name'] as String,
        targetAmount: _d(m['target_amount'] ?? 0),
        currentSavedAmount: _d(m['current_saved_amount'] ?? 0),
        targetDate: _dtN(m['target_date']),
        icon: m['icon'] as String? ?? 'target',
        colorHex: m['color_hex'] as String? ?? '0xFF6366F1',
        updatedAt: _dt(m['updated_at']),
        isDeleted: _bool(m['is_deleted']),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Notes
// ═══════════════════════════════════════════════════════════════════════════
/// Notes sync ENCRYPTED: `title` / `body` / `checklist_items` / `labels` leave
/// the device (and land in Postgres) as ciphertext, matching what the local
/// Drift columns hold. `fromCloud` decrypts back to the plaintext [NoteModel]
/// the UI uses. Legacy plaintext rows pass through unchanged (see
/// `SecretCipherService.decField`).
extension NoteCloud on NoteModel {
  Map<String, dynamic> toCloudJson() => {
        'id': id,
        'title': SecretCipherService.encField(title),
        'body': SecretCipherService.encField(body),
        'color': color.name,
        'is_pinned': isPinned,
        'is_archived': isArchived,
        'is_checklist': isChecklist,
        'checklist_items':
            SecretCipherService.encField(jsonEncode(checklistItems.map((e) => e.toMap()).toList())),
        'labels': SecretCipherService.encField(jsonEncode(labels)),
        'is_deleted': isDeleted,
        'deleted_at': _isoN(isDeleted ? updatedAt : null),
        'created_at': _iso(createdAt),
        'updated_at': _iso(updatedAt),
      };

  static NoteModel fromCloud(Map<String, dynamic> m) => NoteModel(
        id: m['id'] as String,
        title: SecretCipherService.decField(m['title'] as String? ?? ''),
        body: SecretCipherService.decField(m['body'] as String? ?? ''),
        color: NoteColor.values.byName(m['color'] as String? ?? 'defaultColor'),
        isPinned: _bool(m['is_pinned']),
        isArchived: _bool(m['is_archived']),
        isChecklist: _bool(m['is_checklist']),
        checklistItems: _decNoteJsonList(m['checklist_items'])
            .map((e) => NoteChecklistItem.fromMap((e as Map).cast<String, dynamic>()))
            .toList(),
        labels: _decNoteJsonList(m['labels']).cast<String>(),
        createdAt: _dt(m['created_at']),
        updatedAt: _dt(m['updated_at']),
        isDeleted: _bool(m['is_deleted']),
      );
}

/// A note's checklist/labels come back from the cloud either as an encrypted
/// string (current) or, for legacy rows, as a plain JSON array.
List<dynamic> _decNoteJsonList(dynamic raw) {
  if (raw is List) return raw; // legacy plaintext jsonb array
  if (raw is String) {
    final s = SecretCipherService.decField(raw).trim();
    if (s.isEmpty) return const [];
    try {
      final v = jsonDecode(s);
      return v is List ? v : const [];
    } catch (_) {
      return const [];
    }
  }
  return const [];
}

// ═══════════════════════════════════════════════════════════════════════════
// user_settings (no biometric — device-local only)
// ═══════════════════════════════════════════════════════════════════════════
Map<String, dynamic> settingsToCloudJson(
  String userId, {
  required double emergencyBuffer,
  required String currencySymbol,
  required bool isRoundUpEnabled,
  required bool isAutoBackupEnabled,
  required DateTime updatedAt,
  String? secWrappedDek,
  String? secKekSalt,
  String? secWrappedDekRc,
  String? secRcSalt,
}) {
  return {
    'user_id': userId,
    'emergency_buffer': emergencyBuffer,
    'currency_symbol': currencySymbol,
    'is_round_up_enabled': isRoundUpEnabled,
    'is_auto_backup_enabled': isAutoBackupEnabled,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    // Envelope-encryption key material. The operator sees only ciphertext;
    // useless without the user's password or recovery code.
    'sec_wrapped_dek': secWrappedDek,
    'sec_kek_salt': secKekSalt,
    'sec_wrapped_dek_rc': secWrappedDekRc,
    'sec_rc_salt': secRcSalt,
  };
}

/// Parsed view of a cloud `user_settings` row.
class CloudSettings {
  final double emergencyBuffer;
  final String currencySymbol;
  final bool isRoundUpEnabled;
  final bool isAutoBackupEnabled;
  final DateTime updatedAt;
  final String? secWrappedDek;
  final String? secKekSalt;
  final String? secWrappedDekRc;
  final String? secRcSalt;

  const CloudSettings({
    required this.emergencyBuffer,
    required this.currencySymbol,
    required this.isRoundUpEnabled,
    required this.isAutoBackupEnabled,
    required this.updatedAt,
    this.secWrappedDek,
    this.secKekSalt,
    this.secWrappedDekRc,
    this.secRcSalt,
  });

  factory CloudSettings.fromCloud(Map<String, dynamic> m) => CloudSettings(
        emergencyBuffer: _d(m['emergency_buffer'] ?? 20000),
        currencySymbol: m['currency_symbol'] as String? ?? '₹',
        isRoundUpEnabled: _bool(m['is_round_up_enabled']),
        isAutoBackupEnabled: _bool(m['is_auto_backup_enabled']),
        updatedAt: _dt(m['updated_at'] ?? DateTime.now().toUtc().toIso8601String()),
        secWrappedDek: m['sec_wrapped_dek'] as String?,
        secKekSalt: m['sec_kek_salt'] as String?,
        secWrappedDekRc: m['sec_wrapped_dek_rc'] as String?,
        secRcSalt: m['sec_rc_salt'] as String?,
      );
}
